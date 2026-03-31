#!/usr/bin/env bash
# claw-friends: sync.sh
# Handles git sync operations (pull/push) for the social repo
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
MAX_RETRIES=3

usage() {
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  pull     Pull latest changes from remote"
    echo "  push     Stage, commit, and push local changes"
    echo "  status   Show sync status (new profiles, messages, requests)"
    exit 1
}

ensure_repo() {
    if [ ! -d "${REPO_DIR}/.git" ]; then
        echo "ERROR: Repo not cloned. Run /friends init first."
        exit 1
    fi
}

get_username() {
    if [ ! -f "${OCFR_DIR}/config.yaml" ]; then
        echo "ERROR: Not initialized. Run /friends init first."
        exit 1
    fi
    # Simple YAML parsing for username field
    grep '^username:' "${OCFR_DIR}/config.yaml" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

do_pull() {
    ensure_repo
    cd "${REPO_DIR}"

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

    echo "Pulling latest from origin/${branch}..."
    local pull_err
    if pull_err=$(git pull --rebase origin "${branch}" 2>&1); then
        echo "OK: Pull complete."
    else
        echo "WARNING: Pull with rebase failed. Trying merge..." >&2
        echo "  Detail: ${pull_err}" >&2
        git rebase --abort 2>/dev/null || true
        if ! pull_err=$(git pull origin "${branch}" 2>&1); then
            echo "ERROR: Pull failed." >&2
            echo "  Detail: ${pull_err}" >&2
            exit 1
        fi
        echo "OK: Pull complete (merged)."
    fi
}

do_push() {
    ensure_repo
    cd "${REPO_DIR}"

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

    # Stage only known data directories (avoid accidental secret leakage)
    git add profiles/ matches/ messages/ negotiations/ .gitignore 2>/dev/null || true

    # Check if there are changes to commit
    if git diff --cached --quiet; then
        echo "OK: Nothing to push (no local changes)."
        return 0
    fi

    # Get username for commit message
    local username
    username=$(get_username 2>/dev/null || echo "unknown")
    local timestamp
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)

    git commit -m "sync: ${username} ${timestamp}"

    # Push with retry on conflict
    local attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        local push_err
        if push_err=$(git push origin "${branch}" 2>&1); then
            echo "OK: Push complete."
            return 0
        fi

        attempt=$((attempt + 1))
        echo "Push failed (attempt ${attempt}/${MAX_RETRIES}): ${push_err}" >&2
        echo "Pulling and retrying..." >&2
        git pull --rebase origin "${branch}" 2>/dev/null || {
            git rebase --abort 2>/dev/null || true
            git pull origin "${branch}" 2>/dev/null || true
        }
    done

    echo "ERROR: Push failed after ${MAX_RETRIES} retries."
    echo "Try running /friends sync manually."
    exit 1
}

do_status() {
    ensure_repo
    cd "${REPO_DIR}"

    local username
    username=$(get_username)

    # Count profiles
    local profile_count=0
    if [ -d "profiles" ]; then
        profile_count=$(find profiles -name "*.yaml" | wc -l | tr -d ' ')
    fi

    # Count pending requests for me
    local request_count=0
    if [ -d "matches/${username}" ]; then
        request_count=$(grep -rl 'status: "pending"\|status: pending' "matches/${username}/" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Count messages for me
    local message_count=0
    if [ -d "messages/${username}" ]; then
        message_count=$(find "messages/${username}" -name "*.yaml" | wc -l | tr -d ' ')
    fi

    echo "PROFILES:${profile_count}"
    echo "REQUESTS:${request_count}"
    echo "MESSAGES:${message_count}"
}

# --- Main ---

if [ $# -lt 1 ]; then
    usage
fi

case "$1" in
    pull)
        do_pull
        ;;
    push)
        do_push
        ;;
    status)
        do_status
        ;;
    *)
        usage
        ;;
esac
