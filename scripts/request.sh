#!/usr/bin/env bash
# claw-friends: request.sh (UX Enhanced)
# Send and manage friend requests
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

# Source UI and messages
source "${SCRIPT_DIR}/ui.sh" 2>/dev/null || true
source "${SCRIPT_DIR}/messages.sh" 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        error_not_initialized
        exit 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# ─────────────────────────────────────────────────────────────
# Send Friend Request
# ─────────────────────────────────────────────────────────────

send_request() {
    local target="$1"

    if [ -z "$target" ]; then
        echo "用法：/friends request <用户名>"
        exit 1
    fi

    local username
    username=$(get_username)
    local target_profile="${REPO_DIR}/profiles/${target}.yaml"

    # Check target exists
    if [ ! -f "$target_profile" ]; then
        error_user_not_found "$target"
        exit 1
    fi

    # Check if seed profile
    if grep -q 'is_seed: true' "$target_profile"; then
        error_seed_profile "$target"
        exit 1
    fi

    # Check if requesting self
    if [ "$target" = "$username" ]; then
        echo "不能向自己发送好友请求!"
        exit 1
    fi

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    # Check for duplicate
    local my_matches_dir="${REPO_DIR}/matches/${target}"
    local existing_request="${my_matches_dir}/from_${username}.yaml"

    if [ -f "$existing_request" ]; then
        local status
        status=$(grep '^status:' "$existing_request" 2>/dev/null | awk '{print $2}' | tr -d '"')
        if [ "$status" = "pending" ]; then
            echo ""
            echo "你已经向 @${target} 发送了好友请求，正在等待对方接受"
            exit 0
        fi
    fi

    # Check for mutual request (auto-accept)
    local their_matches_dir="${REPO_DIR}/matches/${username}"
    local their_request="${their_matches_dir}/from_${target}.yaml"

    if [ -f "$their_request" ]; then
        local status
        status=$(grep '^status:' "$their_request" 2>/dev/null | awk '{print $2}' | tr -d '"')
        if [ "$status" = "pending" ]; then
            # Auto-accept both directions
            echo ""
            echo -e "${GREEN}🎉 对方已经向你发送了请求！你们现在是好友了!${NC}"
            echo ""

            # Update both requests to accepted
            local timestamp
            timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

            # Update their request
            sed -i.bak "s/^status: pending/status: accepted/" "$their_request"
            echo "responded_at: \"${timestamp}\"" >> "$their_request"
            rm -f "${their_request}.bak"

            # Create our response
            mkdir -p "$my_matches_dir"
            cat > "$existing_request" <<EOF
from: "${username}"
to: "${target}"
message: "互相喜欢!"
created_at: "${timestamp}"
responded_at: "${timestamp}"
status: accepted
EOF

            # Sync
            cd "${REPO_DIR}"
            git add "matches/" 2>/dev/null || true
            git commit -m "feat: mutual match between ${username} and ${target}" >/dev/null 2>&1 || true
            git push origin HEAD 2>/dev/null || true

            success_request_accepted "$target"
            exit 0
        fi
    fi

    # Ask for optional message
    echo ""
    echo "要附带一条消息吗？(可选，直接回车跳过)"
    echo -n "> "
    read -r message
    message="${message:-}"

    # Create request file
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    mkdir -p "$my_matches_dir"

    cat > "$existing_request" <<EOF
from: "${username}"
to: "${target}"
message: "${message}"
created_at: "${timestamp}"
status: pending
EOF

    # Sync
    echo ""
    echo -e "${BLUE}⟳${NC} 正在发送请求..."
    cd "${REPO_DIR}"
    git add "matches/" 2>/dev/null || true
    git commit -m "feat: friend request from ${username} to ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    # Get target display name
    local target_display
    target_display=$(grep '^display_name:' "$target_profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

    render_friend_request_sent "$target" "$target_display"
}

# ─────────────────────────────────────────────────────────────
# View Requests
# ─────────────────────────────────────────────────────────────

view_requests() {
    local username
    username=$(get_username)
    local matches_dir="${REPO_DIR}/matches/${username}"

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}📨 好友请求${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$matches_dir" ] || [ -z "$(ls -A "$matches_dir" 2>/dev/null)" ]; then
        echo "暂无好友请求"
        echo ""
        echo "去发现新朋友吧:"
        echo -e "  ${CYAN}/friends explore${NC} — 浏览社区"
        echo -e "  ${CYAN}/friends match${NC}   — 智能推荐"
        echo ""
        return
    fi

    local pending=()
    local accepted=()
    local declined=()

    for f in "$matches_dir"/*.yaml; do
        [ ! -f "$f" ] && continue
        local status
        status=$(grep '^status:' "$f" 2>/dev/null | awk '{print $2}' | tr -d '"')
        case "$status" in
            pending) pending+=("$f") ;;
            accepted) accepted+=("$f") ;;
            declined) declined+=("$f") ;;
        esac
    done

    # Show pending
    if [ ${#pending[@]} -gt 0 ]; then
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  ⏳ 待处理 (${#pending[@})"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""

        for f in "${pending[@]}"; do
            local from_user status message created_at
            from_user=$(basename "$f" .yaml | sed 's/^from_//')
            status=$(grep '^status:' "$f" | awk '{print $2}' | tr -d '"')
            message=$(grep '^message:' "$f" | sed 's/^message: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
            created_at=$(grep '^created_at:' "$f" | awk '{print $2}' | tr -d '"')

            # Get display name
            local profile="${REPO_DIR}/profiles/${from_user}.yaml"
            local display_name="$from_user"
            if [ -f "$profile" ]; then
                display_name=$(grep '^display_name:' "$profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
            fi

            echo "  @${from_user} (${display_name})"
            if [ -n "$message" ]; then
                echo "  留言：\"${message}\""
            fi
            echo "  时间：${created_at}"
            echo ""
        done

        echo "操作:"
        echo "  accept <用户名>  — 接受"
        echo "  decline <用户名> — 拒绝"
        echo ""
    fi

    # Show accepted
    if [ ${#accepted[@]} -gt 0 ]; then
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  ✓ 已接受 (${#accepted[@})"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        for f in "${accepted[@]}"; do
            local from_user
            from_user=$(basename "$f" .yaml | sed 's/^from_//')
            echo "  @${from_user}"
        done
        echo ""
    fi

    # Show declined
    if [ ${#declined[@]} -gt 0 ]; then
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  ✗ 已拒绝 (${#declined[@})"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
        for f in "${declined[@]}"; do
            local from_user
            from_user=$(basename "$f" .yaml | sed 's/^from_//')
            echo "  @${from_user}"
        done
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Accept/Decline Request
# ─────────────────────────────────────────────────────────────

accept_request() {
    local target="$1"
    local username
    username=$(get_username)
    local request_file="${REPO_DIR}/matches/${username}/from_${target}.yaml"

    if [ ! -f "$request_file" ]; then
        echo "未找到来自 @${target} 的好友请求"
        exit 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update request status
    sed -i.bak "s/^status: pending/status: accepted/" "$request_file"
    echo "responded_at: \"${timestamp}\"" >> "$request_file"
    rm -f "${request_file}.bak"

    # Create reciprocal request
    local my_response_file="${REPO_DIR}/matches/${target}/from_${username}.yaml"
    mkdir -p "$(dirname "$my_response_file")"
    cat > "$my_response_file" <<EOF
from: "${username}"
to: "${target}"
message: "互相喜欢!"
created_at: "${timestamp}"
responded_at: "${timestamp}"
status: accepted
EOF

    # Sync
    cd "${REPO_DIR}"
    git add "matches/" 2>/dev/null || true
    git commit -m "feat: accept friend request from ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    success_request_accepted "$target"
}

decline_request() {
    local target="$1"
    local username
    username=$(get_username)
    local request_file="${REPO_DIR}/matches/${username}/from_${target}.yaml"

    if [ ! -f "$request_file" ]; then
        echo "未找到来自 @${target} 的好友请求"
        exit 1
    fi

    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Update status
    sed -i.bak "s/^status: pending/status: declined/" "$request_file"
    echo "responded_at: \"${timestamp}\"" >> "$request_file"
    rm -f "${request_file}.bak"

    # Sync
    cd "${REPO_DIR}"
    git add "matches/" 2>/dev/null || true
    git commit -m "feat: decline request from ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    echo ""
    echo "已拒绝 @${target} 的好友请求"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Cancel Request
# ─────────────────────────────────────────────────────────────

cancel_request() {
    local target="$1"
    local username
    username=$(get_username)
    local request_file="${REPO_DIR}/matches/${target}/from_${username}.yaml"

    if [ ! -f "$request_file" ]; then
        echo "未找到向 @${target} 发送的好友请求"
        exit 1
    fi

    rm -f "$request_file"

    # Sync
    cd "${REPO_DIR}"
    git add "matches/" 2>/dev/null || true
    git commit -m "chore: cancel request to ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    echo ""
    echo "已撤回向 @${target} 发送的好友请求"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local action="${1:-}"
    local target="${2:-}"

    if [ -z "$action" ]; then
        view_requests
        return
    fi

    case "$action" in
        view|list|ls|requests|"")
            view_requests
            ;;
        send|s)
            send_request "$target"
            ;;
        accept|a)
            accept_request "$target"
            ;;
        decline|d|reject)
            decline_request "$target"
            ;;
        cancel|c)
            cancel_request "$target"
            ;;
        *)
            # If no action specified, treat first arg as target for send
            if [ -n "$action" ]; then
                send_request "$action"
            else
                view_requests
            fi
            ;;
    esac
}

main "$@"
