//go:build linux

package main

import (
	"context"
	"errors"
	"net"
	"os"
	"os/exec"
	"syscall"
	"testing"
	"time"
)

// Runs only in an explicitly selected root Linux test environment. It opens
// loopback TCP sockets and changes only the helper child's UID, not networking.
func TestLiveProcResolutionWithApplicationUID(t *testing.T) {
	if os.Geteuid() != 0 || os.Getenv("MINIFIRE_LIVE_PROC_TEST") != "1" {
		t.Skip("explicit root Linux test environment required")
	}
	listener, err := net.Listen("tcp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	listener.(*net.TCPListener).SetDeadline(time.Now().Add(5 * time.Second))
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	child := exec.CommandContext(ctx, os.Args[0], "-test.run=^TestLiveProcClientHelper$")
	child.Env = append(os.Environ(), "MINIFIRE_PROC_CLIENT="+listener.Addr().String())
	child.SysProcAttr = &syscall.SysProcAttr{Credential: &syscall.Credential{Uid: 12345, Gid: 12345}}
	if err = child.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if child.ProcessState == nil {
			child.Process.Kill()
			child.Wait()
		}
	}()
	connection, err := listener.Accept()
	if err != nil {
		t.Fatal(err)
	}
	destination, method, err := recoverDestination(connection, 12345, func(net.Conn) (string, error) { return "", errors.New("forced unsupported kernel socket option") }, readProcTCPTables)
	connection.Close()
	if err != nil || method != "proc_client_tuple" || destination != listener.Addr().String() {
		t.Fatalf("real Linux TCP/UID recovery: %q %q %v", destination, method, err)
	}
	if err = child.Wait(); err != nil {
		t.Fatal(err)
	}
}

func TestLiveProcClientHelper(t *testing.T) {
	address := os.Getenv("MINIFIRE_PROC_CLIENT")
	if address == "" {
		t.Skip("helper process only")
	}
	if os.Getuid() != 12345 {
		t.Fatal("wrong helper UID")
	}
	connection, err := net.DialTimeout("tcp4", address, 3*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer connection.Close()
	connection.SetReadDeadline(time.Now().Add(5 * time.Second))
	connection.Read(make([]byte, 1))
}
