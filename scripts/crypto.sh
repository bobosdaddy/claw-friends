#!/usr/bin/env bash
# claw-friends: crypto.sh
# RSA-2048 + AES-256-CBC hybrid encryption for messages
#
# Encrypt: reads plaintext from STDIN, RSA encrypts a random AES key,
#          AES encrypts the message body. Outputs YAML fields to stdout.
# Decrypt: RSA decrypts the AES key, AES decrypts the message body.
#          Outputs plaintext to stdout.
#
# This avoids RSA plaintext size limits and is standard hybrid encryption.
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
PRIVATE_KEY="${OCFR_DIR}/keys/private.pem"
_CLEANUP_DIR=""

_cleanup() {
    if [ -n "${_CLEANUP_DIR:-}" ] && [ -d "${_CLEANUP_DIR:-}" ]; then
        rm -rf "${_CLEANUP_DIR}"
    fi
}
trap _cleanup EXIT

_make_tmpdir() {
    local tmpdir
    tmpdir=$(mktemp -d)
    _CLEANUP_DIR="${tmpdir}"
    echo "${tmpdir}"
}

usage() {
    echo "Usage: $0 <command> <args>"
    echo ""
    echo "Commands:"
    echo "  encrypt <recipient_pubkey_file>"
    echo "      Encrypt a message for a recipient. Reads plaintext from STDIN."
    echo "      Outputs YAML fields (encrypted_key, iv, encrypted_content) to stdout."
    echo ""
    echo "  decrypt <message_yaml_file>"
    echo "      Decrypt a received message file. Outputs plaintext to stdout."
    echo ""
    echo "  verify"
    echo "      Verify that local keys exist and are valid."
    exit 1
}

do_encrypt() {
    local recipient_pubkey="$1"

    if [ ! -f "${recipient_pubkey}" ]; then
        echo "ERROR: Recipient public key not found: ${recipient_pubkey}" >&2
        exit 1
    fi

    local tmpdir
    tmpdir=$(_make_tmpdir)

    # Read plaintext from stdin into a temp file (avoids exposing in process list)
    cat > "${tmpdir}/plaintext.bin"
    chmod 600 "${tmpdir}/plaintext.bin"

    if [ ! -s "${tmpdir}/plaintext.bin" ]; then
        echo "ERROR: No plaintext provided on stdin." >&2
        exit 1
    fi

    # Generate random AES-256 key (32 bytes) and IV (16 bytes)
    openssl rand 32 > "${tmpdir}/aes_key.bin"
    openssl rand 16 > "${tmpdir}/iv.bin"

    # Read key/iv hex for openssl enc (via file, not command line args)
    local aes_key_hex iv_hex
    aes_key_hex=$(xxd -p -c 64 "${tmpdir}/aes_key.bin")
    iv_hex=$(xxd -p -c 32 "${tmpdir}/iv.bin")

    # Encrypt the message with AES-256-CBC
    openssl enc -aes-256-cbc \
        -K "${aes_key_hex}" \
        -iv "${iv_hex}" \
        -in "${tmpdir}/plaintext.bin" \
        -out "${tmpdir}/encrypted.bin"

    # Encrypt the AES key with recipient's RSA public key (OAEP padding)
    openssl pkeyutl -encrypt \
        -pubin -inkey "${recipient_pubkey}" \
        -pkeyopt rsa_padding_mode:oaep \
        -pkeyopt rsa_oaep_md:sha256 \
        -in "${tmpdir}/aes_key.bin" \
        -out "${tmpdir}/encrypted_key.bin"

    # Output as base64-encoded YAML fields
    local encrypted_key_b64 iv_b64 encrypted_content_b64
    encrypted_key_b64=$(base64 < "${tmpdir}/encrypted_key.bin" | tr -d '\n')
    iv_b64=$(base64 < "${tmpdir}/iv.bin" | tr -d '\n')
    encrypted_content_b64=$(base64 < "${tmpdir}/encrypted.bin" | tr -d '\n')

    echo "encrypted_key: \"${encrypted_key_b64}\""
    echo "iv: \"${iv_b64}\""
    echo "encrypted_content: \"${encrypted_content_b64}\""
}

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

    # Parse YAML fields with validation
    local encrypted_key_b64 iv_b64 encrypted_content_b64
    encrypted_key_b64=$(grep '^encrypted_key:' "${message_file}" | sed 's/^encrypted_key: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || true)
    iv_b64=$(grep '^iv:' "${message_file}" | sed 's/^iv: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || true)
    encrypted_content_b64=$(grep '^encrypted_content:' "${message_file}" | sed 's/^encrypted_content: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || true)

    # Validate all fields are present
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

    # Decrypt AES key with RSA private key (OAEP padding)
    if ! openssl pkeyutl -decrypt \
            -inkey "${PRIVATE_KEY}" \
            -pkeyopt rsa_padding_mode:oaep \
            -pkeyopt rsa_oaep_md:sha256 \
            -in "${tmpdir}/encrypted_key.bin" \
            -out "${tmpdir}/aes_key.bin" 2>/dev/null; then
        echo "ERROR: Decryption failed. Wrong key or corrupted message." >&2
        exit 1
    fi

    # Read key/iv hex
    local aes_key_hex iv_hex
    aes_key_hex=$(xxd -p -c 64 "${tmpdir}/aes_key.bin")
    iv_hex=$(xxd -p -c 32 "${tmpdir}/iv.bin")

    # Decrypt message with AES key
    if ! openssl enc -d -aes-256-cbc \
            -K "${aes_key_hex}" \
            -iv "${iv_hex}" \
            -in "${tmpdir}/encrypted.bin" 2>/dev/null; then
        echo "ERROR: AES decryption failed. Message may be corrupted." >&2
        exit 1
    fi
}

do_verify() {
    local status=0

    if [ -f "${PRIVATE_KEY}" ]; then
        echo "Private key: OK (${PRIVATE_KEY})"
        if openssl rsa -in "${PRIVATE_KEY}" -check -noout 2>/dev/null; then
            echo "  RSA validation: OK"
        else
            echo "  RSA validation: FAILED (key may be corrupted)"
            status=1
        fi
    else
        echo "Private key: NOT FOUND"
        status=1
    fi

    local public_key="${OCFR_DIR}/keys/public.pem"
    if [ -f "${public_key}" ]; then
        echo "Public key:  OK (${public_key})"
    else
        echo "Public key:  NOT FOUND"
        status=1
    fi

    # Quick round-trip test
    if [ $status -eq 0 ]; then
        local tmpdir
        tmpdir=$(_make_tmpdir)

        local test_msg="ocfr_key_test_$(date +%s)"

        # Encrypt with own public key (plaintext via stdin)
        echo -n "${test_msg}" | do_encrypt "${public_key}" > "${tmpdir}/test_msg.yaml" 2>/dev/null
        {
            echo "from: \"self-test\""
            echo "timestamp: \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
            cat "${tmpdir}/test_msg.yaml"
        } > "${tmpdir}/test_msg_full.yaml"

        local decrypted
        decrypted=$(do_decrypt "${tmpdir}/test_msg_full.yaml" 2>/dev/null) || true

        if [ "${decrypted}" = "${test_msg}" ]; then
            echo "Round-trip:  OK (encrypt/decrypt verified)"
        else
            echo "Round-trip:  FAILED"
            status=1
        fi
    fi

    return $status
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    encrypt)
        if [ $# -lt 2 ]; then
            echo "ERROR: encrypt requires <recipient_pubkey_file>" >&2
            echo "Plaintext is read from stdin." >&2
            exit 1
        fi
        do_encrypt "$2"
        ;;
    decrypt)
        if [ $# -lt 2 ]; then
            echo "ERROR: decrypt requires <message_yaml_file>" >&2
            exit 1
        fi
        do_decrypt "$2"
        ;;
    verify)
        do_verify
        ;;
    *)
        usage
        ;;
esac
