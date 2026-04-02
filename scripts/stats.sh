#!/usr/bin/env bash
# claw-friends: stats.sh
# Personal statistics and dashboard
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

# Source UI
source "${SCRIPT_DIR}/ui.sh" 2>/dev/null || true

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
# Statistics Collection
# ─────────────────────────────────────────────────────────────

get_profile_stats() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "$profile" ]; then
        echo "0|0|0|0|0|0"
        return
    fi

    local interests skills looking_for ideal completeness
    interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    looking_for=$(awk '/^looking_for:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    ideal=$(awk '/^ideal_type:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep -E '^\s+\w+:.*\S' | wc -l | tr -d ' ')
    completeness=$(calculate_completeness "$profile" 2>/dev/null || echo "0")

    # Get updated_at
    local updated_at
    updated_at=$(grep '^updated_at:' "$profile" | sed 's/^updated_at: *"\([^"]*\)"/\1/' | head -1)

    echo "${interests}|${skills}|${looking_for}|${ideal}|${completeness}|${updated_at}"
}

get_social_stats() {
    local username
    username=$(get_username)

    # Sent requests
    local sent_dir="${REPO_DIR}/matches/${username}"
    local sent_count=0
    local accepted_count=0
    local pending_count=0

    if [ -d "$sent_dir" ]; then
        for f in "$sent_dir"/*.yaml; do
            [ ! -f "$f" ] && continue
            sent_count=$((sent_count + 1))
            local status
            status=$(grep '^status:' "$f" 2>/dev/null | awk '{print $2}' | tr -d '"')
            case "$status" in
                accepted) accepted_count=$((accepted_count + 1)) ;;
                pending) pending_count=$((pending_count + 1)) ;;
            esac
        done
    fi

    # Received requests
    local received_dir="${REPO_DIR}/matches"
    local received_count=0
    if [ -d "$received_dir" ]; then
        for dir in "$received_dir"/*; do
            [ ! -d "$dir" ] && continue
            local from_file
            from_file=$(find "$dir" -name "from_${username}_*.yaml" 2>/dev/null | head -1)
            if [ -n "$from_file" ] && [ -f "$from_file" ]; then
                received_count=$((received_count + 1))
            fi
        done
    fi

    # Negotiations
    local negotiations_dir="${REPO_DIR}/negotiations"
    local total_negotiations=0
    local active_negotiations=0
    local matched_count=0
    local rejected_count=0

    if [ -d "$negotiations_dir" ]; then
        for dir in "$negotiations_dir"/*/; do
            [ ! -d "$dir" ] && continue
            local dir_name
            dir_name=$(basename "$dir")
            [[ "$dir_name" != *"$username"* ]] && continue

            total_negotiations=$((total_negotiations + 1))

            if [ -f "${dir}result.yaml" ]; then
                local status
                status=$(grep '^status:' "${dir}result.yaml" | awk '{print $2}' | tr -d '"')
                case "$status" in
                    matched) matched_count=$((matched_count + 1)) ;;
                    rejected|expired|cancelled) rejected_count=$((rejected_count + 1)) ;;
                esac
            else
                active_negotiations=$((active_negotiations + 1))
            fi
        done
    fi

    # Messages
    local messages_dir="${REPO_DIR}/messages/${username}"
    local total_messages=0
    local sent_messages=0

    if [ -d "$messages_dir" ]; then
        total_messages=$(find "$messages_dir" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    fi

    # Count sent messages
    local sent_cache="${OCFR_DIR}/sent"
    if [ -d "$sent_cache" ]; then
        sent_messages=$(find "$sent_cache" -name "*.txt" 2>/dev/null | wc -l | tr -d ' ')
    fi

    echo "${sent_count}|${accepted_count}|${pending_count}|${received_count}|${total_negotiations}|${active_negotiations}|${matched_count}|${rejected_count}|${total_messages}|${sent_messages}"
}

# ─────────────────────────────────────────────────────────────
# Display Dashboard
# ─────────────────────────────────────────────────────────────

show_dashboard() {
    local username
    username=$(get_username)

    if [ -z "$username" ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}❌ 未初始化${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "运行 /friends init 开始使用"
        echo ""
        return
    fi

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}📊 个人仪表盘 — @${username}${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Profile stats
    local profile_stats
    profile_stats=$(get_profile_stats)
    local interests skills looking_for ideal completeness updated_at
    interests=$(echo "$profile_stats" | cut -d'|' -f1)
    skills=$(echo "$profile_stats" | cut -d'|' -f2)
    looking_for=$(echo "$profile_stats" | cut -d'|' -f3)
    ideal=$(echo "$profile_stats" | cut -d'|' -f4)
    completeness=$(echo "$profile_stats" | cut -d'|' -f5)
    updated_at=$(echo "$profile_stats" | cut -d'|' -f6)

    # Completeness indicator
    local completeness_icon
    if [ "$completeness" -lt 30 ]; then
        completeness_icon="⚠️ "
    elif [ "$completeness" -lt 70 ]; then
        completeness_icon="📝"
    else
        completeness_icon="✓"
    fi

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  📋 资料状态                                           │"
    echo "│  ───────────────────────────────────────────────────────  │"
    printf "│  完整度：${completeness_icon} %-3d%%                                          │\n" "$completeness"
    printf "│  兴趣标签：${BLUE}%-4d${NC}个                                          │\n" "$interests"
    printf "│  技能标签：${GREEN}%-4d${NC}个                                          │\n" "$skills"
    printf "│  寻找项：%-5d个                                          │\n" "$looking_for"
    printf "│  理想类型：%-4d项                                          │\n" "$ideal"
    printf "│  更新于：%-44s│\n" "${updated_at:-未知}"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Social stats
    local social_stats
    social_stats=$(get_social_stats)
    local sent accepted pending received total_neg active_neg matched rejected total_msg sent_msg
    sent=$(echo "$social_stats" | cut -d'|' -f1)
    accepted=$(echo "$social_stats" | cut -d'|' -f2)
    pending=$(echo "$social_stats" | cut -d'|' -f3)
    received=$(echo "$social_stats" | cut -d'|' -f4)
    total_neg=$(echo "$social_stats" | cut -d'|' -f5)
    active_neg=$(echo "$social_stats" | cut -d'|' -f6)
    matched=$(echo "$social_stats" | cut -d'|' -f7)
    rejected=$(echo "$social_stats" | cut -d'|' -f8)
    total_msg=$(echo "$social_stats" | cut -d'|' -f9)
    sent_msg=$(echo "$social_stats" | cut -d'|' -f10)

    # Success rate calculation
    local success_rate=0
    if [ "$((accepted + pending))" -gt 0 ]; then
        success_rate=$((accepted * 100 / (accepted + pending)))
    fi

    local negotiation_success_rate=0
    if [ "$total_neg" -gt 0 ]; then
        negotiation_success_rate=$((matched * 100 / total_neg))
    fi

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  🤝 社交活动                                           │"
    echo "│  ───────────────────────────────────────────────────────  │"
    printf "│  已发送请求：${BLUE}%-5d${NC} (接受率：${GREEN}%3d%%${NC})                    │\n" "$sent" "$success_rate"
    printf "│  已接受：${GREEN}%-5d${NC}                                            │\n" "$accepted"
    printf "│  待处理：${YELLOW}%-5d${NC}                                            │\n" "$pending"
    printf "│  已收到：%-6d                                            │\n" "$received"
    echo "│                                                         │"
    printf "│  协商总数：%-6d (成功率：${GREEN}%3d%%${NC})                    │\n" "$total_neg" "$negotiation_success_rate"
    printf "│  进行中：${CYAN}%-5d${NC}                                            │\n" "$active_neg"
    printf "│  已成功：${GREEN}%-5d${NC}                                            │\n" "$matched"
    printf "│  已结束：%-6d                                            │\n" "$rejected"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  💬 消息活动                                           │"
    echo "│  ───────────────────────────────────────────────────────  │"
    printf "│  总消息数：%-46d│\n" "$total_msg"
    printf "│  已发送：%-47d│\n" "$sent_msg"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Quick actions
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "快捷操作:"
    echo "  [1] 查看/编辑资料    → /friends profile"
    echo "  [2] 查看好友请求     → /friends requests"
    echo "  [3] 查看协商状态     → /friends auto status"
    echo "  [4] 查看消息         → /friends msg inbox"
    echo "  [5] 开始匹配         → /friends match"
    echo "  [q] 返回"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Handle user input
    echo -n "选择 [1-5/q]: "
    read -r choice

    case "$choice" in
        1)
            bash "${SCRIPT_DIR}/profile.sh" view
            ;;
        2)
            bash "${SCRIPT_DIR}/request.sh" requests
            ;;
        3)
            bash "${SCRIPT_DIR}/auto.sh" status
            ;;
        4)
            bash "${SCRIPT_DIR}/msg.sh" inbox
            ;;
        5)
            bash "${SCRIPT_DIR}/match.sh"
            ;;
        *)
            echo "返回"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    show_dashboard
}

main "$@"
