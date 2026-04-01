#!/usr/bin/env bash
# claw-friends: crypto.sh
# RSA-2048 + AES-256-CBC hybrid encryption
# Core cryptographic operations
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
PRIVATE_KEY="${OCFR_DIR}/keys/private.pem"
PUBLIC_KEY="${OCFR_DIR}/keys/public.pem"
_CLEANUP_DIR=""

# Cleanup temp files on exit
_cleanup() {
    if [ -n "${_CLEANUP_DIR:-}" ] && [ -d "${_CLEANUP_DIR:-}" ]; then
        rm -rf "${_CLEANUP_DIR}"
    fi
}
trap _cleanup EXIT

# Create temp directory
_make_tmpdir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIR="${tmpdir}"
    echo "${tmpdir}"
}

# ─────────────────────────────────────────────────────────────
# Encrypt
# Encrypts plaintext from stdin, outputs YAML fields to stdout
# ─────────────────────────────────────────────────────────────

do_encrypt() {
    local recipient_pubkey="$1"

    if [ ! -f "${recipient_pubkey}" ]; then
        echo "ERROR: Recipient public key not found: ${recipient_pubkey}" >&2
        exit 1
    fi

    local tmpdir
    tmpdir=$(_make_tmpdir)

    # Read plaintext from stdin
    cat > "${tmpdir}/plaintext.bin"

    if [ ! -s "${tmpdir}/plaintext.bin" ]; then
        echo "ERROR: No plaintext provided on stdin" >&2
        exit 1
    fi

    # Generate random AES-256 key and IV
    openssl rand 32 > "${tmpdir}/aes_key.bin"
    openssl rand 16 > "${tmpdir}/iv.bin"

    # Convert to hex for openssl enc
    local aes_key_hex iv_hex
    aes_key_hex=$(xxd -p -c 64 "${tmpdir}/aes_key.bin")
    iv_hex=$(xxd -p -c 32 "${tmpdir}/iv.bin")

    # Encrypt content with AES-256-CBC
    openssl enc -aes-256-cbc \
        -K "${aes_key_hex}" \
        -iv "${iv_hex}" \
        -in "${tmpdir}/plaintext.bin" \
        -out "${tmpdir}/encrypted.bin"

    # Encrypt AES key with RSA public key (OAEP/SHA-256)
    openssl pkeyutl -encrypt \
        -pubin -inkey "${recipient_pubkey}" \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -in "${tmpdir}/aes_key.bin" \
        -out "${tmpdir}/encrypted_key.bin"

    # Convert to base64
    local encrypted_key_b64 iv_b64 encrypted_content_b64
    encrypted_key_b64=$(base64 < "${tmpdir}/encrypted_key.bin" | tr -d '\n')
    iv_b64=$(base64 < "${tmpdir}/iv.bin" | tr -d '\n')
    encrypted_content_b64=$(base64 < "${tmpdir}/encrypted.bin" | tr -d '\n')

    # Output YAML fields
    echo "encrypted_key: \"${encrypted_key_b64}\""
    echo "iv: \"${iv_b64}\""
    echo "encrypted_content: \"${encrypted_content_b64}\""
}

# ─────────────────────────────────────────────────────────────
# Decrypt
# Decrypts a message YAML file, outputs plaintext to stdout
# ─────────────────────────────────────────────────────────────

do_decrypt() {
    local message_file="$1"

    if [ ! -f "${message_file}" ]; then
        echo "ERROR: Message file not found: ${message_file}" >&2
        exit 1
    fi

    if [ ! -f "${PRIVATE_KEY}" ]; then
        echo "ERROR: Private key not found at ${PRIVATE_KEY}" >&2
        echo "Run /friends init to generate keys." >&2
        exit 1
    fi

    local tmpdir
    tmpdir=$(_make_tmpdir)

    # Parse YAML fields (simple grep/sed approach)
    local encrypted_key_b64 iv_b64 encrypted_content_b64
    encrypted_key_b64=$(grep '^encrypted_key:' "${message_file}" | sed 's/^encrypted_key: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    iv_b64=$(grep '^iv:' "${message_file}" | sed 's/^iv: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    encrypted_content_b64=$(grep '^encrypted_content:' "${message_file}" | sed 's/^encrypted_content: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

    if [ -z "${encrypted_key_b64}" ]; then
        echo "ERROR: Missing 'encrypted_key' field in ${message_file}" >&2
        exit 1
    fi
    if [ -z "${iv_b64}" ]; then
        echo "ERROR: Missing 'iv' field in ${message_file}" >&2
        exit 1
    fi
    if [ -z "${encrypted_content_b64}" ]; then
        echo "ERROR: Missing 'encrypted_content' field in ${message_file}" >&2
        exit 1
    fi

    # Decode from base64
    echo -n "${encrypted_key_b64}" | base64 -d > "${tmpdir}/encrypted_key.bin"
    echo -n "${iv_b64}" | base64 -d > "${tmpdir}/iv.bin"
    echo -n "${encrypted_content_b64}" | base64 -d > "${tmpdir}/encrypted.bin"

    # Decrypt AES key with RSA private key
    if ! openssl pkeyutl -decrypt \
        -inkey "${PRIVATE_KEY}" \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -in "${tmpdir}/encrypted_key.bin" \
        -out "${tmpdir}/aes_key.bin" 2>/dev/null; then
        echo "ERROR: Decryption failed. Wrong key or corrupted message." >&2
        exit 1
    fi

    # Convert key and IV to hex
    local aes_key_hex iv_hex
    aes_key_hex=$(xxd -p -c 64 "${tmpdir}/aes_key.bin")
    iv_hex=$(xxd -p -c 32 "${tmpdir}/iv.bin")

    # Decrypt content with AES-256-CBC
    if ! openssl enc -d -aes-256-cbc \
        -K "${aes_key_hex}" \
        -iv "${iv_hex}" \
        -in "${tmpdir}/encrypted.bin" 2>/dev/null; then
        echo "ERROR: AES decryption failed. Message may be corrupted." >&2
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
# Verify Keys
# ─────────────────────────────────────────────────────────────

do_verify() {
    local status=0

    echo "密钥验证:"
    echo ""

    # Check private key
    if [ -f "${PRIVATE_KEY}" ]; then
        echo "  私钥：OK (${PRIVATE_KEY})"
        if openssl rsa -in "${PRIVATE_KEY}" -check -noout 2>/dev/null; then
            echo "    RSA 验证：OK"
        else
            echo "    RSA 验证：FAILED (密钥可能已损坏)"
            status=1
        fi
    else
        echo "  私钥：NOT FOUND"
        status=1
    fi

    # Check public key
    local public_key="${OCFR_DIR}/keys/public.pem"
    if [ -f "${public_key}" ]; then
        echo "  公钥：OK (${public_key})"
    else
        echo "  公钥：NOT FOUND"
        status=1
    fi

    # Round-trip test
    if [ $status -eq 0 ] && [ -f "${public_key}" ]; then
        local tmpdir
        tmpdir=$(_make_tmpdir)

        local test_msg="ocfr_key_test_$(date +%s)"

        # Encrypt
        echo -n "${test_msg}" > "${tmpdir}/test_input.txt"
        cat "${tmpdir}/test_input.txt" | do_encrypt "${public_key}" > "${tmpdir}/test_encrypted.yaml" 2>/dev/null

        # Add metadata to make it look like a real message file
        {
            echo "from: \"self-test\""
            echo "timestamp: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
            cat "${tmpdir}/test_encrypted.yaml"
        } > "${tmpdir}/test_full.yaml"

        # Decrypt
        local decrypted
        decrypted=$(do_decrypt "${tmpdir}/test_full.yaml" 2>/dev/null) || true

        if [ "${decrypted}" = "${test_msg}" ]; then
            echo ""
            echo "  往返测试：OK (加密/解密验证通过)"
        else
            echo ""
            echo "  往返测试：FAILED"
            status=1
        fi
    fi

    echo ""
    return $status
}

# ─────────────────────────────────────────────────────────────
# Generate Keys
# ─────────────────────────────────────────────────────────────

do_keygen() {
    local output_dir="${1:-${OCFR_DIR}/keys}"

    mkdir -p "${output_dir}"

    # Generate RSA-2048 private key
    openssl genrsa -out "${output_dir}/private.pem" 2048 2>/dev/null

    # Extract public key
    openssl rsa -in "${output_dir}/private.pem" -pubout -out "${output_dir}/public.pem" 2>/dev/null

    # Set permissions
    chmod 600 "${output_dir}/private.pem"
    chmod 644 "${output_dir}/public.pem"

    echo "OK: RSA-2048 密钥对已生成"
    echo "  私钥：${output_dir}/private.pem (chmod 600)"
    echo "  公钥：${output_dir}/public.pem"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

usage() {
    echo "用法：$0 <命令> <参数>"
    echo ""
    echo "命令:"
    echo "  encrypt <recipient_pubkey_file>"
    echo "      加密消息。从 stdin 读取明文，输出 YAML 字段到 stdout。"
    echo ""
    echo "  decrypt <message_yaml_file>"
    echo "      解密消息文件。输出明文到 stdout。"
    echo ""
    echo "  verify"
    echo "      验证本地密钥是否有效。"
    echo ""
    echo "  keygen [output_dir]"
    echo "      生成新的 RSA 密钥对。"
    echo ""
    exit 1
}

if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    encrypt)
        if [ $# -lt 2 ]; then
            echo "ERROR: encrypt 需要 <recipient_pubkey_file>" >&2
            exit 1
        fi
        do_encrypt "$2"
        ;;
    decrypt)
        if [ $# -lt 2 ]; then
            echo "ERROR: decrypt 需要 <message_yaml_file>" >&2
            exit 1
        fi
        do_decrypt "$2"
        ;;
    verify)
        do_verify
        ;;
    keygen)
        do_keygen "${2:-}"
        ;;
    *)
        usage
        ;;
esac
