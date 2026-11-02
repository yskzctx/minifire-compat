package main

import (
	"crypto/sha1"
	"crypto/subtle"
	"encoding/binary"
	"encoding/hex"
	"errors"
	"regexp"
	"strings"
)

const maxBody = 2 * 1024 * 1024

var invalidWire = errors.New("invalid protobuf wire data")
var versionPattern = regexp.MustCompile(`^[0-9]+\.[0-9]+\.[0-9]+$`)

type field struct {
	num       uint64
	wire      uint64
	raw, data []byte
}

func parseFields(b []byte) ([]field, error) {
	if len(b) > maxBody {
		return nil, invalidWire
	}
	var result []field
	for at := 0; at < len(b); {
		start := at
		key, n := binary.Uvarint(b[at:])
		if n <= 0 || key>>3 == 0 || key>>3 > 0x1fffffff {
			return nil, invalidWire
		}
		at += n
		f := field{num: key >> 3, wire: key & 7}
		dataStart := at
		switch f.wire {
		case 0:
			_, n = binary.Uvarint(b[at:])
			if n <= 0 {
				return nil, invalidWire
			}
			at += n
		case 1:
			at += 8
		case 5:
			at += 4
		case 2:
			size, k := binary.Uvarint(b[at:])
			if k <= 0 {
				return nil, invalidWire
			}
			at += k
			if size > uint64(len(b)-at) {
				return nil, invalidWire
			}
			dataStart = at
			at += int(size)
		default:
			return nil, invalidWire
		}
		if at > len(b) {
			return nil, invalidWire
		}
		f.data = b[dataStart:at]
		f.raw = b[start:at]
		result = append(result, f)
	}
	return result, nil
}
func value(fields []field, num uint64) []byte {
	for _, f := range fields {
		if f.num == num {
			return f.data
		}
	}
	return nil
}
func count(fields []field, num uint64) int {
	n := 0
	for _, f := range fields {
		if f.num == num {
			n++
		}
	}
	return n
}
func number(fields []field, num uint64) uint64 {
	for _, f := range fields {
		if f.num == num && f.wire == 0 {
			v, _ := binary.Uvarint(f.data)
			return v
		}
	}
	return 0
}
func integer(v uint64) []byte { return binary.AppendUvarint(nil, v) }
func appendField(dst []byte, num, wire uint64, data []byte) []byte {
	dst = binary.AppendUvarint(dst, num<<3|wire)
	if wire == 2 {
		dst = binary.AppendUvarint(dst, uint64(len(data)))
	}
	return append(dst, data...)
}

type replacement struct {
	wire uint64
	data []byte
}

func replaceFields(fields []field, changes map[uint64]replacement) []byte {
	var result []byte
	seen := map[uint64]bool{}
	for _, f := range fields {
		if r, ok := changes[f.num]; ok {
			result = appendField(result, f.num, r.wire, r.data)
			seen[f.num] = true
		} else {
			result = append(result, f.raw...)
		}
	}
	// Stable order for newly inserted fields.
	for n := uint64(1); n <= 23; n++ {
		if r, ok := changes[n]; ok && !seen[n] {
			result = appendField(result, n, r.wire, r.data)
		}
	}
	return result
}
func knownVersion(b []byte) bool {
	s := string(b)
	return s == "1.0.77" || s == "1.0.78" || s == "1.0.79"
}
func rewriteTerminal(body []byte, target string) ([]byte, bool) {
	fields, err := parseFields(body)
	if err != nil || !versionPattern.MatchString(target) {
		return body, false
	}
	for _, n := range []uint64{5, 9, 10, 14} {
		if count(fields, n) != 1 {
			return body, false
		}
	}
	os, channel := number(fields, 9), number(fields, 5)
	if (os != 1 && os != 2) || (channel != 23 && channel != 888) || !knownVersion(value(fields, 10)) || !knownVersion(value(fields, 14)) {
		return body, false
	}
	if os == 2 && channel == 888 && string(value(fields, 10)) == target && string(value(fields, 14)) == target {
		return body, false
	}
	return replaceFields(fields, map[uint64]replacement{5: {0, integer(888)}, 9: {0, integer(2)}, 10: {2, []byte(target)}, 14: {2, []byte(target)}}), true
}
func verifiedSignature(body []byte, sign, unique string, material []byte) bool {
	if len(sign) != 40 || len(unique) > 256 || len(material) == 0 || len(material) > 256 || len(body) > maxBody {
		return false
	}
	expected, err := hex.DecodeString(sign)
	if err != nil {
		return false
	}
	digest := func(data []byte) []byte {
		h := sha1.New()
		h.Write(data)
		h.Write(material)
		h.Write([]byte(unique))
		return h.Sum(nil)
	}
	// Legacy game-protocol compatibility. Verify before rewriting anything.
	return subtle.ConstantTimeCompare(digest(body), expected) == 1
}

func signedTerminal(body []byte, sign, unique string, material []byte, target string) ([]byte, string, bool) {
	if !verifiedSignature(body, sign, unique, material) {
		return body, sign, false
	}
	digest := func(data []byte) []byte {
		h := sha1.New()
		h.Write(data)
		h.Write(material)
		h.Write([]byte(unique))
		return h.Sum(nil)
	}
	result, changed := rewriteTerminal(body, target)
	if !changed {
		return body, sign, false
	}
	updated := hex.EncodeToString(digest(result))
	if sign == strings.ToUpper(sign) {
		updated = strings.ToUpper(updated)
	}
	return result, updated, true
}

func rewriteLobby(packet []byte, target string) ([]byte, bool) {
	envelope, err := parseFields(packet)
	if err != nil || count(envelope, 1) != 1 || count(envelope, 2) != 1 || !versionPattern.MatchString(target) {
		return packet, false
	}
	head, err := parseFields(value(envelope, 1))
	if err != nil || count(head, 1) != 1 || number(head, 1) != 10000 {
		return packet, false
	}
	fields, err := parseFields(value(envelope, 2))
	if err != nil || count(fields, 9) != 1 || count(fields, 13) != 1 || count(fields, 4) > 1 {
		return packet, false
	}
	os, channel := number(fields, 9), number(fields, 4)
	if (os != 1 && os != 2) || (count(fields, 4) == 1 && channel != 23 && channel != 888) || !knownVersion(value(fields, 13)) {
		return packet, false
	}
	if os == 2 && channel == 888 && string(value(fields, 13)) == target {
		return packet, false
	}
	body := replaceFields(fields, map[uint64]replacement{9: {0, integer(2)}, 4: {0, integer(888)}, 13: {2, []byte(target)}})
	return replaceFields(envelope, map[uint64]replacement{2: {2, body}}), true
}

func lobbyEndpoint(response []byte) string {
	fields, err := parseFields(response)
	if err != nil || count(fields, 1) != 1 || number(fields, 1) != 200 || count(fields, 5) != 1 {
		return ""
	}
	data, err := parseFields(value(fields, 5))
	if err != nil || count(data, 3) != 1 {
		return ""
	}
	address := value(data, 3)
	if len(address) == 0 || len(address) > 256 {
		return ""
	}
	for _, c := range address {
		if c < 33 || c > 126 {
			return ""
		}
	}
	return string(address)
}
