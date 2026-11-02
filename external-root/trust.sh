#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
PROC=${MINIFIRE_PROC:-/proc}
NSENTER=${MINIFIRE_NSENTER:-nsenter}
APEX=${MINIFIRE_TRUST_APEX:-/apex/com.android.conscrypt/cacerts}
SYSTEM=${MINIFIRE_TRUST_SYSTEM:-/system/etc/security/cacerts}
fail(){ printf '%s\n' "$1"; exit 1; }
valid_pid(){ case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -gt 1 ]; }
game_process(){ [ -r "$PROC/$1/cmdline" ] && [ "$(tr '\000' '\n' < "$PROC/$1/cmdline" | head -n 1)" = com.miniworldroyale.sparkgame ]; }
unmount_trust(){
    [ -f "$STATE/mount_pid" ] && [ -f "$STATE/mount_ns" ] && [ -f "$STATE/mount_targets" ] || return 0
    IFS= read -r target_pid < "$STATE/mount_pid"
    IFS= read -r expected_ns < "$STATE/mount_ns"
    if valid_pid "$target_pid" && game_process "$target_pid" && [ "$(readlink "$PROC/$target_pid/ns/mnt")" = "$expected_ns" ]; then
        while IFS= read -r target; do
            case "$target" in /apex/com.android.conscrypt/cacerts|/system/etc/security/cacerts)
                if awk -v target="$target" '$5==target && $4 ~ /minifire_compat_zygisk\/state\/trust/ {found=1} END {exit !found}' "$PROC/$target_pid/mountinfo"; then
                    "$NSENTER" -t "$target_pid" -m -- umount "$target" 2>/dev/null || :
                fi;;
            esac
        done < "$STATE/mount_targets"
    fi
    rm -f "$STATE/mount_pid" "$STATE/mount_ns" "$STATE/mount_targets"
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
        mkdir -p "$STATE/trust" && chmod 0755 "$STATE/trust" || fail trust_directory_failed
        rm -f "$STATE/trust"/*
        first=''
        for file in "$base"/*; do
            [ -f "$file" ] || continue
            cp -L "$file" "$STATE/trust/${file##*/}" || fail trust_copy_failed
            [ -n "$first" ] || first=$file
        done
        [ -n "$first" ] || fail system_trust_store_empty
        cp "$STATE/ca.pem" "$STATE/trust/$name" || fail local_ca_copy_failed
        directory_context=$(ls -Zd "$base" | awk '{print $1}')
        file_context=$(ls -Z "$first" | awk '{print $1}')
        case "$directory_context:$file_context" in u:object_r:*:s0:u:object_r:*:s0) ;; *) fail certificate_context_unrecognized;; esac
        chcon "$directory_context" "$STATE/trust" || fail certificate_context_failed
        for file in "$STATE/trust"/*; do chmod 0644 "$file" && chcon "$file_context" "$file" || fail certificate_context_failed; done
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
        unmount_trust
        # A distinct namespace may still contain shared mounts. Stop propagation
        # inside the game namespace before adding any certificate bind mount.
        "$NSENTER" -t "$2" -m -- mount --make-rprivate / 2> "$STATE/trust-error.txt" || fail target_mount_propagation_failed
        printf '%s\n' "$2" > "$STATE/mount_pid"
        printf '%s\n' "$namespace" > "$STATE/mount_ns"
        : > "$STATE/mount_targets"
        source="$PROC/$$/root$STATE/trust"
        mounted=0
        for target in "$APEX" "$SYSTEM"; do
            [ -d "$target" ] || continue
            if ! "$NSENTER" -t "$2" -m -- mount --bind "$source" "$target" 2> "$STATE/trust-error.txt"; then
                unmount_trust; fail target_certificate_mount_failed
            fi
            printf '%s\n' "$target" >> "$STATE/mount_targets"
            mounted=$((mounted+1))
        done
        [ "$mounted" -gt 0 ] || fail target_trust_store_missing
        printf 'mounted\n'
        ;;
    unmount) unmount_trust; printf 'unmounted\n';;
    *) exit 2;;
esac
