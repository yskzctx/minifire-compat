//go:build !linux

package main

import (
	"errors"
	"net"
)

func originalDestination(net.Conn) (string, error) {
	return "", errors.New("original_destination_requires_linux")
}
