# Detect SteamStub DRM wrapper in Linux ELF (.bind section) or Windows PE
detect_steamstub_drm() {
    local bin_path="$1"
    [ -f "$bin_path" ] || return 1

    # Check 1: Linux ELF .bind section (readelf or strings)
    if command -v readelf >/dev/null 2>&1; then
        if readelf -S "$bin_path" 2>/dev/null | grep -Eq '(\.bind|[[:space:]]\.bind[[:space:]])'; then
            return 0
        fi
    fi

    # Check 2: Strings heuristic for SteamStub / SteamDRM markers
    if command -v strings >/dev/null 2>&1; then
        if strings -n 6 "$bin_path" 2>/dev/null | head -n 500 | grep -Eq '(SteamDRM|\.bind|SteamStub)'; then
            return 0
        fi
    fi

    return 1
}

# Distinguish SteamStub type (windows_pe, linux_elf, or unknown)
detect_steamstub_type() {
    local bin_path="$1"
    [ -f "$bin_path" ] || return 1
    if ! detect_steamstub_drm "$bin_path"; then
        return 1
    fi
    local btype
    btype=$(file -b "$bin_path" 2>/dev/null || echo "")
    if echo "$btype" | grep -qi -E "PE32|MS Windows"; then
        echo "windows_pe"
    elif case "$bin_path" in *.exe|*.EXE) true ;; *) false ;; esac; then
        echo "windows_pe"
    elif echo "$btype" | grep -qi "ELF"; then
        echo "linux_elf"
    else
        echo "unknown"
    fi
    return 0
}

# Check if a Linux ELF SteamStub (.bind) is actively protecting the binary
# (entry point resides inside the .bind section) or has been remediated
is_steamstub_elf_active() {
    local bin_path="$1"
    [ -f "$bin_path" ] || return 1
    if command -v readelf >/dev/null 2>&1; then
        local ep_hex b_addr_hex b_size_hex
        ep_hex=$(readelf -h "$bin_path" 2>/dev/null | awk '/Entry point address:/ { print $4 }')
        read -r b_addr_hex b_size_hex < <(readelf -S -W "$bin_path" 2>/dev/null | awk '{ for (i = 1; i <= NF; i++) if ($i == ".bind") { print "0x"$(i+2), "0x"$(i+4); break } }')
        if [ -n "$ep_hex" ] && [ -n "$b_addr_hex" ] && [ -n "$b_size_hex" ]; then
            local ep=$((ep_hex)) b_start=$((b_addr_hex)) b_end=$((b_addr_hex + b_size_hex))
            if [ "$ep" -lt "$b_start" ] || [ "$ep" -ge "$b_end" ]; then
                return 1
            fi
        fi
    fi
    return 0
}

# Resolve candidate unpacked binary for Windows PE SteamStub
resolve_unpacked_binary() {
    local gdir="$1"
    local gbin="$2"
    [ -d "$gdir" ] || return 1
    [ -n "$gbin" ] || return 1

    local base_no_ext="${gbin%.*}"
    local cand
    for cand in "${base_no_ext}.unpacked.exe" \
                "${base_no_ext}_unpacked.exe" \
                "${base_no_ext}-unpacked.exe" \
                "${gbin}.unpacked.exe" \
                "${base_no_ext}.unpacked" \
                "${base_no_ext}_unpacked" \
                "${gbin}.unpacked"; do
        if [ -f "$gdir/$cand" ]; then
            [ -x "$gdir/$cand" ] || chmod +x "$gdir/$cand" 2>/dev/null || true
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Find Steamless CLI executable on system
find_steamless_cli() {
    local cand
    for cand in "${GAMECTL_STEAMLESS_PATH:-}" \
                "$(command -v steamless 2>/dev/null || true)" \
                "$(command -v Steamless.CLI.exe 2>/dev/null || true)" \
                "$HOME/.local/share/steamless/Steamless.CLI.exe" \
                "$HOME/.local/share/steamless/Steamless.exe" \
                "$HOME/.config/gamectl/tools/Steamless.CLI.exe"; do
        if [ -n "$cand" ] && [ -f "$cand" ]; then
            echo "$cand"
            return 0
        fi
    done
    return 1
}

# Unpack Windows PE SteamStub binary via Steamless CLI
unpack_steamstub_pe() {
    local target_exe="$1"
    local runner_bin="${2:-}"
    local pfx_dir="${3:-}"
    [ -f "$target_exe" ] || return 1

    local gdir
    gdir="$(dirname "$target_exe")"
    local gbin
    gbin="$(basename "$target_exe")"

    # If already unpacked, nothing to do
    if resolve_unpacked_binary "$gdir" "$gbin" >/dev/null 2>&1; then
        return 0
    fi

    local steamless_bin
    steamless_bin=$(find_steamless_cli 2>/dev/null || true)
    if [ -z "$steamless_bin" ]; then
        return 1
    fi

    if [ -z "$runner_bin" ]; then
        runner_bin=$(find_runner "$gdir" 2>/dev/null || true)
    fi
    pfx_dir="${pfx_dir:-$gdir/pfx}"

    echo "  ${UI_CYAN:-}[INFO] Invoking Steamless CLI: $steamless_bin on $gbin...${UI_RST:-}"
    if [ -x "$steamless_bin" ] && ! echo "$steamless_bin" | grep -qi '\.exe$'; then
        "$steamless_bin" "$target_exe" >/dev/null 2>&1 || true
    elif command -v mono >/dev/null 2>&1; then
        mono "$steamless_bin" "$target_exe" >/dev/null 2>&1 || true
    elif command -v dotnet >/dev/null 2>&1; then
        dotnet "$steamless_bin" "$target_exe" >/dev/null 2>&1 || true
    elif [ -n "$runner_bin" ] && [ -x "$runner_bin" ]; then
        WINEPREFIX="${pfx_dir:-$gdir/pfx}" "$runner_bin" "$steamless_bin" "$target_exe" >/dev/null 2>&1 || true
    elif command -v wine >/dev/null 2>&1; then
        WINEPREFIX="${pfx_dir:-$gdir/pfx}" wine "$steamless_bin" "$target_exe" >/dev/null 2>&1 || true
    else
        return 1
    fi

    # Check if unpacked binary was produced
    if resolve_unpacked_binary "$gdir" "$gbin" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

# Unpack Linux ELF SteamStub binary (.bind section) via native Python unpacker
unpack_steamstub_elf() {
    local target_bin="$1"
    [ -f "$target_bin" ] || return 1

    local gdir
    gdir="$(dirname "$target_bin")"
    local gbin
    gbin="$(basename "$target_bin")"

    # If already unpacked, nothing to do
    if resolve_unpacked_binary "$gdir" "$gbin" >/dev/null 2>&1; then
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "  ${UI_AMBER:-}[WARN] python3 not available. Cannot unpack Linux SteamStub binary.${UI_RST:-}" >&2
        return 1
    fi

    echo "  ${UI_CYAN:-}[INFO] Unpacking Linux ELF SteamStub DRM (.bind) on $gbin...${UI_RST:-}"

    local out_bin="$gdir/${gbin}.unpacked"
    local py_rc=0
    python3 - "$target_bin" "$out_bin" << 'EOF_UNPACK_PY' || py_rc=$?
import sys, os, struct, subprocess

def decrypt_aes(key, iv, data):
    try:
        from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
        ecb = Cipher(algorithms.AES(key), modes.ECB()).decryptor()
        new_iv = ecb.update(iv) + ecb.finalize()
        cbc = Cipher(algorithms.AES(key), modes.CBC(new_iv)).decryptor()
        return cbc.update(data) + cbc.finalize()
    except Exception:
        pass
    try:
        key_hex = key.hex()
        p1 = subprocess.run(['openssl', 'enc', '-d', '-aes-256-ecb', '-K', key_hex, '-nopad'],
                            input=iv, capture_output=True, check=True)
        new_iv_hex = p1.stdout.hex()
        p2 = subprocess.run(['openssl', 'enc', '-d', '-aes-256-cbc', '-K', key_hex, '-iv', new_iv_hex, '-nopad'],
                            input=data, capture_output=True, check=True)
        return p2.stdout
    except Exception as e:
        sys.stderr.write(f"[ERROR] AES decryption failed: {e}\n")
        return None

def unpack(target_path, output_path):
    with open(target_path, 'rb') as f:
        magic = f.read(4)
        if magic != b'\x7fELF':
            sys.stderr.write("[ERROR] Not an ELF binary.\n")
            return 1
        ei_class = f.read(1)[0]
        ei_data = f.read(1)[0]
        endian = '<' if ei_data == 1 else '>'
        if ei_class not in (1, 2) or ei_data not in (1, 2):
            sys.stderr.write("[ERROR] Unsupported ELF encoding.\n")
            return 1

        f.seek(0x18)
        if ei_class == 1:
            entrypoint = struct.unpack(endian + 'I', f.read(4))[0]
            f.seek(0x20)
            shoff = struct.unpack(endian + 'I', f.read(4))[0]
            f.seek(0x2e)
            shentsize, shnum, shstrndx = struct.unpack(endian + 'HHH', f.read(6))
        else:
            entrypoint = struct.unpack(endian + 'Q', f.read(8))[0]
            f.seek(0x28)
            shoff = struct.unpack(endian + 'Q', f.read(8))[0]
            f.seek(0x3a)
            shentsize, shnum, shstrndx = struct.unpack(endian + 'HHH', f.read(6))

        f.seek(shoff + shstrndx * shentsize)
        if ei_class == 1:
            _, _, _, _, str_offset, str_size, _, _, _, _ = struct.unpack(endian + 'IIIIIIIIII', f.read(40))
        else:
            _, _, _, _, str_offset, str_size, _, _, _, _ = struct.unpack(endian + 'IIQQQQIIQQ', f.read(64))

        f.seek(str_offset)
        strtab = f.read(str_size)

        sections = []
        bind_sec = None
        for i in range(shnum):
            f.seek(shoff + i * shentsize)
            if ei_class == 1:
                name_idx, s_type, s_flags, s_addr, s_offset, s_size, _, _, _, _ = struct.unpack(endian + 'IIIIIIIIII', f.read(40))
            else:
                name_idx, s_type, s_flags, s_addr, s_offset, s_size, _, _, _, _ = struct.unpack(endian + 'IIQQQQIIQQ', f.read(64))
            name_end = strtab.find(b'\x00', name_idx)
            name = strtab[name_idx:name_end].decode('latin1', errors='replace')
            sec = {'name': name, 'type': s_type, 'flags': s_flags, 'addr': s_addr, 'offset': s_offset, 'size': s_size}
            sections.append(sec)
            if name == '.bind':
                bind_sec = sec

        if not bind_sec:
            sys.stderr.write("[ERROR] No .bind section found in ELF binary.\n")
            return 1

        f.seek(bind_sec['offset'])
        bind_data = f.read(bind_sec['size'])
        if len(bind_data) < 0xb0:
            sys.stderr.write("[ERROR] .bind section too small.\n")
            return 1

        candidates = []
        seen_cand = set()
        if bind_sec['addr'] <= entrypoint < bind_sec['addr'] + bind_sec['size']:
            bind_entry = entrypoint - bind_sec['addr']
            for h_sz in (0xc0, 0xd0, 0xb0):
                if bind_entry >= h_sz:
                    item = (bind_entry - h_sz, h_sz)
                    candidates.append(item)
                    seen_cand.add(item)

        for off in range(0, min(len(bind_data) - 0xb4, 0x8000), 4):
            for h_sz in (0xc0, 0xd0, 0xb0):
                item = (off, h_sz)
                if item not in seen_cand:
                    candidates.append(item)
                    seen_cand.add(item)

        pattern_64 = '<IQQIIQIIIIIIIIQQ32s16s16s16s32sQI'
        names_64 = ('signature base drm_entrypoint bind_offset u0 '
                    'real_entrypoint u1 payload_size u2 u3 appid '
                    'flags bind_virtual_size u4 code_virtual_addr '
                    'code_size aes_key aes_iv code_stolen keys u5 '
                    'u6 u7').split()

        pattern_32 = '<IQIIIIIIIIIIIIII32s16s16s16s'
        names_32 = ('signature base drm_entrypoint bind_offset u0 '
                    'real_entrypoint u1 payload_size drmp_offset drmp_size '
                    'appid flags bind_virtual_size u2 code_virtual_addr code_size '
                    'aes_key aes_iv code_stolen enc_keys').split()

        hdr_info = None
        arch = None

        for cand_off, h_sz in candidates:
            if cand_off + h_sz + 4 > len(bind_data):
                continue
            key = int.from_bytes(bind_data[cand_off:cand_off+4], byteorder='little')
            header_bytes = bytearray()
            h_off = cand_off
            end_off = cand_off + h_sz
            while h_off < end_off:
                h_off += 4
                val = int.from_bytes(bind_data[h_off:h_off+4], byteorder='little')
                header_bytes.extend(int.to_bytes(val ^ key, 4, byteorder='little'))
                key = val

            if len(header_bytes) >= 4:
                sig = int.from_bytes(header_bytes[0:4], byteorder='little')
                if sig == 0xc0dec0df and len(header_bytes) >= struct.calcsize(pattern_64):
                    raw_tuple = struct.unpack(pattern_64, bytes(header_bytes[:struct.calcsize(pattern_64)]))
                    hdr_info = dict(zip(names_64, raw_tuple))
                    arch = 'x64'
                    break
                elif sig == 0xc0dec0de and len(header_bytes) >= struct.calcsize(pattern_32):
                    raw_tuple = struct.unpack(pattern_32, bytes(header_bytes[:struct.calcsize(pattern_32)]))
                    hdr_info = dict(zip(names_32, raw_tuple))
                    arch = 'x86'
                    break

        if not hdr_info:
            sys.stderr.write("[ERROR] SteamStub .bind header signature (0xc0dec0df / 0xc0dec0de) not found.\n")
            return 1

        flags = hdr_info.get('flags', 0)
        is_encrypted = not bool(flags & 0x04)

        f.seek(0)
        file_bytes = bytearray(f.read())

        if is_encrypted:
            code_sec = None
            c_addr = hdr_info['code_virtual_addr']
            for s in sections:
                if (s['addr'] <= c_addr < s['addr'] + s['size']) or (s['offset'] <= c_addr < s['offset'] + s['size']):
                    code_sec = s
                    break

            if not code_sec:
                for s in sections:
                    if s['name'] == '.text':
                        code_sec = s
                        break

            if not code_sec:
                sys.stderr.write(f"[ERROR] Could not identify code section for virtual addr 0x{c_addr:x}.\n")
                return 1

            f.seek(code_sec['offset'])
            enc_code_from_sec = f.read(min(hdr_info['code_size'], code_sec['size']))
            code_payload = bytearray(hdr_info['code_stolen'])
            code_payload.extend(enc_code_from_sec)

            decrypted_code = decrypt_aes(hdr_info['aes_key'], hdr_info['aes_iv'], bytes(code_payload))
            if not decrypted_code:
                sys.stderr.write("[ERROR] Decryption of code section failed.\n")
                return 1

            write_len = min(len(decrypted_code), code_sec['size'], max(0, len(file_bytes) - code_sec['offset']))
            file_bytes[code_sec['offset'] : code_sec['offset'] + write_len] = decrypted_code[:write_len]

        real_ep = hdr_info['real_entrypoint']
        base_addr = hdr_info.get('base', 0)
        if arch == 'x86':
            if real_ep < base_addr:
                real_ep = real_ep + base_addr
            ep_bytes = struct.pack(endian + 'I', real_ep & 0xffffffff)
        else:
            code_sec_addr = 0
            for s in sections:
                if s['name'] == '.text':
                    code_sec_addr = s['addr']
                    break
            base_ref = base_addr if base_addr > 0 else code_sec_addr
            if real_ep < base_ref:
                real_ep = real_ep + base_ref
            ep_bytes = struct.pack(endian + 'Q', real_ep)

        file_bytes[0x18 : 0x18 + len(ep_bytes)] = ep_bytes

        with open(output_path, 'wb') as out_f:
            out_f.write(file_bytes)

        os.chmod(output_path, 0o755)
        sys.stdout.write(f"[SUCCESS] Unpacked SteamStub ELF ({arch}, AppID: {hdr_info['appid']}) -> {output_path}\n")
        return 0

target = sys.argv[1]
output = sys.argv[2]
sys.exit(unpack(target, output))
EOF_UNPACK_PY

    if [ "$py_rc" -eq 0 ] && [ -f "$out_bin" ] && [ -x "$out_bin" ]; then
        return 0
    fi
    rm -f "$out_bin" 2>/dev/null || true
    return 1
}

# Setup sovereign Steam interceptor scripts in target directory
setup_steam_interceptor() {
    local target_dir="${1:-$(get_runtime_dir)/interceptor}"
    mkdir -p -m 700 "$target_dir" 2>/dev/null || mkdir -p "$target_dir"
    cat << 'EOF_INTERCEPTOR' > "$target_dir/steam"
#!/usr/bin/env bash
# Sovereign Steam Interceptor: traps and silences unshielded Steam Client calls
target_appid=""
for arg in "$@"; do
    case "$arg" in
        steam://run/*)
            target_appid="${arg##steam://run/}"
            target_appid="${target_appid%%/*}"
            ;;
    esac
done
if [ -n "$target_appid" ]; then
    echo "[gamectl interceptor] Blocked unsolicited Steam Client launch (steam://run/$target_appid)" >&2
else
    echo "[gamectl interceptor] Blocked unsolicited Steam Client launch ($*)" >&2
fi
exit 0
EOF_INTERCEPTOR
    chmod +x "$target_dir/steam" 2>/dev/null || true
    cp -f "$target_dir/steam" "$target_dir/steam.sh" 2>/dev/null || true
    return 0
}

# Forensic diagnostics report for SteamStub DRM inspection
diagnose_steamstub() {
    local bin_path="$1"
    if [ ! -f "$bin_path" ]; then
        echo "[ERROR] File not found: $bin_path" >&2
        return 1
    fi

    local b_name
    b_name="$(basename "$bin_path")"
    local b_dir
    b_dir="$(dirname "$bin_path")"
    local b_type
    b_type=$(file -b "$bin_path" 2>/dev/null || echo "Unknown")

    echo "╭─ STEAMSTUB FORENSIC DIAGNOSTICS ────────────────────────────╮"
    echo "│ Target Binary : $b_name"
    echo "│ Full Path     : $bin_path"
    echo "│ Architecture  : $b_type"

    local is_stub=false
    local stub_type="none"

    if detect_steamstub_drm "$bin_path"; then
        is_stub=true
        stub_type=$(detect_steamstub_type "$bin_path" 2>/dev/null || echo "unknown")
    fi

    if [ "$is_stub" = true ]; then
        if [ "$stub_type" = "windows_pe" ]; then
            local up_bin
            up_bin=$(resolve_unpacked_binary "$b_dir" "$b_name" 2>/dev/null || true)
            if [ "$b_name" = "$up_bin" ] || case "$b_name" in *.unpacked.exe|*_unpacked.exe|*-unpacked.exe) true ;; *) false ;; esac; then
                echo "│ DRM Status    : ${UI_GREEN:-}[REMEDIATED] Windows PE SteamStub (unpacked / DRM cleared)${UI_RST:-}"
                echo "│ Unpack Status : ${UI_GREEN:-}[ACTIVE] Executable DRM wrapper removed${UI_RST:-}"
                echo "│ Remediation   : Binary is unpacked and ready for Proton/Wine execution"
            elif [ -n "$up_bin" ]; then
                echo "│ DRM Status    : ${UI_AMBER:-}[DETECTED] Windows PE SteamStub DRM${UI_RST:-}"
                echo "│ Unpack Status : ${UI_GREEN:-}[READY] Unpacked counterpart found: $up_bin${UI_RST:-}"
                echo "│ Remediation   : launch_game will automatically execute $up_bin"
            else
                echo "│ DRM Status    : ${UI_AMBER:-}[DETECTED] Windows PE SteamStub DRM${UI_RST:-}"
                echo "│ Unpack Status : ${UI_AMBER:-}[PENDING] No unpacked binary found${UI_RST:-}"
                local s_cli
                s_cli=$(find_steamless_cli 2>/dev/null || true)
                if [ -n "$s_cli" ]; then
                    echo "│ Steamless CLI : ${UI_GREEN:-}[AVAILABLE] $s_cli${UI_RST:-}"
                    echo "│ Action        : Run 'gamectl unpack-stub \"$bin_path\"'"
                else
                    echo "│ Steamless CLI : ${UI_AMBER:-}[NOT FOUND] Place Steamless in ~/.local/share/steamless/${UI_RST:-}"
                    echo "│ Remediation   : Unpack $b_name with Steamless or provide ${b_name%.*}.unpacked.exe"
                fi
            fi
        elif [ "$stub_type" = "linux_elf" ]; then
            local is_active=true
            if ! is_steamstub_elf_active "$bin_path"; then
                is_active=false
            fi

            local up_bin
            up_bin=$(resolve_unpacked_binary "$b_dir" "$b_name" 2>/dev/null || true)
            if [ "$is_active" = false ] || [ "$b_name" = "$up_bin" ]; then
                echo "│ DRM Status    : ${UI_GREEN:-}[REMEDIATED] Linux ELF SteamStub (.bind inactive / OEP restored)${UI_RST:-}"
                echo "│ Unpack Status : ${UI_GREEN:-}[ACTIVE] Executable entry point points to original code${UI_RST:-}"
                echo "│ Remediation   : Binary is unpacked and ready for direct execution"
            elif [ -n "$up_bin" ]; then
                echo "│ DRM Status    : ${UI_AMBER:-}[DETECTED] Linux ELF SteamStub (.bind section)${UI_RST:-}"
                echo "│ Unpack Status : ${UI_GREEN:-}[READY] Unpacked counterpart found: $up_bin${UI_RST:-}"
                echo "│ Remediation   : launch_game will automatically execute $up_bin"
            else
                echo "│ DRM Status    : ${UI_AMBER:-}[DETECTED] Linux ELF SteamStub (.bind section)${UI_RST:-}"
                echo "│ Unpack Status : ${UI_AMBER:-}[PENDING] No unpacked binary found${UI_RST:-}"
                echo "│ Action        : Run 'gamectl unpack-stub \"$bin_path\"' to decrypt .bind section"
            fi
            echo "│ Interceptor   : ${UI_GREEN:-}[ACTIVE] Sovereign steam.sh trap prevents Steam Client launch${UI_RST:-}"
            local cand_win
            cand_win=$(find "$b_dir" -maxdepth 2 -iname "*.exe" 2>/dev/null | head -n 1 || true)
            if [ -n "$cand_win" ]; then
                echo "│ Runner Option : Windows executable found ($(basename "$cand_win")). Can run via Proton with Steamless."
            else
                echo "│ Runner Option : Pure Linux native. Runs with unpacked binary and sovereign steam.sh trap."
            fi
        else
            echo "│ DRM Status    : ${UI_AMBER:-}[DETECTED] SteamStub / SteamDRM markers found${UI_RST:-}"
        fi
    else
        echo "│ DRM Status    : ${UI_GREEN:-}[CLEAN] No SteamStub DRM markers detected${UI_RST:-}"
    fi
    echo "╰─────────────────────────────────────────────────────────────╯"

    [ "$is_stub" = true ] && return 0 || return 1
}

# CLI subcommand handler for unpacking SteamStub Windows PE or Linux ELF binaries
cli_unpack_stub() {
    local target="$1"
    if [ ! -f "$target" ]; then
        echo "[ERROR] Target file not found: $target" >&2
        return 1
    fi
    local up_res
    up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
    if [ -n "$up_res" ]; then
        echo "[VERIFIED] Binary is already unpacked: $up_res"
        return 0
    fi

    local stype
    stype=$(detect_steamstub_type "$target" 2>/dev/null || echo "unknown")

    if [ "$stype" = "linux_elf" ]; then
        echo "[INFO] Attempting to unpack Linux ELF binary $target..."
        if unpack_steamstub_elf "$target"; then
            up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
            echo "[SUCCESS] Binary successfully unpacked: $up_res"
            return 0
        else
            echo "[ERROR] Failed to unpack Linux ELF SteamStub binary." >&2
            return 1
        fi
    elif [ "$stype" = "windows_pe" ]; then
        echo "[INFO] Attempting to unpack Windows PE binary $target via Steamless CLI..."
        if unpack_steamstub_pe "$target"; then
            up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
            echo "[SUCCESS] Binary successfully unpacked: $up_res"
            return 0
        else
            echo "[ERROR] Failed to unpack binary. Ensure Steamless CLI is installed or run under Wine." >&2
            return 1
        fi
    else
        echo "[INFO] Architecture undetermined. Probing Linux ELF and Windows PE unpackers..."
        if unpack_steamstub_elf "$target" || unpack_steamstub_pe "$target"; then
            up_res=$(resolve_unpacked_binary "$(dirname "$target")" "$(basename "$target")" 2>/dev/null || true)
            echo "[SUCCESS] Binary successfully unpacked: $up_res"
            return 0
        else
            echo "[ERROR] Failed to unpack binary with available unpackers." >&2
            return 1
        fi
    fi
}

