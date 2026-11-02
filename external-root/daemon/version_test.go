package main

import (
	"bytes"
	"compress/gzip"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestStartupAndroidVersionAndResourcesArePreservedBothDirections(t *testing.T) {
	requestBody := appendField(nil, 1, 0, integer(1))
	requestBody = appendField(requestBody, 2, 2, []byte("1.0.77"))
	requestBody = appendField(requestBody, 3, 0, integer(23))
	requestBody = appendField(requestBody, 4, 2, []byte("90"))
	requestBody = appendField(requestBody, 5, 2, []byte("fixture-resource-signature"))
	resource := appendField(nil, 1, 0, integer(90))
	resource = appendField(resource, 2, 2, []byte("https://cdn.example/android/1.0.77/data.ab"))
	resource = appendField(resource, 11, 2, []byte("1.0.77"))
	resource = appendField(resource, 12, 0, integer(23))
	data := appendField(nil, 1, 2, []byte("1.0.77"))
	data = appendField(data, 5, 2, resource)
	reply := appendField(nil, 1, 0, integer(200))
	reply = appendField(reply, 5, 2, data)
	for _, compressed := range []bool{false, true} {
		t.Run(map[bool]string{false: "plain", true: "gzip"}[compressed], func(t *testing.T) {
			wire := reply
			if compressed {
				var encoded bytes.Buffer
				z := gzip.NewWriter(&encoded)
				z.Write(reply)
				z.Close()
				wire = encoded.Bytes()
			}
			upstream := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				body, _ := io.ReadAll(r.Body)
				if !bytes.Equal(body, requestBody) || r.Header.Get("sign") != "original-sign" || r.Header.Get("unique") != "original-time" {
					t.Error("Android startup request changed")
				}
				if r.URL.RawQuery != "platform=android&version=1.0.77" {
					t.Error("startup query changed")
				}
				if compressed {
					w.Header().Set("Content-Encoding", "gzip")
				}
				w.Header().Set("ETag", "resource-manifest-fixture")
				w.Write(wire)
			}))
			defer upstream.Close()
			target, _ := url.Parse(upstream.URL)
			var logs bytes.Buffer
			handler, err := newProxy(target, []byte("fixture"), "1.0.79", upstream.Client().Transport, &eventLog{w: &logs}, func(string) error { t.Error("startup version request must not change lobby routing"); return nil })
			if err != nil {
				t.Fatal(err)
			}
			request := httptest.NewRequest("POST", "https://login.minifire.cn/api/comm/version/new?platform=android&version=1.0.77", bytes.NewReader(requestBody))
			request.Header.Set("sign", "original-sign")
			request.Header.Set("unique", "original-time")
			request.Header.Set("Accept-Encoding", "gzip")
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if response.Code != 200 || !bytes.Equal(response.Body.Bytes(), wire) || response.Header().Get("ETag") != "resource-manifest-fixture" {
				t.Fatal("Android version/resource response changed")
			}
			if strings.Contains(logs.String(), "request_rewritten") {
				t.Fatal("startup was treated as login")
			}
			if !strings.Contains(logs.String(), "android_version_request_passthrough") || !strings.Contains(logs.String(), "version_response_passthrough") {
				t.Fatal("version flow lacks distinguishable diagnostics")
			}
		})
	}
}
