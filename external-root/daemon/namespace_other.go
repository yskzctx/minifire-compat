//go:build !linux

package main

import "errors"

func mountNamespacePrivate() error { return errors.New("private_mount_requires_linux") }
