package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

func run() error {
	if len(os.Args) > 1 && os.Args[1] == "prepare" {
		flags := flag.NewFlagSet("prepare", flag.ContinueOnError)
		apk := flags.String("apk", "", "installed base APK path")
		state := flags.String("state", "", "private state directory")
		if err := flags.Parse(os.Args[2:]); err != nil {
			return err
		}
		if *apk == "" || *state == "" {
			return fmt.Errorf("prepare_configuration_missing")
		}
		material, err := materialFromAPK(*apk)
		if err != nil {
			return err
		}
		if err = prepareIdentity(*state); err != nil {
			return err
		}
		if err = writePrivate(*state, "material", material); err != nil {
			return err
		}
		fmt.Println("prepared")
		return nil
	}
	listen := flag.String("listen", "127.0.0.1:18443", "loopback listener")
	upstream := flag.String("upstream", "https://login.minifire.cn", "fixed upstream HTTPS origin")
	materialPath := flag.String("material-file", "", "private local signing material")
	certificate := flag.String("cert", "", "TLS certificate file")
	key := flag.String("key", "", "TLS private key file")
	journalPath := flag.String("journal", "", "private diagnostic JSONL path")
	version := flag.String("target-version", "1.0.79", "iOS login version declaration")
	lobbyListen := flag.String("lobby-listen", "127.0.0.1:19000", "loopback lobby listener")
	routeScript := flag.String("route-script", "", "optional root routing script")
	gameUID := flag.Int("game-uid", 0, "target application UID for root routing")
	readyFile := flag.String("ready-file", "", "optional startup marker")
	fatalFile := flag.String("fatal-file", "", "optional client trust failure marker")
	flag.Parse()
	host, _, err := net.SplitHostPort(*listen)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
		return fmt.Errorf("listener_must_be_loopback")
	}
	if *materialPath == "" || *certificate == "" || *key == "" || *journalPath == "" {
		return fmt.Errorf("missing_configuration_files")
	}
	for _, path := range []string{*materialPath, *key} {
		info, err := os.Stat(path)
		if err != nil || !info.Mode().IsRegular() {
			return fmt.Errorf("private_file_unavailable")
		}
		if runtime.GOOS != "windows" && info.Mode().Perm()&0077 != 0 {
			return fmt.Errorf("private_file_permissions_must_be_0600")
		}
	}
	material, err := os.ReadFile(*materialPath)
	if err != nil {
		return fmt.Errorf("material_read_failed")
	}
	origin, err := url.Parse(*upstream)
	if err != nil {
		return fmt.Errorf("upstream_url_invalid")
	}
	if err = os.MkdirAll(filepath.Dir(*journalPath), 0700); err != nil {
		return fmt.Errorf("journal_directory_failed")
	}
	journal := &eventLog{path: *journalPath}
	route := func(action string, args ...string) error {
		if *routeScript == "" {
			return nil
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		commandArgs := append([]string{*routeScript, action}, args...)
		output, err := exec.CommandContext(ctx, "sh", commandArgs...).CombinedOutput()
		if err != nil {
			if len(output) > 65536 {
				output = output[:65536]
			}
			_ = writePrivate(filepath.Dir(*materialPath), "route-error.txt", output)
			return fmt.Errorf("route_%s_failed", action)
		}
		return nil
	}
	var destination atomic.Value
	destination.Store("")
	if *routeScript == "" {
		lobby, err := startLobby(*lobbyListen, func() string { return destination.Load().(string) }, *version, journal)
		if err != nil {
			return fmt.Errorf("lobby_listener_failed")
		}
		defer lobby.Close()
	}
	onLobby := func(address string) error {
		if address == "" {
			destination.Store("")
			if err := route("lobby_clear"); err != nil {
				if *fatalFile != "" {
					_ = os.WriteFile(*fatalFile, []byte("routing_reset_failed\n"), 0600)
				}
				return err
			}
			return nil
		}
		host, port, err := net.SplitHostPort(address)
		if err != nil {
			return fmt.Errorf("lobby_address_invalid")
		}
		number, err := strconv.Atoi(port)
		if err != nil || number < 1 || number > 65535 {
			return fmt.Errorf("lobby_port_invalid")
		}
		if *routeScript != "" {
			return route("lobby", strconv.Itoa(number))
		}
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		addresses, err := net.DefaultResolver.LookupIPAddr(ctx, host)
		if err != nil {
			return fmt.Errorf("lobby_dns_failed")
		}
		var ip net.IP
		for _, entry := range addresses {
			if v4 := entry.IP.To4(); v4 != nil && v4.IsGlobalUnicast() && !v4.IsPrivate() && !v4.IsLoopback() {
				ip = v4
				break
			}
		}
		if ip == nil {
			return fmt.Errorf("lobby_public_ipv4_missing")
		}
		destination.Store(net.JoinHostPort(ip.String(), strconv.Itoa(number)))
		return nil
	}
	handler, err := newProxy(origin, material, *version, nil, journal, onLobby)
	if err != nil {
		return err
	}
	pair, err := tls.LoadX509KeyPair(*certificate, *key)
	if err != nil {
		return fmt.Errorf("tls_keypair_invalid")
	}
	listener, err := net.Listen("tcp", *listen)
	if err != nil {
		return fmt.Errorf("listener_failed")
	}
	defer listener.Close()
	if *routeScript != "" {
		if *listen != "127.0.0.1:18443" {
			return fmt.Errorf("root_listener_port_invalid")
		}
		ipv6, err := net.Listen("tcp6", "[::1]:18443")
		if err != nil {
			return fmt.Errorf("ipv6_listener_failed")
		}
		defer ipv6.Close()
		listener = mergeListeners(listener, ipv6)
		if *gameUID < 10000 {
			return fmt.Errorf("game_uid_invalid")
		}
		if err = route("init", strconv.Itoa(*gameUID)); err != nil {
			return err
		}
		defer route("stop")
		base := listener
		listener = newDemux(base, origin.Hostname(), func(connection net.Conn) (string, error) {
			destination, err := originalDestination(connection)
			host, port, _ := net.SplitHostPort(destination)
			ip := net.ParseIP(host)
			if err == nil && ip != nil && ip.IsLoopback() && port == "18443" {
				return "", errDirectConnection
			}
			if err != nil {
				if *fatalFile != "" {
					_ = os.WriteFile(*fatalFile, []byte("original_destination_unavailable\n"), 0600)
				}
				return "", fmt.Errorf("original_destination_unavailable")
			}
			return destination, nil
		}, journal, *version)
		defer listener.Close()
	}
	server := &http.Server{Handler: handler, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: 60 * time.Second,
		TLSConfig: &tls.Config{MinVersion: tls.VersionTLS12, Certificates: []tls.Certificate{pair}}}
	server.ErrorLog = log.New(&tlsLogWriter{journal: journal, fatalPath: *fatalFile}, "", 0)
	journal.emit("service", "listener_ready", 0, 0, 0)
	journal.emit("service", "mode_external_zero_game_hooks", 0, 0, 0)
	if journal.lastError != nil {
		return fmt.Errorf("journal_write_failed")
	}
	if *readyFile != "" {
		if err = os.WriteFile(*readyFile, []byte("ready\n"), 0600); err != nil {
			return fmt.Errorf("ready_marker_failed")
		}
		defer os.Remove(*readyFile)
	}
	stopped, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	go func() {
		<-stopped.Done()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = server.Shutdown(ctx)
	}()
	err = server.Serve(tls.NewListener(listener, server.TLSConfig))
	if err == http.ErrServerClosed {
		return nil
	}
	return err
}

type tlsLogWriter struct {
	journal   *eventLog
	fatalPath string
}

func (w *tlsLogWriter) Write(data []byte) (int, error) {
	stage := "client_tls_handshake_failed"
	message := string(data)
	if strings.Contains(message, "remote error: tls: bad certificate") || strings.Contains(message, "unknown certificate authority") {
		stage = "client_certificate_rejected"
		if w.fatalPath != "" {
			_ = os.WriteFile(w.fatalPath, []byte(stage+"\n"), 0600)
		}
	}
	w.journal.emit("service", stage, 0, 0, 0)
	return len(data), nil
}

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}
