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
	if err := requireIsolatedNamespace(expected, controller, readlink); err != nil {
		return err
	}
	if err := mountPrivate(); err != nil {
		return fmt.Errorf("mount_private_syscall_failed: %w", err)
	}
	return nil
}

func requireIsolatedNamespace(expected, controller string, readlink func(string) (string, error)) error {
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
	return nil
}

func bindTrustMount(expected, controller, source, target string, readlink func(string) (string, error), bind func(string, string) error) error {
	if source != "/data/local/tmp/minifire_compat_zygisk/trust" {
		return errors.New("certificate_source_path_rejected")
	}
	if target != "/apex/com.android.conscrypt/cacerts" && target != "/system/etc/security/cacerts" {
		return errors.New("certificate_target_path_rejected")
	}
	if err := requireIsolatedNamespace(expected, controller, readlink); err != nil {
		return err
	}
	if err := bind(source, target); err != nil {
		return fmt.Errorf("certificate_bind_syscall_failed: %w", err)
	}
	return nil
}
