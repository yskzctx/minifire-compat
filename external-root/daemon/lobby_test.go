package main

import (
	"bytes"
	"encoding/binary"
	"io"
	"net"
	"testing"
)

func TestNativeLobbyRelayRewritesRealSocketStream(t *testing.T) {
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
	proxy, err := startLobby("127.0.0.1:0", func() string { return upstream.Addr().String() }, "1.0.79", &eventLog{w: io.Discard})
	if err != nil {
		t.Fatal(err)
	}
	defer proxy.Close()
	login := appendField(nil, 9, 0, integer(1))
	login = appendField(login, 4, 0, integer(23))
	login = appendField(login, 13, 2, []byte("1.0.77"))
	packet := appendField(nil, 1, 2, appendField(nil, 1, 0, integer(10000)))
	packet = appendField(packet, 2, 2, login)
	frame := append([]byte("SP"), binary.LittleEndian.AppendUint32(nil, uint32(len(packet)))...)
	frame = append(frame, packet...)
	expected, _ := rewriteLobby(packet, "1.0.79")
	header := append([]byte("SP"), binary.LittleEndian.AppendUint32(nil, uint32(len(expected)))...)
	expected = append(header, expected...)
	client, err := net.Dial("tcp", proxy.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	for _, b := range frame {
		if _, err = client.Write([]byte{b}); err != nil {
			t.Fatal(err)
		}
	}
	_ = client.(*net.TCPConn).CloseWrite()
	result, err := io.ReadAll(client)
	if err != nil || !bytes.Equal(result, expected) {
		t.Fatal("native relay failed")
	}
}
