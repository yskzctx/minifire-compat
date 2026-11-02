//go:build linux

package main

import (
	"fmt"
	"os"
	"syscall"
)

func mountNamespacePrivate() error {
	return syscall.Mount("", "/", "", syscall.MS_REC|syscall.MS_PRIVATE, "")
}

func mountTrustDirectory(source, target string) error {
	for _, path := range []string{source, target} {
		info, err := os.Stat(path)
		if err != nil {
			return fmt.Errorf("certificate_directory_unavailable: %w", err)
		}
		if !info.IsDir() {
			return fmt.Errorf("certificate_path_not_directory")
		}
	}
	return syscall.Mount(source, target, "", syscall.MS_BIND|syscall.MS_REC, "")
}
