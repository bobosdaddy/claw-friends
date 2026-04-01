#!/usr/bin/env bash
# claw-friends: match.sh (UX Enhanced)
# Smart matching with visual cards
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

# Calculate match score between two profiles
calculate_match_score() {
    local my_profile="$1"
    local their_profile="$2"

    # Get my interests and skills (lowercase)
    local my_interests my_skills
    my_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$my_profile" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)
    my_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$my_profile" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)

    # Get their interests and skills
    local their_interests their_skills
    their_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$their_profile" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)
    their_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$their_profile" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)

    # Interest overlap
    local common_count=0
    if [ -n "$my_interests" ] && [ -n "$their_interests" ]; then
        common_count=$(comm -12 <(echo "$my_interests") <(echo "$their_interests") | wc -l | tr -d ' ')
    fi

    # Skill complement (what they have that I don't)
    local complement_count=0
    if [ -n "$my_skills" ] && [ -n "$their_skills" ]; then
        complement_count=$(comm -13 <(echo "$my_skills") <(echo "$their_skills") | wc -l | tr -d ' ')
    fi

    # Get common interests list
    local common_list=""
    if [ "$common_count" -gt 0 ]; then
        common_list=$(comm -12 <(echo "$my_interests") <(echo "$their_interests") | head -3 | tr '\n' ',' | sed 's/,$//')
    fi

    # Simple scoring: interests * 10 + skill_complement * 5
    local score=$((common_count * 10 + complement_count * 5))
    # Cap at 100
    score=$((score > 100 ? 100 : score))

    echo "${score}|${common_list}|${complement_count}"
}

# Generate match reason
generate_match_reason() {
    local common_interests="$1"
    local skill_complement="$2"
    local their_name="$3"

    local reason=""

    if [ -n "$common_interests" ]; then
        reason="你们都热爱 ${common_interests}"
    fi

    if [ "$skill_complement" -gt 0 ]; then
        if [ -n "$reason" ]; then
            reason="${reason}，对方有 ${skill_complement} 项互补技能"
        else
            reason="对方有 ${skill_complement} 项你需要的技能"
        fi
    fi

    if [ -z "$reason" ]; then
        reason="探索新的可能性"
    fi

    echo "$reason"
}

# ─────────────────────────────────────────────────────────────
# Get Matches
# ─────────────────────────────────────────────────────────────

get_matches() {
    local top_n="${1:-5}"
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [[ ! -f "${profile}" ]]; then
        error_profile_empty
        exit 1
    fi

    local matches=()

    for p in "${REPO_DIR}/profiles"/*.yaml; do
        [[ ! -f "$p" ]] && continue

        local other_user
        other_user=$(basename "$p" .yaml)

        # Skip self, seed profiles, empty profiles
        [[ "$other_user" == "$username" ]] && continue
        grep -q 'is_seed: true' "$p" 2>/dev/null && continue
        [[ ! -s "$p" ]] && continue

        # Calculate score
        local result
        result=$(calculate_match_score "$profile" "$p")
        local score common_list complement_count
        score=$(echo "$result" | cut -d'|' -f1)
        common_list=$(echo "$result" | cut -d'|' -f2)
        complement_count=$(echo "$result" | cut -d'|' -f3)

        # Skip if no match
        [[ "$score" -le 0 ]] && continue

        # Get their display_name
        local their_name
        their_name=$(grep '^display_name:' "$p" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

        # Generate match reason
        local reason
        reason=$(generate_match_reason "$common_list" "$complement_count" "$their_name")

        matches+=("${score}|${other_user}|${their_name}|${common_list}|${complement_count}|${reason}")
    done

    # Sort and return top N
    if [ ${#matches[@]} -gt 0 ]; then
        printf '%s\n' "${matches[@]}" | sort -t'|' -k1 -rn | head -n "$top_n"
    fi
}

# ─────────────────────────────────────────────────────────────
# Display Matches
# ─────────────────────────────────────────────────────────────

display_matches() {
    local top_n="${1:-5}"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🎯 智能匹配推荐 — Top ${top_n}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    local matches
    matches=$(get_matches "$top_n")

    if [ -z "$matches" ]; then
        echo "未找到匹配的用户"
        echo ""
        echo "可能原因:"
        echo "  • 社区用户较少"
        echo "  • 你的兴趣/技能标签太少"
        echo ""
        echo "建议:"
        echo -e "  ${CYAN}/friends profile edit${NC} — 完善你的标签"
        echo -e "  ${CYAN}/friends profile enhance${NC} — 智能导入 GitHub"
        echo -e "  ${CYAN}/friends explore${NC} — 浏览社区"
        echo ""
        return 0
    fi

    local rank=0
    echo "$matches" | while IFS='|' read -r score user name common complement reason; do
        rank=$((rank + 1))
        render_match_card "$rank" "$user" "$name" "$score" "$common" "$complement" "$reason"
    done

    # Action prompt
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "操作:"
    echo "  [1-${top_n}] 选择用户发起对话"
    echo "  v 查看详细资料"
    echo "  r 发送好友请求"
    echo "  q 返回"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Interactive Match Selection
# ─────────────────────────────────────────────────────────────

interactive_select() {
    local top_n="${1:-5}"
    local matches
    matches=$(get_matches "$top_n")

    if [ -z "$matches" ]; then
        return
    fi

    echo -n "选择 [1-${top_n}/v/r/q]: "
    read -r choice

    case "$choice" in
        [1-9])
            if [ "$choice" -le "$top_n" ]; then
                local selected
                selected=$(echo "$matches" | sed -n "${choice}p")
                local user
                user=$(echo "$selected" | cut -d'|' -f2)
                local name
                name=$(echo "$selected" | cut -d'|' -f3)

                echo ""
                echo "想和 @${user} 聊聊吗？"
                echo ""
                echo "  [1] 发送好友请求"
                echo "  [2] 查看详细资料"
                echo "  [3] 返回"
                echo ""
                echo -n "选择："
                read -r action

                case "$action" in
                    1)
                        bash "${SCRIPT_DIR}/request.sh" "$user"
                        ;;
                    2)
                        bash "${SCRIPT_DIR}/profile.sh" view "$user"
                        ;;
                    *)
                        echo "已取消"
                        ;;
                esac
            fi
            ;;
        v|V)
            echo -n "查看谁的资料 (用户名): "
            read -r user
            bash "${SCRIPT_DIR}/profile.sh" view "$user"
            ;;
        r|R)
            echo -n "给谁发送好友请求 (用户名): "
            read -r user
            bash "${SCRIPT_DIR}/request.sh" "$user"
            ;;
        *)
            echo "返回主菜单"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local top_n=5

    # Parse arguments
    while [ $# -gt 0 ]; do
        case "$1" in
            --top|-n)
                top_n="$2"
                shift 2
                ;;
            *)
                shift
                ;;
        esac
    done

    # Check initialization
    if [ ! -f "${CONFIG_FILE}" ]; then
        error_not_initialized
        exit 1
    fi

    # Check profile completeness
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"
    local completeness
    completeness=$(calculate_completeness "$profile" 2>/dev/null || echo "0")

    if [ "$completeness" -lt 30 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  你的资料完整度较低 (${completeness}%)${NC}"
        echo "匹配质量可能会受影响。"
        echo ""
        echo "建议先完善资料:"
        echo -e "  ${CYAN}/friends profile enhance${NC} — 智能导入 GitHub"
        echo -e "  ${CYAN}/friends profile edit${NC} — 手动编辑"
        echo ""
        echo -n "要继续匹配吗？[Y/n]: "
        read -r confirm
        if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
            echo "好的，先去完善资料吧!"
            exit 0
        fi
    fi

    # Sync before matching
    echo ""
    echo -e "${BLUE}⟳${NC} 正在同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    # Display matches
    display_matches "$top_n"

    # Interactive selection
    interactive_select "$top_n"
}

main "$@"
