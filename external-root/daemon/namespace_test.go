package main

import (
	"errors"
	"testing"
)

func TestPrivateNamespaceRequiresExpectedIsolatedNamespace(t *testing.T) {
	for _, test := range []struct {
		name, current, init, expected, controller string
		ok                                        bool
	}{
		{"isolated", "mnt:[300]", "mnt:[100]", "mnt:[300]", "mnt:[200]", true},
		{"init", "mnt:[100]", "mnt:[100]", "mnt:[100]", "mnt:[200]", false},
		{"controller", "mnt:[200]", "mnt:[100]", "mnt:[200]", "mnt:[200]", false},
		{"wrong target", "mnt:[301]", "mnt:[100]", "mnt:[300]", "mnt:[200]", false},
		{"invalid expected", "mnt:[300]", "mnt:[100]", "invalid", "mnt:[200]", false},
	} {
		t.Run(test.name, func(t *testing.T) {
			called := false
			link := func(path string) (string, error) {
				if path == "/proc/self/ns/mnt" {
					return test.current, nil
				}
				return test.init, nil
			}
			err := privatizeNamespace(test.expected, test.controller, link, func() error { called = true; return nil })
			if called != test.ok || (err == nil) != test.ok {
				t.Fatalf("namespace gate: called=%v err=%v", called, err)
			}
		})
	}
}
func TestPrivateNamespaceRetainsKernelErrorAndNeverUsesMountCommand(t *testing.T) {
	sentinel := errors.New("fixture kernel permission error")
	link := func(path string) (string, error) {
		if path == "/proc/self/ns/mnt" {
			return "mnt:[300]", nil
		}
		return "mnt:[100]", nil
	}
	err := privatizeNamespace("mnt:[300]", "mnt:[200]", link, func() error { return sentinel })
	if !errors.Is(err, sentinel) {
		t.Fatalf("lost kernel error: %v", err)
	}
}
func TestPrivateNamespaceRejectsUnreadableNamespace(t *testing.T) {
	called := false
	err := privatizeNamespace("mnt:[300]", "mnt:[200]", func(string) (string, error) { return "", errors.New("unreadable") }, func() error { called = true; return nil })
	if err == nil || called {
		t.Fatal("missing namespace accepted")
	}
}

func TestTrustBindRejectsForeignNamespaceSourceAndUnexpectedTarget(t *testing.T) {
	link := func(path string) (string, error) {
		if path == "/proc/self/ns/mnt" {
			return "mnt:[300]", nil
		}
		return "mnt:[100]", nil
	}
	for _, row := range []struct {
		source, target string
		ok             bool
	}{
		{"/data/local/tmp/minifire_compat_zygisk/trust", "/apex/com.android.conscrypt/cacerts", true},
		{"/data/local/tmp/minifire_compat_zygisk/trust", "/system/etc/security/cacerts", true},
		{"/proc/123/root/data/adb/modules/minifire_compat_zygisk/state/trust", "/apex/com.android.conscrypt/cacerts", false},
		{"/data/local/tmp/minifire_compat_zygisk/trust", "/system", false},
	} {
		called := false
		err := bindTrustMount("mnt:[300]", "mnt:[200]", row.source, row.target, link, func(source, target string) error { called = true; return nil })
		if called != row.ok || (err == nil) != row.ok {
			t.Fatalf("bind policy: %+v called=%v err=%v", row, called, err)
		}
	}
}

func TestTrustBindRequiresIsolatedNamespaceAndPreservesKernelError(t *testing.T) {
	called := false
	link := func(path string) (string, error) { return "mnt:[100]", nil }
	if err := bindTrustMount("mnt:[100]", "mnt:[200]", "/data/local/tmp/minifire_compat_zygisk/trust", "/system/etc/security/cacerts", link, func(string, string) error { called = true; return nil }); err == nil || called {
		t.Fatal("bind reached init namespace")
	}
	sentinel := errors.New("fixture EINVAL")
	link = func(path string) (string, error) {
		if path == "/proc/self/ns/mnt" {
			return "mnt:[300]", nil
		}
		return "mnt:[100]", nil
	}
	if err := bindTrustMount("mnt:[300]", "mnt:[200]", "/data/local/tmp/minifire_compat_zygisk/trust", "/system/etc/security/cacerts", link, func(string, string) error { return sentinel }); !errors.Is(err, sentinel) {
		t.Fatal(err)
	}
}
