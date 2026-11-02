package main

import (
	"bufio"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"strconv"
	"strings"
	"syscall"
)

var errTargetSocketMissing = errors.New("target_client_socket_not_found")
var errTargetSocketAmbiguous = errors.New("target_client_socket_ambiguous")

func procEndpoint(encoded string) (*net.TCPAddr, error) {
	parts := strings.Split(encoded, ":")
	if len(parts) != 2 {
		return nil, errors.New("proc_endpoint_invalid")
	}
	raw, err := hex.DecodeString(parts[0])
	if err != nil || (len(raw) != 4 && len(raw) != 16) {
		return nil, errors.New("proc_ip_invalid")
	}
	// The supported ARM64 Android ABI prints each address word in native order.
	for at := 0; at < len(raw); at += 4 {
		raw[at], raw[at+3] = raw[at+3], raw[at]
		raw[at+1], raw[at+2] = raw[at+2], raw[at+1]
	}
	port, err := strconv.ParseUint(parts[1], 16, 16)
	if err != nil || port == 0 {
		return nil, errors.New("proc_port_invalid")
	}
	return &net.TCPAddr{IP: net.IP(raw), Port: int(port)}, nil
}

func procDestination(peer *net.TCPAddr, uid int, tables []string) (string, error) {
	if peer == nil || peer.IP == nil || uid < 10000 {
		return "", errors.New("client_identity_invalid")
	}
	matches := map[string]bool{}
	for _, table := range tables {
		scanner := bufio.NewScanner(strings.NewReader(table))
		for scanner.Scan() {
			fields := strings.Fields(scanner.Text())
			if len(fields) < 8 || fields[3] == "0A" || fields[3] == "06" {
				continue
			}
			owner, err := strconv.Atoi(fields[7])
			if err != nil || owner != uid {
				continue
			}
			local, err := procEndpoint(fields[1])
			if err != nil || local.Port != peer.Port || !local.IP.Equal(peer.IP) {
				continue
			}
			remote, err := procEndpoint(fields[2])
			if err != nil || remote.IP.IsUnspecified() {
				continue
			}
			matches[remote.String()] = true
		}
		if scanner.Err() != nil {
			return "", errors.New("proc_table_scan_failed")
		}
	}
	if len(matches) == 0 {
		return "", errTargetSocketMissing
	}
	if len(matches) != 1 {
		return "", errTargetSocketAmbiguous
	}
	for address := range matches {
		host, port, _ := net.SplitHostPort(address)
		if ip := net.ParseIP(host); ip != nil && ip.IsLoopback() && port == "18443" {
			return "", errDirectConnection
		}
		return address, nil
	}
	return "", errTargetSocketMissing
}

func readProcTCPTables() ([]string, error) {
	tables := []string{}
	for _, path := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		file, err := os.Open(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, fmt.Errorf("proc_table_open_failed: %w", err)
		}
		data, err := io.ReadAll(io.LimitReader(file, 8*1024*1024+1))
		file.Close()
		if err != nil {
			return nil, errors.New("proc_table_read_failed")
		}
		if len(data) > 8*1024*1024 {
			return nil, errors.New("proc_table_oversized")
		}
		tables = append(tables, string(data))
	}
	if len(tables) == 0 {
		return nil, errors.New("proc_tables_unavailable")
	}
	return tables, nil
}

func recoverDestination(connection net.Conn, uid int, kernel func(net.Conn) (string, error), readTables func() ([]string, error)) (string, string, error) {
	destination, kernelErr := kernel(connection)
	if kernelErr == nil {
		host, port, err := net.SplitHostPort(destination)
		ip := net.ParseIP(host)
		number, numberErr := strconv.Atoi(port)
		if err == nil && ip != nil && !ip.IsUnspecified() && numberErr == nil && number > 0 && number <= 65535 && !(ip.IsLoopback() && port == "18443") {
			return destination, "kernel_sockopt", nil
		}
		kernelErr = errors.New("kernel_destination_is_local_or_invalid")
	}
	var errno syscall.Errno
	if errors.As(kernelErr, &errno) {
		kernelErr = fmt.Errorf("errno=%d (%v)", int(errno), errno)
	}
	peer, ok := connection.RemoteAddr().(*net.TCPAddr)
	if !ok {
		return "", "", fmt.Errorf("original_destination_failed: kernel=%v; peer_not_tcp", kernelErr)
	}
	tables, err := readTables()
	if err == nil {
		destination, err = procDestination(peer, uid, tables)
		if err == nil {
			return destination, "proc_client_tuple", nil
		}
	}
	if errors.Is(err, errDirectConnection) || (errors.Is(err, errTargetSocketMissing) && peer.IP.IsLoopback()) {
		return "", "", errDirectConnection
	}
	return "", "", fmt.Errorf("original_destination_failed: kernel=%v; proc=%w", kernelErr, err)
}
