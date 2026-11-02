package main

import (
	"bufio"
	"errors"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

const gamePackage = "com.miniworldroyale.sparkgame"

var packagePattern = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$`)

func validPackage(name string) bool { return len(name) <= 255 && packagePattern.MatchString(name) }

type installedApp struct {
	Package string `json:"package"`
	UID     int    `json:"uid"`
}

func readInstalledApps(path string) ([]installedApp, error) {
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("packages_list_unreadable")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.Size() > 16*1024*1024 {
		return nil, errors.New("packages_list_unsupported")
	}
	result := []installedApp{}
	seen := map[string]bool{}
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		fields := strings.Fields(scanner.Text())
		if len(fields) < 2 || !validPackage(fields[0]) {
			continue
		}
		uid, err := strconv.ParseInt(fields[1], 10, 32)
		if err != nil || uid < 10000 {
			continue
		}
		if seen[fields[0]] {
			return nil, errors.New("package_registry_duplicate")
		}
		seen[fields[0]] = true
		result = append(result, installedApp{fields[0], int(uid)})
	}
	if scanner.Err() != nil {
		return nil, errors.New("packages_list_read_failed")
	}
	sort.Slice(result, func(i, j int) bool { return result[i].Package < result[j].Package })
	return result, nil
}

type installedGame struct {
	APK string
	UID int
}

// Root can read the package registry and installed APK directories without
// invoking PackageManager over Binder. Never select an APK by modification time:
// installation leftovers must produce an ambiguity error, not a guessed path.
func locateInstalledGame(listPath string, appRoots []string, selected ...string) (installedGame, error) {
	result := installedGame{}
	name := gamePackage
	if len(selected) > 0 {
		name = selected[0]
	}
	if !validPackage(name) {
		return result, errors.New("target_package_invalid")
	}
	file, err := os.Open(listPath)
	if err != nil {
		return result, errors.New("packages_list_unreadable")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || info.Size() > 16*1024*1024 {
		return result, errors.New("packages_list_unsupported")
	}
	scanner := bufio.NewScanner(file)
	matches := 0
	for scanner.Scan() {
		columns := strings.Fields(scanner.Text())
		if len(columns) < 2 || columns[0] != name {
			continue
		}
		matches++
		uid, err := strconv.ParseInt(columns[1], 10, 32)
		if err != nil || uid < 10000 {
			return result, errors.New("package_uid_invalid")
		}
		result.UID = int(uid)
	}
	if err := scanner.Err(); err != nil {
		return result, errors.New("packages_list_read_failed")
	}
	if matches != 1 {
		return result, errors.New("package_uid_missing_or_ambiguous")
	}
	candidates := map[string]bool{}
	for _, root := range appRoots {
		if !filepath.IsAbs(root) || strings.ContainsAny(root, "\r\n\x00") {
			return result, errors.New("apk_root_invalid")
		}
		for _, pattern := range []string{filepath.Join(root, name+"-*", "base.apk"), filepath.Join(root, "*", name+"-*", "base.apk")} {
			paths, err := filepath.Glob(pattern)
			if err != nil {
				return result, errors.New("apk_root_invalid")
			}
			for _, path := range paths {
				if strings.ContainsAny(path, "\r\n\x00") {
					continue
				}
				stat, err := os.Stat(path)
				if err != nil || !stat.Mode().IsRegular() {
					continue
				}
				probe, err := os.Open(path)
				if err != nil {
					continue
				}
				probe.Close()
				real, err := filepath.EvalSymlinks(path)
				if err != nil {
					continue
				}
				candidates[real] = true
			}
		}
	}
	if len(candidates) == 0 {
		return result, errors.New("installed_apk_not_found")
	}
	if len(candidates) != 1 {
		return result, errors.New("installed_apk_ambiguous")
	}
	for path := range candidates {
		result.APK = path
	}
	return result, nil
}
