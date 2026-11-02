package main

import (
	"crypto/tls"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"
)

func TestUpstreamUsesAPEXRootsWhenLegacyStoreIsEmpty(t *testing.T) {
	dir := t.TempDir()
	apex := filepath.Join(dir, "apex")
	legacy := filepath.Join(dir, "legacy")
	if err := prepareIdentity(apex); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(legacy, 0700); err != nil {
		t.Fatal(err)
	}
	upstream := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("android configuration")) }))
	pair, err := tls.LoadX509KeyPair(filepath.Join(apex, "server.pem"), filepath.Join(apex, "server.key"))
	if err != nil {
		t.Fatal(err)
	}
	upstream.TLS = &tls.Config{Certificates: []tls.Certificate{pair}}
	upstream.StartTLS()
	defer upstream.Close()
	transport, err := upstreamTransport([]string{apex, legacy})
	if err != nil {
		t.Fatal(err)
	}
	defer transport.CloseIdleConnections()
	transport.TLSClientConfig.ServerName = "login.minifire.cn"
	target, _ := url.Parse(upstream.URL)
	handler, err := newProxy(target, []byte("fixture"), "1.0.79", transport, &eventLog{w: io.Discard})
	if err != nil {
		t.Fatal(err)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest("GET", "https://login.minifire.cn/api/comm/version/new", nil))
	if response.Code != 200 || response.Body.String() != "android configuration" {
		t.Fatalf("APEX roots not used: HTTP %d", response.Code)
	}
	if transport.Proxy != nil || transport.TLSClientConfig.InsecureSkipVerify {
		t.Fatal("upstream verification weakened")
	}
}

func TestUpstreamRejectsMissingOrInvalidRootStores(t *testing.T) {
	dir := t.TempDir()
	if _, err := upstreamTransport([]string{dir}); err == nil {
		t.Fatal("empty roots accepted")
	}
	if err := os.WriteFile(filepath.Join(dir, "invalid.0"), []byte("not a certificate"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := upstreamTransport([]string{dir}); err == nil {
		t.Fatal("invalid roots accepted")
	}
}
