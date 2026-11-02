package main

import (
	"archive/zip"
	"bytes"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/md5" // Android's legacy certificate filename index only; not authentication.
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"debug/elf"
	"encoding/binary"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"time"
)

func clientMaterial(binaryData, metadata []byte) ([]byte, error) {
	digest := sha256.Sum256(binaryData)
	if hex.EncodeToString(digest[:]) != "6d86ac671d3136a79a6e486c3e547660d0dfbd13160169f35d86c5bfdc479e5d" {
		return nil, errors.New("client_binary_unrecognized")
	}
	image, err := elf.NewFile(bytes.NewReader(binaryData))
	if err != nil {
		return nil, errors.New("client_elf_invalid")
	}
	read64 := func(address uint64) (uint64, error) {
		for _, p := range image.Progs {
			if p.Type == elf.PT_LOAD && address >= p.Vaddr && address-p.Vaddr <= p.Filesz && p.Filesz-(address-p.Vaddr) >= 8 {
				offset := p.Off + address - p.Vaddr
				if offset > uint64(len(binaryData)) || uint64(len(binaryData))-offset < 8 {
					break
				}
				return binary.LittleEndian.Uint64(binaryData[offset : offset+8]), nil
			}
		}
		return 0, errors.New("client_reference_unmapped")
	}
	pointer, err := read64(0x820d130)
	if err != nil {
		return nil, err
	}
	usage, err := read64(pointer)
	if err != nil {
		return nil, err
	}
	if usage>>29 != 5 || usage&1 != 1 || len(metadata) < 24 {
		return nil, errors.New("metadata_usage_invalid")
	}
	index := (usage & 0x1fffffff) >> 1
	table := uint64(binary.LittleEndian.Uint32(metadata[8:12]) ^ 0x66666666)
	size := uint64(binary.LittleEndian.Uint32(metadata[12:16]) ^ 0x66666666)
	data := uint64(binary.LittleEndian.Uint32(metadata[16:20]) ^ 0x66666666)
	dataSize := uint64(binary.LittleEndian.Uint32(metadata[20:24]) ^ 0x66666666)
	if index >= size/8 || table+index*8+8 > uint64(len(metadata)) {
		return nil, errors.New("metadata_literal_invalid")
	}
	at := table + index*8
	length := uint64(binary.LittleEndian.Uint32(metadata[at : at+4]))
	offset := uint64(binary.LittleEndian.Uint32(metadata[at+4 : at+8]))
	if length != 16 || offset+length > dataSize || data+offset+length > uint64(len(metadata)) {
		return nil, errors.New("metadata_literal_invalid")
	}
	material := append([]byte(nil), metadata[data+offset:data+offset+length]...)
	fingerprint := sha256.Sum256(material)
	if hex.EncodeToString(fingerprint[:]) != "7ae28f2f44dcfe16e83b9de24e02593199710fb309dffe0136902aa431949b24" {
		return nil, errors.New("material_fingerprint_mismatch")
	}
	return material, nil
}

func materialFromAPK(path string, progress ...func(string) error) ([]byte, error) {
	report := func(stage string) error {
		if len(progress) > 0 {
			return progress[0](stage)
		}
		return nil
	}
	archive, err := zip.OpenReader(path)
	if err != nil {
		return nil, errors.New("apk_open_failed")
	}
	defer archive.Close()
	read := func(name string, limit uint64) ([]byte, error) {
		for _, f := range archive.File {
			if f.Name == name {
				if f.UncompressedSize64 > limit {
					return nil, errors.New("apk_entry_oversize")
				}
				stream, err := f.Open()
				if err != nil {
					return nil, err
				}
				defer stream.Close()
				return io.ReadAll(io.LimitReader(stream, int64(limit)+1))
			}
		}
		return nil, errors.New("apk_entry_missing")
	}
	if err = report("reading_apk_binary"); err != nil {
		return nil, err
	}
	b, err := read("lib/arm64-v8a/libil2cpp.so", 180*1024*1024)
	if err != nil {
		return nil, err
	}
	if err = report("reading_apk_metadata"); err != nil {
		return nil, err
	}
	m, err := read("assets/bin/Data/Managed/Metadata/global-metadata.dat", 32*1024*1024)
	if err != nil {
		return nil, err
	}
	if err = report("verifying_client_binary"); err != nil {
		return nil, err
	}
	return clientMaterial(b, m)
}

func writePrivate(dir, name string, data []byte) error {
	path := filepath.Join(dir, name)
	temp := path + ".tmp"
	file, err := os.OpenFile(temp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	_, err = file.Write(data)
	closeErr := file.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	if err = os.Chmod(temp, 0600); err != nil {
		return err
	}
	return os.Rename(temp, path)
}
func serial() (*big.Int, error) { return rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128)) }
func keyPEM(key *ecdsa.PrivateKey) ([]byte, error) {
	der, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, err
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), nil
}

func prepareIdentity(dir string) error {
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	if err := os.Chmod(dir, 0700); err != nil {
		return err
	}
	var ca *x509.Certificate
	var key *ecdsa.PrivateKey
	certData, certErr := os.ReadFile(filepath.Join(dir, "ca.pem"))
	keyData, keyErr := os.ReadFile(filepath.Join(dir, "ca.key"))
	now := time.Now()
	if certErr == nil && keyErr == nil {
		block, _ := pem.Decode(certData)
		if block == nil {
			return errors.New("ca_invalid")
		}
		var err error
		ca, err = x509.ParseCertificate(block.Bytes)
		if err != nil || !ca.IsCA {
			return errors.New("ca_invalid")
		}
		if err = ca.CheckSignatureFrom(ca); err != nil || now.Before(ca.NotBefore) || !now.Add(7*24*time.Hour).Before(ca.NotAfter) {
			return errors.New("ca_validity_failed")
		}
		block, _ = pem.Decode(keyData)
		if block == nil {
			return errors.New("ca_key_invalid")
		}
		parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
		if err != nil {
			return errors.New("ca_key_invalid")
		}
		var ok bool
		key, ok = parsed.(*ecdsa.PrivateKey)
		if !ok || !key.PublicKey.Equal(ca.PublicKey) {
			return errors.New("ca_key_mismatch")
		}
	} else if (certErr == nil || errors.Is(certErr, os.ErrNotExist)) &&
		(keyErr == nil || errors.Is(keyErr, os.ErrNotExist)) {
		// A cancelled initial prepare can leave only one half of an unused
		// identity. Rebuild that incomplete pair; preserve complete valid pairs.
		var err error
		key, err = ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			return err
		}
		id, err := serial()
		if err != nil {
			return err
		}
		template := &x509.Certificate{SerialNumber: id, Subject: pkix.Name{CommonName: "Minifire Local Compatibility CA"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(365 * 24 * time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign | x509.KeyUsageCRLSign}
		der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
		if err != nil {
			return err
		}
		ca, err = x509.ParseCertificate(der)
		if err != nil {
			return err
		}
		certData = pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
		keyData, err = keyPEM(key)
		if err != nil {
			return err
		}
		if err = writePrivate(dir, "ca.key", keyData); err != nil {
			return err
		}
		if err = writePrivate(dir, "ca.pem", certData); err != nil {
			return err
		}
	} else {
		return errors.New("ca_files_incomplete")
	}
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	id, err := serial()
	if err != nil {
		return err
	}
	leaf := &x509.Certificate{SerialNumber: id, Subject: pkix.Name{CommonName: "login.minifire.cn"}, DNSNames: []string{"login.minifire.cn"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(90 * 24 * time.Hour), BasicConstraintsValid: true, KeyUsage: x509.KeyUsageDigitalSignature, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}
	if leaf.NotAfter.After(ca.NotAfter) {
		leaf.NotAfter = ca.NotAfter
	}
	der, err := x509.CreateCertificate(rand.Reader, leaf, ca, &leafKey.PublicKey, key)
	if err != nil {
		return err
	}
	leafPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	leafPEM = append(leafPEM, certData...)
	leafKeyPEM, err := keyPEM(leafKey)
	if err != nil {
		return err
	}
	if err = writePrivate(dir, "server.pem", leafPEM); err != nil {
		return err
	}
	if err = writePrivate(dir, "server.key", leafKeyPEM); err != nil {
		return err
	}
	// Android uses this MD5-derived subject index to locate trust anchors.
	index := md5.Sum(ca.RawSubject)
	filename := fmt.Sprintf("%08x.0", binary.LittleEndian.Uint32(index[:4]))
	return writePrivate(dir, "ca-filename", []byte(filename+"\n"))
}
