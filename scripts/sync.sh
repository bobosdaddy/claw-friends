#!/usr/bin/env bash
# claw-friends: sync.sh (UX Enhanced)
# Handles git sync operations with friendly feedback
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
MAX_RETRIES=3

# Source messages
source "${SCRIPT_DIR}/messages.sh" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "unknown"
        return
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

ensure_repo() {
    if [ ! -d "${REPO_DIR}/.git" ]; then
        echo ""
        error_not_initialized
        exit 1
    fi
}

# ─────────────────────────────────────────────────────────────
# Pull
# ─────────────────────────────────────────────────────────────

do_pull() {
    ensure_repo
    cd "${REPO_DIR}"

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

    echo -e "${BLUE}⟳${NC} 正在拉取最新数据..."

    local pull_err
    if pull_err=$(git pull --rebase origin "${branch}" 2>&1); then
        echo -e "  ${GREEN}✓${NC} 拉取完成"
        return 0
    else
        echo -e "  ${YELLOW}⚠️${NC} 重新拉取失败，尝试普通合并..."
        git rebase --abort 2>/dev/null || true

        if pull_err=$(git pull origin "${branch}" 2>&1); then
            echo -e "  ${GREEN}✓${NC} 拉取完成 (合并模式)"
            return 0
        else
            echo -e "  ${RED}✗${NC} 拉取失败"
            echo "  详情：${pull_err}"
            return 1
        fi
    fi
}

# ─────────────────────────────────────────────────────────────
# Push
# ─────────────────────────────────────────────────────────────

do_push() {
    ensure_repo
    cd "${REPO_DIR}"

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

    # Stage known directories
    git add profiles/ matches/ messages/ negotiations/ connects/ .gitignore 2>/dev/null || true

    # Check if there are changes
    if git diff --cached --quiet; then
        echo -e "  ${BLUE}ℹ${NC} 无本地更改"
        return 0
    fi

    # Get username for commit message
    local username
    username=$(get_username)
    local timestamp
    timestamp=$(date -u +%Y%m%dT%H%M%SZ)

    git commit -m "sync: ${username} ${timestamp}"

    # Push with retry
    local attempt=0
    while [ $attempt -lt $MAX_RETRIES ]; do
        local push_err
        if push_err=$(git push origin "${branch}" 2>&1); then
            echo -e "  ${GREEN}✓${NC} 推送完成"
            return 0
        fi

        attempt=$((attempt + 1))
        echo -e "  ${YELLOW}⚠️${NC} 推送失败 (尝试 ${attempt}/${MAX_RETRIES})"

        if [ $attempt -lt $MAX_RETRIES ]; then
            echo -e "${BLUE}⟳${NC} 拉取并重试..."
            git pull --rebase origin "${branch}" 2>/dev/null || {
                git rebase --abort 2>/dev/null || true
                git pull origin "${branch}" 2>/dev/null || true
            }
        fi
    done

    echo -e "  ${RED}✗${NC} 推送失败，已尝试 ${MAX_RETRIES} 次"
    echo "  请手动运行 /friends sync"
    return 1
}

# ─────────────────────────────────────────────────────────────
# Status
# ─────────────────────────────────────────────────────────────

do_status() {
    ensure_repo
    cd "${REPO_DIR}"

    local username
    username=$(get_username)

    # Count changes
    local new_profiles=0
    local new_messages=0
    local new_requests=0

    if [ -d "profiles" ]; then
        new_profiles=$(find "profiles" -name "*.yaml" -newer "${OCFR_DIR}/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ -d "messages/${username}" ]; then
        new_messages=$(find "messages/${username}" -name "*.yaml" -newer "${OCFR_DIR}/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ -d "matches/${username}" ]; then
        new_requests=$(find "matches/${username}" -name "*.yaml" -newer "${OCFR_DIR}/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Update last sync time
    touch "${OCFR_DIR}/.last_sync"

    # Display status
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}📊 同步状态${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "本次同步以来:"
    echo "  • ${new_profiles} 个新/更新资料"
    echo "  • ${new_messages} 条新消息"
    echo "  • ${new_requests} 个新好友请求"
    echo ""

    # Git status
    echo "Git 状态:"
    local git_status
    git_status=$(git status --short 2>/dev/null || echo "无法获取状态")

    if [ -z "$git_status" ]; then
        echo -e "  ${GREEN}✓${NC} 工作区干净"
    else
        echo "  ${YELLOW}⚠️${NC} 有待提交的更改:"
        echo "$git_status" | head -10 | while IFS= read -r line; do
            echo "    $line"
        done
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Full Sync
# ─────────────────────────────────────────────────────────────

do_sync() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🔄 数据同步${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Pull first
    do_pull || {
        echo ""
        error_sync_failed "拉取失败"
        exit 1
    }

    # Then push
    do_push

    # Show status
    do_status

    # Success message
    local username
    username=$(get_username)
    local messages_dir="${REPO_DIR}/messages/${username}"
    local matches_dir="${REPO_DIR}/matches/${username}"

    local msg_count=0
    local req_count=0

    if [ -d "$messages_dir" ]; then
        msg_count=$(find "$messages_dir" -name "*.yaml" -newer "${OCFR_DIR}/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ -d "$matches_dir" ]; then
        req_count=$(find "$matches_dir" -name "*.yaml" -newer "${OCFR_DIR}/.last_sync" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Update last sync
    touch "${OCFR_DIR}/.last_sync"

    success_sync_complete "0" "$msg_count" "$req_count"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local action="${1:-full}"

    # Check initialization
    if [ ! -f "${CONFIG_FILE}" ]; then
        error_not_initialized
        exit 1
    fi

    case "$action" in
        pull)
            do_pull
            ;;
        push)
            do_push
            ;;
        status)
            do_status
            ;;
        sync|full|*)
            do_sync
            ;;
    esac
}

main "$@"
