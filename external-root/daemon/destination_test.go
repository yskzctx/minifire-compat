package main

import (
	"errors"
	"net"
	"strings"
	"syscall"
	"testing"
)

func TestProcDestinationMatchesExactClientEndpointAndUID(t *testing.T) {
	rows := ` sl local_address rem_address st tx_queue rx tr uid
 0: 0403020A:C350 0A7100CB:01BB 01 00000000:00000000 00:00000000 00000000 10240 0 123
 1: 0403020A:C350 016433C6:01BB 01 00000000:00000000 00:00000000 00000000 10456 0 124
 2: 0403020A:C351 016433C6:01BB 01 00000000:00000000 00:00000000 00000000 10240 0 125
 `
	peer := &net.TCPAddr{IP: net.ParseIP("10.2.3.4"), Port: 50000}
	got, err := procDestination(peer, 10240, []string{rows})
	if err != nil || got != "203.0.113.10:443" {
		t.Fatal(got, err)
	}
	if _, err := procDestination(peer, 10567, []string{rows}); err == nil {
		t.Fatal("wrong UID matched")
	}
}
func TestProcDestinationRejectsAmbiguityAndProxySelfDestination(t *testing.T) {
	peer := &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 50000}
	row := "0: 0100007F:C350 0A7100CB:01BB 01 0:0 00:0 0 10240 0 1\n"
	if _, err := procDestination(peer, 10240, []string{row + strings.ReplaceAll(row, "0A7100CB", "0B7100CB")}); err == nil {
		t.Fatal("ambiguous endpoint selected")
	}
	local := strings.ReplaceAll(row, "0A7100CB:01BB", "0100007F:480B")
	if _, err := procDestination(peer, 10240, []string{local}); !errors.Is(err, errDirectConnection) {
		t.Fatal("proxy recursion allowed", err)
	}
}
func TestProcDestinationParsesIPv6AndMappedIPv4(t *testing.T) {
	row := "0: 0000000000000000FFFF00000403020A:C350 B80D0120000000000000000001000000:01BB 01 0:0 00:0 0 10240 0 1\n"
	got, err := procDestination(&net.TCPAddr{IP: net.ParseIP("10.2.3.4"), Port: 50000}, 10240, []string{row})
	if err != nil || got != "[2001:db8::1]:443" {
		t.Fatal(got, err)
	}
}
func TestDestinationResolverRecoversAfterKernelSocketOptionFails(t *testing.T) {
	client, peer := net.Pipe()
	defer client.Close()
	defer peer.Close()
	connection := &endpointConn{Conn: client, remote: &net.TCPAddr{IP: net.ParseIP("10.2.3.4"), Port: 50000}}
	row := "0: 0403020A:C350 0A7100CB:01BB 01 0:0 00:0 0 10240 0 1\n"
	result, method, err := recoverDestination(connection, 10240, func(net.Conn) (string, error) { return "", errors.New("fixture ENOPROTOOPT") }, func() ([]string, error) { return []string{row}, nil })
	if err != nil || result != "203.0.113.10:443" || method != "proc_client_tuple" {
		t.Fatal(result, method, err)
	}
}

type endpointConn struct {
	net.Conn
	remote net.Addr
}

func (c *endpointConn) RemoteAddr() net.Addr { return c.remote }
func TestDestinationResolverPreservesErrorsAndIgnoresLocalProbe(t *testing.T) {
	client, peer := net.Pipe()
	defer client.Close()
	defer peer.Close()
	kernel := func(net.Conn) (string, error) { return "", syscall.Errno(92) }
	tables := func() ([]string, error) { return nil, errors.New("fixture proc permission denied") }
	c := &endpointConn{Conn: client, remote: &net.TCPAddr{IP: net.ParseIP("10.2.3.4"), Port: 50000}}
	_, _, err := recoverDestination(c, 10240, kernel, tables)
	if err == nil || !strings.Contains(err.Error(), "errno=92") || !strings.Contains(err.Error(), "permission denied") {
		t.Fatal("error details lost", err)
	}
	c.remote = &net.TCPAddr{IP: net.ParseIP("127.0.0.1"), Port: 50000}
	_, _, err = recoverDestination(c, 10240, kernel, func() ([]string, error) { return []string{""}, nil })
	if !errors.Is(err, errDirectConnection) {
		t.Fatal("unrelated localhost probe not ignored", err)
	}
}
