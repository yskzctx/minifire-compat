//go:build !linux

package main

import "errors"

func mountNamespacePrivate() error             { return errors.New("private_mount_requires_linux") }
func mountTrustDirectory(string, string) error { return errors.New("certificate_bind_requires_linux") }
