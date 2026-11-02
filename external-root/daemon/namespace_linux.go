//go:build linux

package main

import "syscall"

func mountNamespacePrivate() error {
	return syscall.Mount("", "/", "", syscall.MS_REC|syscall.MS_PRIVATE, "")
}
