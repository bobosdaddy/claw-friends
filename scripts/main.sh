#!/usr/bin/env bash
# claw-friends: main.sh (UX Enhanced)
# Main entry point with context-aware help
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
        return 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

calculate_completeness() {
    local profile_file="$1"
    local score=0

    grep -q '^display_name:' "$profile_file" && score=$((score + 10))

    local bio
    bio=$(grep '^bio:' "$profile_file" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -n "$bio" ] && [ ${#bio} -ge 20 ]; then
        score=$((score + 15))
    elif [ -n "$bio" ]; then
        score=$((score + 5))
    fi

    local interests_count
    interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    interests_count=$((interests_count > 5 ? 5 : interests_count))
    score=$((score + interests_count * 5))

    local skills_count
    skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    skills_count=$((skills_count > 5 ? 5 : skills_count))
    score=$((score + skills_count * 5))

    grep -q '^looking_for:' "$profile_file" && score=$((score + 10))

    local ideal_count
    ideal_count=$(awk '/^ideal_type:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep -E '^\s+\w+:.*\S' | wc -l | tr -d ' ')
    ideal_count=$((ideal_count > 5 ? 5 : ideal_count))
    score=$((score + ideal_count * 3))

    echo "$score"
}

count_community_members() {
    if [ ! -d "${REPO_DIR}/profiles" ]; then
        echo "0"
        return
    fi
    find "${REPO_DIR}/profiles" -name "*.yaml" 2>/dev/null | \
        xargs grep -L 'is_seed: true' 2>/dev/null | wc -l | tr -d ' '
}

count_pending_requests() {
    local username="$1"
    local count=0
    if [ -d "${REPO_DIR}/matches/${username}" ]; then
        count=$(find "${REPO_DIR}/matches/${username}" -name "*.yaml" -exec grep -l 'status: pending' {} \; 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo "$count"
}

count_unread_messages() {
    local username="$1"
    local count=0
    if [ -d "${REPO_DIR}/messages/${username}" ]; then
        count=$(find "${REPO_DIR}/messages/${username}" -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    fi
    echo "$count"
}

count_active_negotiations() {
    local username="$1"
    local count=0
    if [ -d "${REPO_DIR}/negotiations" ]; then
        for dir in "${REPO_DIR}/negotiations"/*; do
            if [ -d "$dir" ] && [[ "$(basename "$dir")" == *"${username}"* ]]; then
                if [ ! -f "${dir}/result.yaml" ]; then
                    count=$((count + 1))
                fi
            fi
        done
    fi
    echo "$count"
}

# ─────────────────────────────────────────────────────────────
# Context-Aware Suggestions
# ─────────────────────────────────────────────────────────────

get_context_suggestions() {
    local username
    username=$(get_username) || {
        echo "not_initialized"
        return
    }

    local profile_file="${REPO_DIR}/profiles/${username}.yaml"
    local completeness
    completeness=$(calculate_completeness "$profile_file")

    local pending_requests
    pending_requests=$(count_pending_requests "$username")

    local active_negotiations
    active_negotiations=$(count_active_negotiations "$username")

    # Priority suggestions based on context
    local suggestions=()

    # Always show unread messages if any
    local unread
    unread=$(count_unread_messages "$username")
    if [ "$unread" -gt 0 ]; then
        suggestions+=("📬 你有 ${unread} 条未读消息 → /friends msg inbox")
    fi

    # Pending requests
    if [ "$pending_requests" -gt 0 ]; then
        suggestions+=("📨 你有 ${pending_requests} 条待处理的好友请求 → /friends requests")
    fi

    # Active negotiations
    if [ "$active_negotiations" -gt 0 ]; then
        suggestions+=("🤖 你有 ${active_negotiations} 个进行中的协商 → /friends auto status")
    fi

    # Profile completeness
    if [ "$completeness" -lt 30 ]; then
        suggestions+=("📝 资料完整度较低 (${completeness}%) → /friends profile enhance")
    elif [ "$completeness" -lt 70 ]; then
        suggestions+=("✏️  资料可以进一步完善 → /friends profile edit")
    fi

    # If profile is good, suggest matching
    if [ "$completeness" -ge 70 ] && [ "$pending_requests" -eq 0 ] && [ "$active_negotiations" -eq 0 ]; then
        suggestions+=("🎯 资料完整，开始匹配吧 → /friends match")
    fi

    # Default suggestion if nothing else
    if [ ${#suggestions[@]} -eq 0 ]; then
        suggestions+=("🌍 探索社区 → /friends explore")
    fi

    printf '%s\n' "${suggestions[@]}"
}

# ─────────────────────────────────────────────────────────────
# Main Menu Display
# ─────────────────────────────────────────────────────────────

show_main_menu() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🦞 Claw Friends v0.2${NC}                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    local username
    if ! username=$(get_username); then
        echo "未初始化。运行 /friends init 开始"
        echo ""
        return
    fi

    local profile_file="${REPO_DIR}/profiles/${username}.yaml"
    local completeness=0
    local community_count
    community_count=$(count_community_members)

    if [ -f "$profile_file" ]; then
        completeness=$(calculate_completeness "$profile_file")
    fi

    echo "你好，@${username}!"
    echo "资料完整度：${completeness}%"
    echo "社区成员：${community_count} 人"
    echo ""

    # Completeness status
    if [ "$completeness" -lt 30 ]; then
        echo -e "${YELLOW}⚠️  资料较空，匹配质量会受影响${NC}"
    elif [ "$completeness" -lt 70 ]; then
        echo -e "${BLUE}ℹ  资料尚可，但可以更完善${NC}"
    else
        echo -e "${GREEN}✓  资料完整度良好${NC}"
    fi
    echo ""

    # Context-aware suggestions
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}💡 建议你${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    local suggestions
    suggestions=$(get_context_suggestions)

    if [ "$suggestions" = "not_initialized" ]; then
        echo "  → /friends init  开始使用"
    else
        echo "$suggestions" | while IFS= read -r suggestion; do
            echo "  $suggestion"
        done
    fi
    echo ""

    # Command categories
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}📖 命令速查${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "┌────────────────────────────────────────────────────┐"
    echo "│ ${BOLD}基础命令${NC}"
    echo "│   /friends init              初始化"
    echo "│   /friends profile           查看/编辑资料"
    echo "│   /friends explore           浏览社区"
    echo "│   /friends help              帮助"
    echo "│"
    echo "│ ${BOLD}社交功能${NC}"
    echo "│   /friends match             智能推荐"
    echo "│   /friends request <user>    好友请求"
    echo "│   /friends msg <user>        发消息"
    echo "│"
    echo "│ ${BOLD}自动协商${NC}"
    echo "│   /friends auto <user>       开始协商"
    echo "│   /friends auto discover     自动发现"
    echo "│   /friends auto status       查看状态"
    echo "│   /friends report <user>     友谊报告"
    echo "└────────────────────────────────────────────────────┘"
    echo ""

    # Quick actions
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}⚡ 快捷操作${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  [1] profile edit      [2] profile enhance"
    echo "  [3] explore           [4] match"
    echo "  [5] auto discover     [6] requests"
    echo "  [7] sync              [8] doctor"
    echo "  [0] help"
    echo ""
    echo -n "选择或输入命令："
}

# ─────────────────────────────────────────────────────────────
# Command Aliases
# ─────────────────────────────────────────────────────────────

resolve_alias() {
    local cmd="$1"

    case "$cmd" in
        i|init|initialize)
            echo "init"
            ;;
        p|profile|me|my)
            echo "profile"
            ;;
        e|explore|browse|list)
            echo "explore"
            ;;
        m|match|recommend|find)
            echo "match"
            ;;
        r|request|req)
            echo "request"
            ;;
        msg|message|chat|send)
            echo "msg"
            ;;
        a|auto|negotiate)
            echo "auto"
            ;;
        s|sync|pull|push)
            echo "sync"
            ;;
        d|doctor|health)
            echo "doctor"
            ;;
        h|help|\?|*)
            echo "help"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Main Entry Point
# ─────────────────────────────────────────────────────────────

main() {
    local args=("$@")

    # No arguments - show main menu
    if [ ${#args[@]} -eq 0 ]; then
        show_main_menu
        return
    fi

    # Handle quick action numbers
    if [[ "${args[0]}" =~ ^[0-9]$ ]]; then
        case "${args[0]}" in
            1)
                bash "${SCRIPT_DIR}/profile.sh" edit
                return
                ;;
            2)
                bash "${SCRIPT_DIR}/enhance.sh"
                return
                ;;
            3)
                bash "${SCRIPT_DIR}/explore.sh"
                return
                ;;
            4)
                bash "${SCRIPT_DIR}/match.sh"
                return
                ;;
            5)
                bash "${SCRIPT_DIR}/auto.sh" discover
                return
                ;;
            6)
                bash "${SCRIPT_DIR}/request.sh" requests
                return
                ;;
            7)
                bash "${SCRIPT_DIR}/sync.sh"
                return
                ;;
            8)
                bash "${SCRIPT_DIR}/doctor.sh"
                return
                ;;
            0)
                info_help
                return
                ;;
        esac
    fi

    # Resolve aliases
    local cmd
    cmd=$(resolve_alias "${args[0]}")

    # Execute command
    case "$cmd" in
        init)
            bash "${SCRIPT_DIR}/init.sh"
            ;;
        profile)
            bash "${SCRIPT_DIR}/profile.sh" "${args[@]:1}"
            ;;
        explore)
            bash "${SCRIPT_DIR}/explore.sh"
            ;;
        match)
            bash "${SCRIPT_DIR}/match.sh" "${args[@]:1}"
            ;;
        request)
            bash "${SCRIPT_DIR}/request.sh" "${args[@]:1}"
            ;;
        msg)
            bash "${SCRIPT_DIR}/msg.sh" "${args[@]:1}"
            ;;
        auto)
            bash "${SCRIPT_DIR}/auto.sh" "${args[@]:1}"
            ;;
        report)
            bash "${SCRIPT_DIR}/report.sh" "${args[@]:1}"
            ;;
        sync)
            bash "${SCRIPT_DIR}/sync.sh"
            ;;
        doctor)
            bash "${SCRIPT_DIR}/doctor.sh"
            ;;
        help|*)
            info_help
            ;;
    esac
}

main "$@"
