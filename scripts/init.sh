#!/usr/bin/env bash
# claw-friends: init.sh
# Handles key generation and repo cloning for /friends init
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
KEYS_DIR="${OCFR_DIR}/keys"
REPO_DIR="${OCFR_DIR}/repo"
DEFAULT_REPO="https://github.com/bobosdaddy/claw-friends-data"

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  keygen              Generate RSA-2048 key pair"
    echo "  clone [repo_url]    Clone the social repo (default: ${DEFAULT_REPO})"
    echo "  check               Verify prerequisites are installed"
    echo "  status              Show current init status"
    exit 1
}

check_prerequisites() {
    local missing=()

    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v openssl >/dev/null 2>&1 || missing+=("openssl")
    command -v gh >/dev/null 2>&1 || missing+=("gh (GitHub CLI)")

    if [ ${#missing[@]} -gt 0 ]; then
        echo "ERROR: Missing required tools: ${missing[*]}"
        echo ""
        echo "Install with:"
        if [[ " ${missing[*]} " == *" gh "* ]] || [[ " ${missing[*]} " == *"gh (GitHub CLI)"* ]]; then
            echo "  brew install gh       # macOS"
            echo "  sudo apt install gh   # Debian/Ubuntu"
        fi
        if [[ " ${missing[*]} " == *" openssl "* ]]; then
            echo "  brew install openssl  # macOS"
            echo "  sudo apt install openssl  # Debian/Ubuntu"
        fi
        exit 1
    fi

    # Check gh auth
    if ! gh auth status >/dev/null 2>&1; then
        echo "ERROR: GitHub CLI not authenticated."
        echo "Run: gh auth login"
        exit 1
    fi

    echo "OK: All prerequisites satisfied."
}

keygen() {
    mkdir -p "${KEYS_DIR}"

    if [ -f "${KEYS_DIR}/private.pem" ]; then
        echo "WARNING: Keys already exist at ${KEYS_DIR}/"
        echo "Use --force to regenerate (old encrypted messages will become unreadable)."
        if [ "${1:-}" != "--force" ]; then
            exit 1
        fi
        echo "Regenerating keys..."
    fi

    # Generate RSA-2048 private key
    openssl genrsa -out "${KEYS_DIR}/private.pem" 2048 2>/dev/null

    # Extract public key
    openssl rsa -in "${KEYS_DIR}/private.pem" -pubout -out "${KEYS_DIR}/public.pem" 2>/dev/null

    # Restrict private key permissions
    chmod 600 "${KEYS_DIR}/private.pem"
    chmod 644 "${KEYS_DIR}/public.pem"

    echo "OK: RSA-2048 key pair generated."
    echo "  Private: ${KEYS_DIR}/private.pem (chmod 600)"
    echo "  Public:  ${KEYS_DIR}/public.pem"
}

clone_repo() {
    local repo_url="${1:-${DEFAULT_REPO}}"

    mkdir -p "${OCFR_DIR}"

    if [ -d "${REPO_DIR}/.git" ]; then
        echo "Repo already cloned at ${REPO_DIR}. Pulling latest..."
        cd "${REPO_DIR}"
        git pull --rebase origin main 2>/dev/null || git pull --rebase origin master 2>/dev/null || true
        echo "OK: Repo updated."
    else
        echo "Cloning ${repo_url}..."
        git clone "${repo_url}" "${REPO_DIR}"

        # Create directory structure if it doesn't exist
        cd "${REPO_DIR}"
        mkdir -p profiles matches messages

        # Install .gitignore to prevent accidental secret commits
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        local gitignore_template="${script_dir}/../templates/repo.gitignore"
        if [ -f "${gitignore_template}" ] && [ ! -f .gitignore ]; then
            cp "${gitignore_template}" .gitignore
        fi

        # Only commit if there are new directories to add
        if [ -n "$(git status --porcelain)" ]; then
            git add profiles/ matches/ messages/ .gitignore 2>/dev/null || true
            git commit -m "chore: initialize directory structure"
            git push origin HEAD 2>/dev/null || true
        fi

        echo "OK: Repo cloned to ${REPO_DIR}"
    fi
}

show_status() {
    echo "Claw Friends Status"
    echo "───────────────────────"

    if [ -f "${OCFR_DIR}/config.yaml" ]; then
        echo "Config:  OK (${OCFR_DIR}/config.yaml)"
    else
        echo "Config:  NOT FOUND"
    fi

    if [ -f "${KEYS_DIR}/private.pem" ]; then
        echo "Keys:    OK (${KEYS_DIR}/)"
    else
        echo "Keys:    NOT FOUND"
    fi

    if [ -d "${REPO_DIR}/.git" ]; then
        local profile_count
        profile_count=$(find "${REPO_DIR}/profiles" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
        echo "Repo:    OK (${profile_count} profiles)"
    else
        echo "Repo:    NOT CLONED"
    fi
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    check)
        check_prerequisites
        ;;
    keygen)
        keygen "${2:-}"
        ;;
    clone)
        clone_repo "${2:-}"
        ;;
    status)
        show_status
        ;;
    *)
        usage
        ;;
esac
