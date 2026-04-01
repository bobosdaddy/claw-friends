#!/usr/bin/env bash
# claw-friends: explore.sh (UX Enhanced)
# Browse community members with visual cards
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

# ─────────────────────────────────────────────────────────────
# List Community Members
# ─────────────────────────────────────────────────────────────

list_members() {
    local filter_interest="${1:-}"
    local filter_skill="${2:-}"
    local page="${3:-1}"
    local per_page=10

    local username
    username=$(get_username)

    # Collect all non-seed profiles
    local profiles=()
    for p in "${REPO_DIR}/profiles"/*.yaml; do
        [[ ! -f "$p" ]] && continue

        local other_user
        other_user=$(basename "$p" .yaml)

        # Skip self and seed profiles
        [[ "$other_user" == "$username" ]] && continue
        grep -q 'is_seed: true' "$p" 2>/dev/null && continue
        [[ ! -s "$p" ]] && continue

        # Apply filters
        if [ -n "$filter_interest" ]; then
            if ! grep -qi "$filter_interest" "$p"; then
                continue
            fi
        fi

        if [ -n "$filter_skill" ]; then
            if ! grep -qi "$filter_skill" "$p"; then
                continue
            fi
        fi

        profiles+=("$p")
    done

    local total=${#profiles[@]}

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🌍 社区成员${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ "$total" -eq 0 ]; then
        echo "社区还没有成员"
        echo ""
        echo "成为第一个创建资料的人吧!"
        echo ""
        return
    fi

    # Calculate pagination
    local start=$(( (page - 1) * per_page ))
    local end=$((start + per_page))
    local total_pages=$(( (total + per_page - 1) / per_page ))

    echo "共 ${total} 位成员 (第 ${page}/${total_pages} 页)"
    echo ""

    # Display profiles
    local index=$start
    for p in "${profiles[@]}"; do
        if [ $index -ge $end ]; then
            break
        fi
        index=$((index + 1))

        if [ $index -le $start ]; then
            continue
        fi

        # Parse profile
        local display_name user bio skills interests updated_at completeness
        display_name=$(grep '^display_name:' "$p" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
        user=$(basename "$p" .yaml)
        bio=$(grep '^bio:' "$p" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
        skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$p" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3 | tr '\n' ' ')
        interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$p" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3 | tr '\n' ' ')
        updated_at=$(grep '^updated_at:' "$p" | sed 's/^updated_at: *"\([^"]*\)"/\1/' | head -1)

        # Truncate bio
        if [ ${#bio} -gt 40 ]; then
            bio="${bio:0:37}..."
        fi

        # Format skills
        local skills_display
        skills_display=$(echo "$skills" | sed 's/ / · /g')

        echo "┌─────────────────────────────────────────────────────────┐"
        printf "│ %2d. ${BOLD}%-35s${NC} @%-15s │\n" "$index" "${display_name:0:35}" "$user"
        echo "│                                                         │"

        if [ -n "$bio" ]; then
            printf "│    %-50s│\n" "\"${bio}\""
        else
            printf "│    %-50s│\n" "${DIM}暂无简介${NC}"
        fi

        if [ -n "$interests" ]; then
            printf "│    ${CYAN}🏷${NC} %-46s│\n" "#${interests// /  #}"
        fi

        if [ -n "$skills" ]; then
            printf "│    ${BLUE}🛠${NC} %-46s│\n" "$skills_display"
        fi

        echo "│                                                         │"
        printf "│    🕐 %-47s│\n" "更新于 ${updated_at:-未知}"
        echo "│                                                         │"
        echo "│    [v] 查看  [r] 好友请求  [m] 消息 (如已是好友)        │"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
    done

    # Pagination controls
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -n "页码："

    if [ $page -gt 1 ]; then
        echo -n "[<上一页] "
    fi

    for ((i=1; i<=total_pages && i<=10; i++)); do
        if [ $i -eq $page ]; then
            echo -n "${BOLD}${i}${NC} "
        else
            echo -n "${i} "
        fi
    done

    if [ $page -lt $total_pages ]; then
        echo -n "[下一页>]"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "操作:"
    echo "  [v] <用户名> 查看详细资料"
    echo "  [r] <用户名> 发送好友请求"
    echo "  [f] 按兴趣筛选 (如：rust)"
    echo "  [s] 按技能筛选 (如：python)"
    echo "  [c] 清除筛选"
    echo "  [q] 返回"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local filter_interest=""
    local filter_skill=""
    local page=1

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    # Show list
    list_members "$filter_interest" "$filter_skill" "$page"
}

main "$@"
