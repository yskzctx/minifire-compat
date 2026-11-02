package main

import (
	"bytes"
	"context"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestDirectConnectionsCannotReachTLSHandler(t *testing.T) {
	client, peer := net.Pipe()
	defer peer.Close()
	var journal bytes.Buffer
	listener := &demuxListener{destination: func(net.Conn) (string, error) {
		return "", errDirectConnection
	}, journal: &eventLog{w: &journal}}
	listener.classify(client)
	if !bytes.Contains(journal.Bytes(), []byte("direct_connection_ignored")) {
		t.Fatal("direct connection was not rejected before reading its TLS data")
	}
	if _, err := peer.Read(make([]byte, 1)); err != io.EOF {
		t.Fatalf("direct connection was not closed: %v", err)
	}
}

func TestOtherTLSHostKeepsItsOriginalEndToEndConnection(t *testing.T) {
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("original TLS")) }))
	defer upstream.Close()
	base, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	demux := newDemux(base, "login.minifire.cn", func(net.Conn) (string, error) { return upstream.Listener.Addr().String(), nil }, &eventLog{w: io.Discard})
	defer demux.Close()
	transport := upstream.Client().Transport.(*http.Transport).Clone()
	transport.DialContext = func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", demux.Addr().String())
	}
	transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	transport.TLSClientConfig.ServerName = "example.com"
	client := &http.Client{Transport: transport}
	defer transport.CloseIdleConnections()
	response, err := client.Get("https://example.com/fixture")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if string(body) != "original TLS" {
		t.Fatal("passthrough failed")
	}
}

func TestLoginHostIsDeliveredToLocalTLSHandler(t *testing.T) {
	state := t.TempDir()
	if err := prepareIdentity(state); err != nil {
		t.Fatal(err)
	}
	base, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	demux := newDemux(base, "login.minifire.cn", func(net.Conn) (string, error) { return "203.0.113.10:443", nil }, &eventLog{w: io.Discard})
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("local TLS")) })}
	go server.ServeTLS(demux, filepath.Join(state, "server.pem"), filepath.Join(state, "server.key"))
	defer server.Close()
	ca, _ := os.ReadFile(filepath.Join(state, "ca.pem"))
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(ca)
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, ServerName: "login.minifire.cn"}, DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "tcp", demux.Addr().String())
	}}
	defer transport.CloseIdleConnections()
	response, err := (&http.Client{Transport: transport}).Get("https://login.minifire.cn/fixture")
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	body, _ := io.ReadAll(response.Body)
	if string(body) != "local TLS" {
		t.Fatal("login selection failed")
	}
}

func TestTransparentListenerAlsoHandlesSPFrames(t *testing.T) {
	upstream, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer upstream.Close()
	go func() {
		connection, err := upstream.Accept()
		if err == nil {
			defer connection.Close()
			_, _ = io.Copy(connection, connection)
		}
	}()
	base, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	demux := newDemux(base, "login.minifire.cn", func(net.Conn) (string, error) { return upstream.Addr().String(), nil }, &eventLog{w: io.Discard})
	defer demux.Close()
	login := appendField(nil, 9, 0, integer(1))
	login = appendField(login, 4, 0, integer(23))
	login = appendField(login, 13, 2, []byte("1.0.77"))
	packet := appendField(nil, 1, 2, appendField(nil, 1, 0, integer(10000)))
	packet = appendField(packet, 2, 2, login)
	original := append([]byte("SP"), binary.LittleEndian.AppendUint32(nil, uint32(len(packet)))...)
	original = append(original, packet...)
	changed, _ := rewriteLobby(packet, "1.0.79")
	expected := append([]byte("SP"), binary.LittleEndian.AppendUint32(nil, uint32(len(changed)))...)
	expected = append(expected, changed...)
	client, err := net.Dial("tcp", demux.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	_, _ = client.Write(original)
	_ = client.(*net.TCPConn).CloseWrite()
	result, err := io.ReadAll(client)
	if err != nil || !bytes.Equal(result, expected) {
		t.Fatal("transparent SP relay failed")
	}
}
