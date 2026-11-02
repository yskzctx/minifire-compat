package main

import (
	"os"
	"path/filepath"
	"testing"
)

func locateFixture(t *testing.T) (string, string) {
	t.Helper()
	root := t.TempDir()
	list := filepath.Join(root, "packages.list")
	apps := filepath.Join(root, "app")
	if err := os.WriteFile(list, []byte("other.app 12345 0 /data/user/0/other.app\ncom.miniworldroyale.sparkgame 10240 0 /data/user/0/com.miniworldroyale.sparkgame\n"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(apps, 0700); err != nil {
		t.Fatal(err)
	}
	return list, apps
}
func makeLocatedAPK(t *testing.T, root, parent string) string {
	t.Helper()
	path := filepath.Join(root, parent, "com.miniworldroyale.sparkgame-fixture", "base.apk")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("fixture, validated separately by prepare"), 0600); err != nil {
		t.Fatal(err)
	}
	return path
}
func TestLocateGameWithoutPackageService(t *testing.T) {
	for _, parent := range []string{"", "~~random"} {
		t.Run(parent, func(t *testing.T) {
			list, apps := locateFixture(t)
			want := makeLocatedAPK(t, apps, parent)
			got, err := locateInstalledGame(list, []string{apps})
			if err != nil {
				t.Fatal(err)
			}
			if got.APK != want || got.UID != 10240 {
				t.Fatalf("wrong installed game: %+v", got)
			}
		})
	}
}
func TestLocateRejectsAmbiguousInstalledAPKs(t *testing.T) {
	list, apps := locateFixture(t)
	makeLocatedAPK(t, apps, "~~one")
	makeLocatedAPK(t, apps, "~~two")
	if _, err := locateInstalledGame(list, []string{apps}); err == nil || err.Error() != "installed_apk_ambiguous" {
		t.Fatalf("ambiguous result: %v", err)
	}
}
func TestLocateRequiresExactPackageAndApplicationUID(t *testing.T) {
	list, apps := locateFixture(t)
	makeLocatedAPK(t, apps, "~~one")
	for _, line := range []string{"com.miniworldroyale.sparkgame.evil 10240 0 ignored\n", "com.miniworldroyale.sparkgame 1000 0 ignored\n", "com.miniworldroyale.sparkgame not-a-uid 0 ignored\n"} {
		if err := os.WriteFile(list, []byte(line), 0600); err != nil {
			t.Fatal(err)
		}
		if _, err := locateInstalledGame(list, []string{apps}); err == nil {
			t.Fatal("invalid package metadata accepted")
		}
	}
}
func TestLocateDoesNotUseLookalikeOrMissingAPKs(t *testing.T) {
	list, apps := locateFixture(t)
	path := filepath.Join(apps, "~~random", "com.miniworldroyale.sparkgame.evil-hash", "base.apk")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("wrong package"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := locateInstalledGame(list, []string{apps}); err == nil {
		t.Fatal("lookalike installed path accepted")
	}
}

func TestSelectedChannelPackageHasItsOwnUIDAndAPK(t *testing.T) {
	list, apps := locateFixture(t)
	name := "com.example.minifire.channel"
	if err := os.WriteFile(list, []byte(name+" 10456 0 ignored\n"), 0600); err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(apps, "~~random", name+"-hash", "base.apk")
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte("fixture"), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := locateInstalledGame(list, []string{apps}, name)
	if err != nil || got.UID != 10456 || got.APK != path {
		t.Fatalf("selected lookup: %+v %v", got, err)
	}
	for _, bad := range []string{"com.app;id", "../com.app", "com..app", "com.app\nother"} {
		if _, err := locateInstalledGame(list, []string{apps}, bad); err == nil {
			t.Fatal("unsafe package accepted")
		}
	}
}

func TestInstalledAppListIsBoundedAndContainsNoOtherMetadata(t *testing.T) {
	list, _ := locateFixture(t)
	apps, err := readInstalledApps(list)
	if err != nil {
		t.Fatal(err)
	}
	if len(apps) != 2 || apps[0].Package != gamePackage {
		t.Fatal(apps)
	}
}
