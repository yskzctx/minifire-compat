#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
. "$MODDIR/config.sh" || exit 1
read_target || { case "$1" in unmount|clear-cache) ;; *) exit 1;; esac; }
PROC=${MINIFIRE_PROC:-/proc}
NSENTER=${MINIFIRE_NSENTER:-nsenter}
APEX=${MINIFIRE_TRUST_APEX:-/apex/com.android.conscrypt/cacerts}
SYSTEM=${MINIFIRE_TRUST_SYSTEM:-/system/etc/security/cacerts}
STAGING=${MINIFIRE_TRUST_STAGE:-/data/local/tmp/minifire_compat_zygisk}
TRUST="$STAGING/trust"
fail(){ printf '%s\n' "$1"; exit 1; }
valid_pid(){ case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -gt 1 ]; }
clear_cache(){
    [ ! -d "$STAGING" ] || {
        [ ! -L "$STAGING" ] && [ ! -L "$TRUST" ] || return 1
        [ "$(stat -c %u "$STAGING")" = 0 ] || return 1
        for certificate in "$TRUST"/*; do
            [ -e "$certificate" ] || continue
            cache_name=${certificate##*/}
            printf '%s\n' "$cache_name" | grep -Eq '^[0-9a-f]{8}\.[0-9]+$' || return 1
            rm -f "$certificate" || return 1
        done
        [ ! -d "$TRUST" ] || rmdir "$TRUST" || return 1
        rmdir "$STAGING" || return 1
    }
    rm -f "$STATE/trust_ready"
}
game_process(){ [ -r "$PROC/$1/cmdline" ] && [ "$(tr '\000' '\n' < "$PROC/$1/cmdline" | head -n 1)" = "${2:-$GAME}" ]; }
unmount_trust(){
    [ -f "$STATE/mount_pid" ] && [ -f "$STATE/mount_ns" ] && [ -f "$STATE/mount_targets" ] || return 0
    IFS= read -r target_pid < "$STATE/mount_pid"
    IFS= read -r expected_ns < "$STATE/mount_ns"
    mounted_package=$DEFAULT_GAME
    if [ -f "$STATE/mount_package" ]; then IFS= read -r mounted_package < "$STATE/mount_package"; fi
    valid_package "$mounted_package" || { printf 'mounted_package_invalid\n'; return 1; }
    unmount_failed=0
    if valid_pid "$target_pid" && game_process "$target_pid" "$mounted_package" && [ "$(readlink "$PROC/$target_pid/ns/mnt")" = "$expected_ns" ]; then
        while IFS= read -r target; do
            case "$target" in /apex/com.android.conscrypt/cacerts|/system/etc/security/cacerts)
                if awk -v target="$target" '$5==target && ($4 ~ /minifire_compat_zygisk\/state\/trust/ || $4 ~ /local\/tmp\/minifire_compat_zygisk\/trust$/) {found=1} END {exit !found}' "$PROC/$target_pid/mountinfo"; then
                    "$NSENTER" -t "$target_pid" -m -- umount "$target" || unmount_failed=1
                fi;;
            esac
        done < "$STATE/mount_targets"
    fi
    [ "$unmount_failed" = 0 ] || { printf 'certificate_unmount_failed\n'; return 1; }
    rm -f "$STATE/mount_pid" "$STATE/mount_ns" "$STATE/mount_targets" "$STATE/mount_package"
}
case "$1" in
    prepare)
        case "$MODDIR" in */minifire_compat_zygisk) ;; *) fail module_directory_invalid;; esac
        [ -d "$APEX" ] && base=$APEX || base=$SYSTEM
        [ -d "$base" ] || fail system_trust_store_missing
        [ -s "$STATE/ca.pem" ] && [ -s "$STATE/ca-filename" ] || fail local_ca_missing
        IFS= read -r name < "$STATE/ca-filename"
        case "$name" in ????????.0) ;; *) fail local_ca_filename_invalid;; esac
        case "$name" in *[!0-9a-f.]* ) fail local_ca_filename_invalid;; esac
        clear_cache || fail certificate_cache_cleanup_failed
        [ ! -L "$STAGING" ] || fail certificate_cache_symlink_rejected
        mkdir -p "$STAGING" && [ "$(stat -c %u "$STAGING")" = 0 ] && chmod 0700 "$STAGING" || fail certificate_cache_owner_invalid
        mkdir "$TRUST" && chmod 0755 "$TRUST" || fail trust_directory_failed
        first=''
        for file in "$base"/*; do
            [ -f "$file" ] || continue
            printf '%s\n' "${file##*/}" | grep -Eq '^[0-9a-f]{8}\.[0-9]+$' || continue
            cp -L "$file" "$TRUST/${file##*/}" || fail trust_copy_failed
            [ -n "$first" ] || first=$file
        done
        [ -n "$first" ] || fail system_trust_store_empty
        cp "$STATE/ca.pem" "$TRUST/$name" || fail local_ca_copy_failed
        directory_context=$(ls -Zd "$base" | awk '{print $1}')
        file_context=$(ls -Z "$first" | awk '{print $1}')
        case "$directory_context:$file_context" in u:object_r:*:s0:u:object_r:*:s0) ;; *) fail certificate_context_unrecognized;; esac
        chcon "$directory_context" "$TRUST" || fail certificate_context_failed
        for file in "$TRUST"/*; do chmod 0644 "$file" && chcon "$file_context" "$file" || fail certificate_context_failed; done
        printf 'ready\n' > "$STATE/trust_ready"
        printf 'prepared\n'
        ;;
    mount)
        valid_pid "$2" && game_process "$2" || fail target_process_invalid
        namespace=$(readlink "$PROC/$2/ns/mnt")
        [ -n "$namespace" ] || fail target_namespace_missing
        for shared_pid in 1 $$ $(pidof zygote zygote64 zygote32 2>/dev/null); do
            shared=$(readlink "$PROC/$shared_pid/ns/mnt" 2>/dev/null)
            [ -z "$shared" ] || [ "$shared" != "$namespace" ] || fail shared_mount_namespace
        done
        [ -f "$STATE/trust_ready" ] || fail trust_not_prepared
        unmount_trust || fail previous_certificate_unmount_failed
        # A distinct namespace may still contain shared mounts. Stop propagation
        # inside the game namespace before adding any certificate bind mount.
        controller_namespace=$(readlink "$PROC/$$/ns/mnt")
        [ -n "$controller_namespace" ] || fail controller_namespace_missing
        helper="$PROC/$$/root$MODDIR/bin/minifire-external"
        "$NSENTER" -t "$2" -m -- "$helper" namespace-private --expected-namespace "$namespace" --controller-namespace "$controller_namespace" 2> "$STATE/trust-error.txt" || fail target_mount_propagation_failed
        printf '%s\n' "$2" > "$STATE/mount_pid"
        printf '%s\n' "$namespace" > "$STATE/mount_ns"
        printf '%s\n' "$GAME" > "$STATE/mount_package"
        : > "$STATE/mount_targets"
        source="$TRUST"
        mounted=0
        for target in "$APEX" "$SYSTEM"; do
            [ -d "$target" ] || continue
            # Record before the syscall so cancellation immediately after a
            # successful bind still leaves enough information for cleanup.
            printf '%s\n' "$target" >> "$STATE/mount_targets" || fail mount_record_failed
            if ! "$NSENTER" -t "$2" -m -- "$helper" namespace-bind --expected-namespace "$namespace" --controller-namespace "$controller_namespace" --source "$source" --target "$target" 2> "$STATE/trust-error.txt"; then
                unmount_trust; fail target_certificate_mount_failed
            fi
            mounted=$((mounted+1))
        done
        [ "$mounted" -gt 0 ] || fail target_trust_store_missing
        printf 'mounted\n'
        ;;
    unmount) unmount_trust || exit 1; printf 'unmounted\n';;
    clear-cache) [ ! -f "$STATE/mount_pid" ] || fail certificate_still_mounted; clear_cache || fail certificate_cache_cleanup_failed; printf 'certificate_cache_cleared\n';;
    *) exit 2;;
esac
