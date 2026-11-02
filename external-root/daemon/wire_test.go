package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/hex"
	"testing"
)

func fixture() []byte {
	b := appendField(nil, 5, 0, []byte{23})
	b = appendField(b, 9, 0, []byte{1})
	b = appendField(b, 10, 2, []byte("1.0.77"))
	b = appendField(b, 14, 2, []byte("1.0.77"))
	return appendField(b, 4, 2, []byte("PRIVATE-FIXTURE"))
}

func TestTerminalPreservesOtherFieldsAndRequiresSignature(t *testing.T) {
	b := fixture()
	material := []byte("LOCAL")
	unique := "fixture"
	h := sha1.New()
	h.Write(b)
	h.Write(material)
	h.Write([]byte(unique))
	sign := hex.EncodeToString(h.Sum(nil))
	result, updated, ok := signedTerminal(b, sign, unique, material, "1.0.79")
	if !ok || bytes.Equal(result, b) || updated == sign {
		t.Fatal("expected signed rewrite")
	}
	fields, err := parseFields(result)
	if err != nil {
		t.Fatal(err)
	}
	if number(fields, 9) != 2 || number(fields, 5) != 888 || string(value(fields, 14)) != "1.0.79" || string(value(fields, 4)) != "PRIVATE-FIXTURE" {
		t.Fatal("incorrect rewrite")
	}
	unchanged, original, ok := signedTerminal(b, "bad", unique, material, "1.0.79")
	if ok || !bytes.Equal(unchanged, b) || original != "bad" {
		t.Fatal("must preserve unverified request")
	}
}

func TestInvalidAndDuplicateTargetFieldsAreRejected(t *testing.T) {
	b := appendField(fixture(), 9, 0, []byte{2})
	if _, ok := rewriteTerminal(b, "1.0.79"); ok {
		t.Fatal("duplicate platform field accepted")
	}
	for _, b := range [][]byte{{0xff}, {0x12, 0xff}, {0x0b}, {0}} {
		if _, err := parseFields(b); err == nil {
			t.Fatal("invalid wire accepted")
		}
	}
}

func TestLobbyLoginAndEndpointExtraction(t *testing.T) {
	login := appendField(nil, 9, 0, integer(1))
	login = appendField(login, 4, 0, integer(23))
	login = appendField(login, 13, 2, []byte("1.0.77"))
	login = appendField(login, 3, 2, []byte("PRIVATE-FIXTURE"))
	head := appendField(nil, 1, 0, integer(10000))
	packet := appendField(nil, 1, 2, head)
	packet = appendField(packet, 2, 2, login)
	result, changed := rewriteLobby(packet, "1.0.79")
	if !changed {
		t.Fatal("lobby not rewritten")
	}
	fields, _ := parseFields(result)
	body, _ := parseFields(value(fields, 2))
	if number(body, 9) != 2 || number(body, 4) != 888 || string(value(body, 3)) != "PRIVATE-FIXTURE" {
		t.Fatal("invalid lobby rewrite")
	}
	data := appendField(nil, 3, 2, []byte("203.0.113.10:12345"))
	response := appendField(nil, 1, 0, integer(200))
	response = appendField(response, 5, 2, data)
	if lobbyEndpoint(response) != "203.0.113.10:12345" {
		t.Fatal("endpoint not extracted")
	}
}
