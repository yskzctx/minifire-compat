package main

import (
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/pem"
	"os"
	"path/filepath"
	"testing"
)

func TestKnownClientMaterialExtractionDoesNotRequireProcessAccess(t *testing.T) {
	root := filepath.Join("..", "..", "..", "work", "apk-files")
	b, err := os.ReadFile(filepath.Join(root, "lib", "arm64-v8a", "libil2cpp.so"))
	if err != nil {
		t.Skip("local client fixture absent")
	}
	m, err := os.ReadFile(filepath.Join(root, "assets", "bin", "Data", "Managed", "Metadata", "global-metadata.dat"))
	if err != nil {
		t.Fatal(err)
	}
	material, err := clientMaterial(b, m)
	if err != nil {
		t.Fatal(err)
	}
	digest := sha256.Sum256(material)
	if hex.EncodeToString(digest[:]) != "7ae28f2f44dcfe16e83b9de24e02593199710fb309dffe0136902aa431949b24" {
		t.Fatal("material fingerprint mismatch")
	}
	b[0] ^= 1
	if _, err = clientMaterial(b, m); err == nil {
		t.Fatal("unknown binary accepted")
	}
}

func TestGeneratedTLSIdentityVerifiesAndSurvivesRepeatedPrepare(t *testing.T) {
	dir := t.TempDir()
	if err := prepareIdentity(dir); err != nil {
		t.Fatal(err)
	}
	ca, err := os.ReadFile(filepath.Join(dir, "ca.pem"))
	if err != nil {
		t.Fatal(err)
	}
	pair, err := tls.LoadX509KeyPair(filepath.Join(dir, "server.pem"), filepath.Join(dir, "server.key"))
	if err != nil {
		t.Fatal(err)
	}
	cert, err := x509.ParseCertificate(pair.Certificate[0])
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AppendCertsFromPEM(ca)
	if _, err = cert.Verify(x509.VerifyOptions{Roots: roots, DNSName: "login.minifire.cn"}); err != nil {
		t.Fatal(err)
	}
	if err = prepareIdentity(dir); err != nil {
		t.Fatal(err)
	}
	again, _ := os.ReadFile(filepath.Join(dir, "ca.pem"))
	if string(again) != string(ca) {
		t.Fatal("CA unexpectedly changed")
	}
	block, _ := pem.Decode(ca)
	if block == nil {
		t.Fatal("CA missing")
	}
}
