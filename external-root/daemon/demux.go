package main

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"
)

type replayConnection struct {
	net.Conn
	prefix *bytes.Reader
}

var errDirectConnection = errors.New("connection_not_redirected")

func (c *replayConnection) Read(b []byte) (int, error) {
	if c.prefix.Len() > 0 {
		return c.prefix.Read(b)
	}
	return c.Conn.Read(b)
}

type demuxListener struct {
	net.Listener
	target      string
	destination func(net.Conn) (string, error)
	journal     *eventLog
	ready       chan net.Conn
	failed      chan error
	done        chan struct{}
	once        sync.Once
	version     string
}

func newDemux(base net.Listener, target string, destination func(net.Conn) (string, error), journal *eventLog, versions ...string) *demuxListener {
	listener := &demuxListener{Listener: base, target: strings.TrimSuffix(strings.ToLower(target), "."), destination: destination, journal: journal, ready: make(chan net.Conn, 16), failed: make(chan error, 1), done: make(chan struct{})}
	listener.version = "1.0.79"
	if len(versions) > 0 {
		listener.version = versions[0]
	}
	go func() {
		for {
			connection, err := base.Accept()
			if err != nil {
				select {
				case listener.failed <- err:
				default:
				}
				return
			}
			go listener.classify(connection)
		}
	}()
	return listener
}
func (l *demuxListener) Accept() (net.Conn, error) {
	select {
	case connection := <-l.ready:
		return connection, nil
	case err := <-l.failed:
		return nil, err
	case <-l.done:
		return nil, net.ErrClosed
	}
}
func (l *demuxListener) Close() error {
	var err error
	l.once.Do(func() { close(l.done); err = l.Listener.Close() })
	return err
}
func (l *demuxListener) classify(connection net.Conn) {
	id := fmt.Sprintf("tls-%x", time.Now().UnixNano())
	destination, err := l.destination(connection)
	if err != nil || destination == l.Listener.Addr().String() {
		stage := "original_destination_unavailable"
		if errors.Is(err, errDirectConnection) {
			stage = "direct_connection_ignored"
		}
		l.journal.emit(id, stage, 0, 0, 0)
		_ = connection.Close()
		return
	}
	_ = connection.SetReadDeadline(time.Now().Add(10 * time.Second))
	prefix, host, err := readHello(connection)
	_ = connection.SetReadDeadline(time.Time{})
	if err != nil {
		l.journal.emit(id, "client_hello_incomplete", 0, 0, 0)
		_ = connection.Close()
		return
	}
	wrapped := &replayConnection{connection, bytes.NewReader(prefix)}
	if host == l.target {
		l.journal.emit(id, "login_tls_selected", 0, 0, 0)
		select {
		case l.ready <- wrapped:
		case <-l.done:
			_ = connection.Close()
		}
		return
	}
	remote, err := net.DialTimeout("tcp", destination, 10*time.Second)
	if err != nil {
		l.journal.emit(id, "passthrough_connect_failed", 0, 0, 0)
		_ = connection.Close()
		return
	}
	defer remote.Close()
	defer connection.Close()
	stage := "other_tls_passthrough"
	if len(prefix) > 0 && prefix[0] == 'S' {
		stage = "sp_stream_selected"
	}
	l.journal.emit(id, stage, 0, 0, 0)
	finished := make(chan struct{})
	go func() {
		if len(prefix) > 0 && prefix[0] == 'S' {
			relayLobbyFrames(remote, wrapped, l.version, l.journal, id)
		} else {
			_, _ = io.Copy(remote, wrapped)
		}
		if tcp, ok := remote.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
		close(finished)
	}()
	_, _ = io.Copy(connection, remote)
	_ = remote.Close()
	_ = connection.Close()
	<-finished
}

func readHello(reader io.Reader) ([]byte, string, error) {
	var raw, handshake []byte
	for len(raw) < 100*1024 {
		header := make([]byte, 5)
		n, err := io.ReadFull(reader, header[:1])
		raw = append(raw, header[:n]...)
		if err != nil {
			return raw, "", err
		}
		if header[0] != 22 {
			return raw, "", nil
		}
		n, err = io.ReadFull(reader, header[1:])
		raw = append(raw, header[1:1+n]...)
		if err != nil {
			return raw, "", err
		}
		size := int(binary.BigEndian.Uint16(header[3:]))
		if size == 0 || size > 18432 {
			return raw, "", nil
		}
		record := make([]byte, size)
		n, err = io.ReadFull(reader, record)
		raw = append(raw, record[:n]...)
		if err != nil {
			return raw, "", err
		}
		handshake = append(handshake, record...)
		if len(handshake) >= 4 {
			if handshake[0] != 1 {
				return raw, "", nil
			}
			size := int(handshake[1])<<16 | int(handshake[2])<<8 | int(handshake[3])
			if size > 65536 {
				return raw, "", nil
			}
			if len(handshake) >= size+4 {
				return raw, helloName(handshake[4 : 4+size]), nil
			}
		}
	}
	return raw, "", nil
}
func helloName(hello []byte) string {
	at := 34
	if len(hello) <= at {
		return ""
	}
	session := int(hello[at])
	at++
	if at+session+2 > len(hello) {
		return ""
	}
	at += session
	ciphers := int(binary.BigEndian.Uint16(hello[at:]))
	at += 2
	if at+ciphers+1 > len(hello) {
		return ""
	}
	at += ciphers
	compression := int(hello[at])
	at++
	if at+compression+2 > len(hello) {
		return ""
	}
	at += compression
	extensions := int(binary.BigEndian.Uint16(hello[at:]))
	at += 2
	if at+extensions > len(hello) {
		return ""
	}
	end := at + extensions
	for at+4 <= end {
		kind := binary.BigEndian.Uint16(hello[at:])
		size := int(binary.BigEndian.Uint16(hello[at+2:]))
		at += 4
		if at+size > end {
			return ""
		}
		data := hello[at : at+size]
		at += size
		if kind != 0 {
			continue
		}
		if len(data) < 2 {
			return ""
		}
		limit := int(binary.BigEndian.Uint16(data)) + 2
		if limit > len(data) {
			return ""
		}
		for p := 2; p+3 <= limit; {
			kind := data[p]
			length := int(binary.BigEndian.Uint16(data[p+1:]))
			p += 3
			if p+length > limit {
				return ""
			}
			if kind == 0 && length > 0 && length <= 253 {
				host := strings.TrimSuffix(strings.ToLower(string(data[p:p+length])), ".")
				for _, c := range host {
					if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '.' || c == '-') {
						return ""
					}
				}
				return host
			}
			p += length
		}
	}
	return ""
}
