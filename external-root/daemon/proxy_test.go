package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestHTTPSForwardRewritesAndReturnsResponse(t *testing.T) {
	material := []byte("LOCAL-FIXTURE")
	body := fixture()
	unique := "fixture-time"
	h := sha1.New()
	h.Write(body)
	h.Write(material)
	h.Write([]byte(unique))
	sign := hex.EncodeToString(h.Sum(nil))
	received := make(chan []byte, 1)
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		b, _ := io.ReadAll(r.Body)
		received <- b
		h := sha1.New()
		h.Write(b)
		h.Write(material)
		h.Write([]byte(r.Header.Get("unique")))
		if r.Header.Get("sign") != hex.EncodeToString(h.Sum(nil)) {
			t.Error("invalid forwarded signature")
		}
		w.Write([]byte("accepted"))
	}))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	var logs bytes.Buffer
	handler, err := newProxy(target, material, "1.0.79", upstream.Client().Transport, &eventLog{w: &logs})
	if err != nil {
		t.Fatal(err)
	}
	proxy := httptest.NewTLSServer(handler)
	defer proxy.Close()
	request, _ := http.NewRequest("POST", proxy.URL+"/api/user/login", bytes.NewReader(body))
	request.Header.Set("sign", sign)
	request.Header.Set("unique", unique)
	response, err := proxy.Client().Do(request)
	if err != nil {
		t.Fatal(err)
	}
	defer response.Body.Close()
	reply, _ := io.ReadAll(response.Body)
	if response.StatusCode != 200 || string(reply) != "accepted" {
		t.Fatal("response failed")
	}
	fields, err := parseFields(<-received)
	if err != nil || number(fields, 9) != 2 || number(fields, 5) != 888 {
		t.Fatal("body not rewritten")
	}
	if !strings.Contains(logs.String(), "request_rewritten") || strings.Contains(logs.String(), "PRIVATE-FIXTURE") || strings.Contains(logs.String(), sign) {
		t.Fatal("invalid diagnostic output")
	}
}

func TestUnknownUpstreamCertificateIsRejected(t *testing.T) {
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write([]byte("must not reach")) }))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	var logs bytes.Buffer
	handler, err := newProxy(target, []byte("fixture"), "1.0.79", nil, &eventLog{w: &logs})
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest("GET", "https://localhost/fixture", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != 502 || !strings.Contains(logs.String(), "upstream_failed") {
		t.Fatal("untrusted upstream was not rejected")
	}
}

func TestLobbyRouteIsPreparedBeforeLoginResponseReturns(t *testing.T) {
	data := appendField(nil, 3, 2, []byte("203.0.113.10:12345"))
	body := appendField(nil, 1, 0, integer(200))
	body = appendField(body, 5, 2, data)
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(body) }))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	ready := false
	handler, err := newProxy(target, []byte("fixture"), "1.0.79", upstream.Client().Transport, &eventLog{w: io.Discard}, func(address string) error {
		if address == "" {
			return nil
		}
		if address != "203.0.113.10:12345" {
			t.Error("wrong endpoint")
		}
		ready = true
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	requestBody := fixture()
	h := sha1.New()
	h.Write(requestBody)
	h.Write([]byte("fixture"))
	h.Write([]byte("time"))
	request := httptest.NewRequest("POST", "https://localhost/api/user/login", bytes.NewReader(requestBody))
	request.Header.Set("sign", hex.EncodeToString(h.Sum(nil)))
	request.Header.Set("unique", "time")
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if !ready || response.Code != 200 || !bytes.Equal(response.Body.Bytes(), body) {
		t.Fatal("route preparation or response forwarding failed")
	}
}

func TestUnverifiedNewLoginClearsOldLobbyRouteWithoutInstallingNewOne(t *testing.T) {
	data := appendField(nil, 3, 2, []byte("203.0.113.10:12345"))
	body := appendField(nil, 1, 0, integer(200))
	body = appendField(body, 5, 2, data)
	upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(body) }))
	defer upstream.Close()
	target, _ := url.Parse(upstream.URL)
	var addresses []string
	handler, err := newProxy(target, []byte("fixture"), "1.0.79", upstream.Client().Transport, &eventLog{w: io.Discard}, func(address string) error { addresses = append(addresses, address); return nil })
	if err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest("POST", "https://localhost/api/user/login", bytes.NewReader(fixture()))
	request.Header.Set("sign", strings.Repeat("0", 40))
	request.Header.Set("unique", "time")
	handler.ServeHTTP(httptest.NewRecorder(), request)
	if len(addresses) != 1 || addresses[0] != "" {
		t.Fatal("old route not cleared or unverified route installed")
	}
}
