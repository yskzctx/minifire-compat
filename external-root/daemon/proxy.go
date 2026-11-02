package main

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"sync"
	"sync/atomic"
	"time"
)

type eventLog struct {
	mu        sync.Mutex
	w         io.Writer
	path      string
	lastError error
}
type event struct {
	Time    string `json:"time"`
	Request string `json:"request_id"`
	Stage   string `json:"stage"`
	Status  int    `json:"status,omitempty"`
	Input   int    `json:"input_bytes,omitempty"`
	Output  int    `json:"output_bytes,omitempty"`
}

func (l *eventLog) emit(id, stage string, status, input, output int) {
	l.mu.Lock()
	defer l.mu.Unlock()
	defer func() {
		if l.lastError != nil {
			fmt.Fprintln(os.Stderr, "journal_write_failed")
		}
	}()
	entry := event{time.Now().UTC().Format(time.RFC3339Nano), id, stage, status, input, output}
	if l.w != nil {
		l.lastError = json.NewEncoder(l.w).Encode(entry)
		return
	}
	if info, err := os.Stat(l.path); err == nil && info.Size() > 1024*1024 {
		_ = os.Remove(l.path + ".1")
		if err = os.Rename(l.path, l.path+".1"); err != nil {
			l.lastError = err
			return
		}
	}
	file, err := os.OpenFile(l.path, os.O_WRONLY|os.O_CREATE|os.O_APPEND, 0600)
	if err != nil {
		l.lastError = err
		return
	}
	l.lastError = json.NewEncoder(file).Encode(entry)
	_ = file.Close()
}

type combinedBody struct {
	io.Reader
	io.Closer
}

func newProxy(target *url.URL, material []byte, version string, transport http.RoundTripper, journal *eventLog, onLobby ...func(string) error) (http.Handler, error) {
	if target == nil || target.Scheme != "https" || target.Hostname() == "" || target.User != nil || target.RawQuery != "" || target.Fragment != "" || (target.Path != "" && target.Path != "/") {
		return nil, errors.New("fixed HTTPS origin required")
	}
	if len(material) == 0 || len(material) > 256 || !versionPattern.MatchString(version) || journal == nil {
		return nil, errors.New("invalid configuration")
	}
	material = append([]byte(nil), material...)
	if transport == nil {
		t := http.DefaultTransport.(*http.Transport).Clone()
		t.Proxy = nil
		t.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}
		transport = t
	}
	if t, ok := transport.(*http.Transport); ok && t.TLSClientConfig != nil && t.TLSClientConfig.InsecureSkipVerify {
		return nil, errors.New("upstream certificate verification required")
	}
	var counter atomic.Uint64
	proxy := &httputil.ReverseProxy{Transport: transport}
	type key struct{}
	type rewriteKey struct{}
	type rewriteState struct{ applied bool }
	proxy.Rewrite = func(r *httputil.ProxyRequest) {
		id := r.In.Context().Value(key{}).(string)
		r.SetURL(target)
		r.Out.Host = target.Host
		r.Out.URL.RawQuery = r.In.URL.RawQuery
		if r.In.Method != "POST" || r.In.URL.Path != "/api/user/login" {
			journal.emit(id, "request_passthrough", 0, 0, 0)
			return
		}
		if len(onLobby) > 0 {
			if err := onLobby[0](""); err != nil {
				journal.emit(id, "lobby_route_reset_failed", 0, 0, 0)
				return
			}
		}
		if r.In.Header.Get("Content-Encoding") != "" {
			journal.emit(id, "login_request_encoding_unsupported", 0, 0, 0)
			return
		}
		if r.Out.Body == nil {
			journal.emit(id, "request_empty", 0, 0, 0)
			return
		}
		original := r.Out.Body
		body, err := io.ReadAll(io.LimitReader(original, maxBody+1))
		if err != nil || len(body) > maxBody {
			r.Out.Body = &combinedBody{io.MultiReader(bytes.NewReader(body), original), original}
			journal.emit(id, "request_body_unsupported", 0, len(body), 0)
			return
		}
		_ = original.Close()
		sign, unique := r.In.Header.Values("sign"), r.In.Header.Values("unique")
		rewritten := body
		if len(sign) == 1 && len(unique) == 1 {
			verified := verifiedSignature(body, sign[0], unique[0], material)
			if verified {
				journal.emit(id, "signature_verified", 0, len(body), 0)
			}
			var changed bool
			var updated string
			rewritten, updated, changed = signedTerminal(body, sign[0], unique[0], material, version)
			if changed {
				r.Out.Context().Value(rewriteKey{}).(*rewriteState).applied = true
				r.Out.Header.Set("sign", updated)
				journal.emit(id, "request_rewritten", 0, len(body), len(rewritten))
			} else {
				stage := "signature_unverified"
				if verified {
					stage = "login_profile_unchanged_or_unsupported"
				}
				journal.emit(id, stage, 0, len(body), 0)
			}
		} else {
			journal.emit(id, "signature_headers_unrecognized", 0, len(body), 0)
		}
		r.Out.Body = io.NopCloser(bytes.NewReader(rewritten))
		r.Out.ContentLength = int64(len(rewritten))
		r.Out.Header.Del("Content-Length")
	}
	proxy.ModifyResponse = func(r *http.Response) error {
		id := r.Request.Context().Value(key{}).(string)
		journal.emit(id, "upstream_response", r.StatusCode, 0, 0)
		if len(onLobby) > 0 && r.StatusCode == 200 && r.Request.URL.Path == "/api/user/login" && r.Request.Context().Value(rewriteKey{}).(*rewriteState).applied {
			original := r.Body
			body, err := io.ReadAll(io.LimitReader(original, maxBody+1))
			if err != nil {
				return errors.New("login_response_read_failed")
			}
			if len(body) > maxBody {
				r.Body = &combinedBody{io.MultiReader(bytes.NewReader(body), original), original}
				journal.emit(id, "login_response_oversize", 0, 0, 0)
				return nil
			}
			_ = original.Close()
			r.Body = io.NopCloser(bytes.NewReader(body))
			decoded := body
			if r.Header.Get("Content-Encoding") == "gzip" {
				stream, err := gzip.NewReader(bytes.NewReader(body))
				if err != nil {
					return errors.New("login_response_gzip_invalid")
				}
				decoded, err = io.ReadAll(io.LimitReader(stream, maxBody+1))
				_ = stream.Close()
				if err != nil || len(decoded) > maxBody {
					return errors.New("login_response_gzip_invalid")
				}
			} else if encoding := r.Header.Get("Content-Encoding"); encoding != "" && encoding != "identity" {
				journal.emit(id, "login_response_encoding_unsupported", 0, 0, 0)
				return nil
			}
			address := lobbyEndpoint(decoded)
			if fields, err := parseFields(decoded); err == nil && count(fields, 1) == 1 {
				journal.emit(id, "terminal_business_response", int(int32(number(fields, 1))), 0, 0)
			} else {
				journal.emit(id, "terminal_response_unrecognized", 0, 0, 0)
			}
			if address != "" {
				if err := onLobby[0](address); err != nil {
					journal.emit(id, "lobby_route_failed", 0, 0, 0)
					return errors.New("lobby_route_failed")
				}
				journal.emit(id, "lobby_endpoint_ready", 0, 0, 0)
			} else {
				journal.emit(id, "lobby_endpoint_not_found", 0, 0, 0)
			}
		}
		return nil
	}
	proxy.ErrorHandler = func(w http.ResponseWriter, r *http.Request, err error) {
		id := r.Context().Value(key{}).(string)
		stage := "upstream_failed_connection"
		var certificate *tls.CertificateVerificationError
		var network net.Error
		if errors.As(err, &certificate) {
			stage = "upstream_failed_certificate"
		} else if errors.As(err, &network) && network.Timeout() {
			stage = "upstream_failed_timeout"
		}
		journal.emit(id, stage, 502, 0, 0)
		http.Error(w, "upstream connection failed", http.StatusBadGateway)
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := fmt.Sprintf("%x-%x", time.Now().UnixNano(), counter.Add(1))
		journal.emit(id, "request_received", 0, 0, 0)
		ctx := context.WithValue(r.Context(), key{}, id)
		ctx = context.WithValue(ctx, rewriteKey{}, &rewriteState{})
		proxy.ServeHTTP(w, r.WithContext(ctx))
	}), nil
}
