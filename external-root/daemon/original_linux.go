//go:build linux

package main

import (
	"encoding/binary"
	"fmt"
	"net"
	"strconv"
	"syscall"
	"unsafe"
)

func originalDestination(connection net.Conn) (string, error) {
	tcp, ok := connection.(*net.TCPConn)
	if !ok {
		return "", fmt.Errorf("original_socket_type_invalid")
	}
	raw, err := tcp.SyscallConn()
	if err != nil {
		return "", err
	}
	var address [28]byte
	length := uint32(len(address))
	var callError syscall.Errno
	level := syscall.SOL_IP
	if local, ok := tcp.LocalAddr().(*net.TCPAddr); ok && local.IP.To4() == nil {
		level = syscall.IPPROTO_IPV6
	}
	err = raw.Control(func(fd uintptr) {
		_, _, callError = syscall.Syscall6(syscall.SYS_GETSOCKOPT, fd, uintptr(level), 80, uintptr(unsafe.Pointer(&address[0])), uintptr(unsafe.Pointer(&length)), 0)
	})
	if err != nil {
		return "", err
	}
	if callError != 0 {
		return "", callError
	}
	family := binary.LittleEndian.Uint16(address[:2])
	if length < 16 || (family != syscall.AF_INET && family != syscall.AF_INET6) || (family == syscall.AF_INET6 && length < 28) {
		return "", fmt.Errorf("original_address_invalid")
	}
	ip := net.IP(address[4:8])
	if family == syscall.AF_INET6 {
		ip = net.IP(address[8:24])
	}
	port := binary.BigEndian.Uint16(address[2:4])
	if port == 0 || ip.IsUnspecified() {
		return "", fmt.Errorf("original_address_invalid")
	}
	return net.JoinHostPort(ip.String(), strconv.Itoa(int(port))), nil
}
