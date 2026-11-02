package main

import (
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net/http"
	"os"
	"path/filepath"
)

// Read original Android system anchors in the daemon's namespace. Android's
// Conscrypt store may live exclusively in APEX while the legacy directory is
// empty. Do not disable verification or use the game's added compatibility CA.
func upstreamTransport(directories []string) (*http.Transport, error) {
	roots := x509.NewCertPool()
	loaded := false
	for _, directory := range directories {
		entries, err := os.ReadDir(directory)
		if err != nil {
			continue
		}
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			path := filepath.Join(directory, entry.Name())
			info, err := os.Stat(path)
			if err != nil || !info.Mode().IsRegular() || info.Size() > 1024*1024 {
				continue
			}
			data, err := os.ReadFile(path)
			if err == nil && roots.AppendCertsFromPEM(data) {
				loaded = true
			}
		}
	}
	if !loaded {
		return nil, errors.New("upstream_system_roots_unavailable")
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12, RootCAs: roots}
	return transport, nil
}
