#!/usr/bin/env bash
# claw-friends: notify.sh
# Notification system for pending requests and negotiations
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo ""
        return
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# ─────────────────────────────────────────────────────────────
# Check Pending Friend Requests
# ─────────────────────────────────────────────────────────────

check_pending_requests() {
    local username
    username=$(get_username)

    if [ -z "$username" ]; then
        return
    fi

    local requests_dir="${REPO_DIR}/matches/${username}"
    local count=0
    local pending_list=()

    if [ -d "$requests_dir" ]; then
        for f in "$requests_dir"/*.yaml; do
            [ ! -f "$f" ] && continue
            local status
            status=$(grep '^status:' "$f" 2>/dev/null | awk '{print $2}' | tr -d '"')
            if [ "$status" = "pending" ]; then
                local from_user
                from_user=$(grep '^from:' "$f" | awk '{print $2}' | tr -d '"')
                pending_list+=("$from_user")
                count=$((count + 1))
            fi
        done
    fi

    if [ $count -gt 0 ]; then
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}📨 你有 ${count} 条待处理的好友请求${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        for user in "${pending_list[@]}"; do
            echo "  • @${user}"
        done
        echo ""
        echo "查看请求：/friends requests"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Check Negotiations Waiting for Response
# ─────────────────────────────────────────────────────────────

check_negotiations() {
    local username
    username=$(get_username)

    if [ -z "$username" ]; then
        return
    fi

    local negotiations_dir="${REPO_DIR}/negotiations"
    local count=0
    local waiting_list=()

    if [ ! -d "$negotiations_dir" ]; then
        return
    fi

    for dir in "$negotiations_dir"/*/; do
        [ ! -d "$dir" ] && continue

        local dir_name
        dir_name=$(basename "$dir")

        # Check if user is participant
        if [[ "$dir_name" != *"$username"* ]]; then
            continue
        fi

        # Skip completed negotiations
        [ -f "${dir}result.yaml" ] && continue

        # Find latest round
        local latest_round=0
        local latest_file=""
        for f in "$dir"/round_*.yaml; do
            [ ! -f "$f" ] && continue
            local round_num
            round_num=$(grep '^round:' "$f" | awk '{print $2}')
            if [[ "$round_num" -gt "$latest_round" ]]; then
                latest_round="$round_num"
                latest_file="$f"
            fi
        done

        # Check if it's user's turn
        if [ -n "$latest_file" ]; then
            local last_from
            last_from=$(grep '^from:' "$latest_file" | awk '{print $2}' | tr -d '"')

            # If last move was by user, skip (not waiting)
            if [ "$last_from" = "$username" ]; then
                continue
            fi

            # Get partner name
            local partner
            partner=$(echo "$dir_name" | sed "s/${username}__//" | sed "s/__${username}//")
            waiting_list+=("$partner")
            count=$((count + 1))
        fi
    done

    if [ $count -gt 0 ]; then
        echo ""
        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}🤖 有 ${count} 个协商等待你的响应${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        for partner in "${waiting_list[@]}"; do
            echo "  • @${partner}"
        done
        echo ""
        echo "查看协商：/friends auto status"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Check Unread Messages
# ─────────────────────────────────────────────────────────────

check_unread_messages() {
    local username
    username=$(get_username)

    if [ -z "$username" ]; then
        return
    fi

    local messages_dir="${REPO_DIR}/messages/${username}"
    local count=0

    if [ -d "$messages_dir" ]; then
        count=$(find "$messages_dir" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    fi

    if [ $count -gt 0 ]; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}  ${BOLD}📬 你有 ${count} 条未读消息${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "查看消息：/friends msg inbox"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Check All Notifications
# ─────────────────────────────────────────────────────────────

check_all() {
    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    local has_notifications=false

    # Check each type
    check_pending_requests && has_notifications=true
    check_negotiations && has_notifications=true
    check_unread_messages && has_notifications=true

    if [ "$has_notifications" = "false" ]; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${NC}  ${BOLD}✅ 没有待处理的事项${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Quick Status (one-liner for main menu)
# ─────────────────────────────────────────────────────────────

quick_status() {
    local username
    username=$(get_username)

    if [ -z "$username" ]; then
        return
    fi

    local notifications=()

    # Pending requests
    local requests_dir="${REPO_DIR}/matches/${username}"
    if [ -d "$requests_dir" ]; then
        local req_count
        req_count=$(find "$requests_dir" -name "*.yaml" -exec grep -l 'status: pending' {} \; 2>/dev/null | wc -l | tr -d ' ')
        if [ "$req_count" -gt 0 ]; then
            notifications+=("📨 ${req_count}条好友请求")
        fi
    fi

    # Unread messages
    local messages_dir="${REPO_DIR}/messages/${username}"
    if [ -d "$messages_dir" ]; then
        local msg_count
        msg_count=$(find "$messages_dir" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
        if [ "$msg_count" -gt 0 ]; then
            notifications+=("📬 ${msg_count}条消息")
        fi
    fi

    # Waiting negotiations
    local negotiations_dir="${REPO_DIR}/negotiations"
    if [ -d "$negotiations_dir" ]; then
        local neg_count=0
        for dir in "$negotiations_dir"/*/; do
            [ ! -d "$dir" ] && continue
            local dir_name
            dir_name=$(basename "$dir")
            [[ "$dir_name" != *"$username"* ]] && continue
            [ -f "${dir}result.yaml" ] && continue

            local latest_file
            latest_file=$(ls -t "$dir"/round_*.yaml 2>/dev/null | head -1)
            if [ -n "$latest_file" ]; then
                local last_from
                last_from=$(grep '^from:' "$latest_file" | awk '{print $2}' | tr -d '"')
                if [ "$last_from" != "$username" ]; then
                    neg_count=$((neg_count + 1))
                fi
            fi
        done
        if [ "$neg_count" -gt 0 ]; then
            notifications+=("🤖 ${neg_count}个协商")
        fi
    fi

    if [ ${#notifications[@]} -gt 0 ]; then
        echo "${notifications[*]}"
    else
        echo "无待处理事项"
    fi
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local action="${1:-check}"

    case "$action" in
        check|all|a)
            check_all
            ;;
        requests|r)
            check_pending_requests
            ;;
        negotiations|n)
            check_negotiations
            ;;
        messages|m)
            check_unread_messages
            ;;
        quick|q)
            quick_status
            ;;
        *)
            echo "用法：/friends notify [check|requests|negotiations|messages|quick]"
            ;;
    esac
}

main "$@"
