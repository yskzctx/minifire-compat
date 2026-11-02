package main

import (
	"errors"
	"fmt"
	"regexp"
)

var namespacePattern = regexp.MustCompile(`^mnt:\[[0-9]+\]$`)

// This helper is exec'd after nsenter. No setns call is made from a Go thread,
// and the kernel operation is allowed only in the expected isolated namespace.
func privatizeNamespace(expected, controller string, readlink func(string) (string, error), mountPrivate func() error) error {
	if !namespacePattern.MatchString(expected) || !namespacePattern.MatchString(controller) {
		return errors.New("namespace_identity_invalid")
	}
	current, err := readlink("/proc/self/ns/mnt")
	if err != nil {
		return errors.New("current_namespace_unreadable")
	}
	initial, err := readlink("/proc/1/ns/mnt")
	if err != nil {
		return errors.New("init_namespace_unreadable")
	}
	if current != expected || current == controller || current == initial {
		return errors.New("namespace_not_isolated")
	}
	if err := mountPrivate(); err != nil {
		return fmt.Errorf("mount_private_syscall_failed: %w", err)
	}
	return nil
}
