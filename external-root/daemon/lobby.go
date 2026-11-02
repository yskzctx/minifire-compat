package main

import (
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"time"
)

func startLobby(address string, destination func() string, version string, journal *eventLog) (net.Listener, error) {
	host, _, err := net.SplitHostPort(address)
	if err != nil || net.ParseIP(host) == nil || !net.ParseIP(host).IsLoopback() {
		return nil, fmt.Errorf("lobby_listener_must_be_loopback")
	}
	listener, err := net.Listen("tcp", address)
	if err != nil {
		return nil, err
	}
	go func() {
		for {
			client, err := listener.Accept()
			if err != nil {
				return
			}
			go func() {
				defer client.Close()
				id := fmt.Sprintf("lobby-%x", time.Now().UnixNano())
				target := destination()
				if target == "" {
					journal.emit(id, "lobby_endpoint_missing", 0, 0, 0)
					return
				}
				remote, err := net.DialTimeout("tcp", target, 10*time.Second)
				if err != nil {
					journal.emit(id, "lobby_connect_failed", 0, 0, 0)
					return
				}
				defer remote.Close()
				journal.emit(id, "lobby_connected", 0, 0, 0)
				done := make(chan struct{})
				go func() {
					defer close(done)
					relayLobbyFrames(remote, client, version, journal, id)
					if tcp, ok := remote.(*net.TCPConn); ok {
						_ = tcp.CloseWrite()
					}
				}()
				_, _ = io.Copy(client, remote)
				_ = client.Close()
				_ = remote.Close()
				<-done
				journal.emit(id, "lobby_closed", 0, 0, 0)
			}()
		}
	}()
	return listener, nil
}

func relayLobbyFrames(destination io.Writer, source io.Reader, version string, journal *eventLog, id string) {
	first := true
	for {
		header := make([]byte, 6)
		n, err := io.ReadFull(source, header)
		if err != nil {
			if n > 0 {
				_, _ = destination.Write(header[:n])
				journal.emit(id, "lobby_partial_header", 0, n, 0)
			}
			return
		}
		size := binary.LittleEndian.Uint32(header[2:])
		if string(header[:2]) != "SP" || size > maxBody {
			_, _ = destination.Write(header)
			journal.emit(id, "lobby_wire_unrecognized", 0, 0, 0)
			_, _ = io.Copy(destination, source)
			return
		}
		body := make([]byte, int(size))
		n, err = io.ReadFull(source, body)
		if err != nil {
			_, _ = destination.Write(header)
			_, _ = destination.Write(body[:n])
			journal.emit(id, "lobby_partial_body", 0, n, 0)
			return
		}
		result, changed := rewriteLobby(body, version)
		if changed {
			binary.LittleEndian.PutUint32(header[2:], uint32(len(result)))
			journal.emit(id, "lobby_login_rewritten", 0, len(body), len(result))
		} else {
			fields, err := parseFields(body)
			login := false
			if err == nil {
				head, err := parseFields(value(fields, 1))
				login = err == nil && number(head, 1) == 10000
			}
			if login {
				journal.emit(id, "lobby_login_profile_unrecognized", 0, len(body), 0)
			} else if first {
				journal.emit(id, "lobby_initial_frame_passthrough", 0, len(body), 0)
			}
		}
		first = false
		if _, err = destination.Write(header); err != nil {
			return
		}
		if _, err = destination.Write(result); err != nil {
			return
		}
	}
}
