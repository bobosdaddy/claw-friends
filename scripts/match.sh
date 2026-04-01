#!/usr/bin/env bash
# claw-friends: match.sh
# Smart matching algorithm: compute compatibility scores between users
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "ERROR: Not initialized" >&2
        exit 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# Get Top N matches with scores
# Output format: score|user|display_name|common_interests|skill_complement_count
get_matches() {
    local top_n="${1:-5}"
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [[ ! -f "${profile}" ]]; then
        echo "ERROR: Profile not found" >&2
        exit 1
    fi

    # Get my interests and skills (lowercase for comparison)
    local my_interests my_skills
    my_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)
    my_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)

    local matches=()

    for p in "${REPO_DIR}/profiles"/*.yaml; do
        [[ ! -f "$p" ]] && continue

        local other_file other_user
        other_file=$(basename "$p")
        other_user="${other_file%.yaml}"

        # Skip self, seed profiles, empty profiles
        [[ "$other_user" == "$username" ]] && continue
        grep -q 'is_seed: true' "$p" 2>/dev/null && continue
        [[ ! -s "$p" ]] && continue

        # Get their interests and skills
        local their_interests their_skills
        their_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$p" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)
        their_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$p" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '[:upper:]' '[:lower:]' | sort -u)

        # Interest overlap (Jaccard-like)
        local common_interests_count=0
        if [[ -n "$my_interests" && -n "$their_interests" ]]; then
            common_interests_count=$(comm -12 <(echo "$my_interests") <(echo "$their_interests") | wc -l | tr -d ' ')
        fi

        # Skill complement (what they have that I don't)
        local skill_complement_count=0
        if [[ -n "$my_skills" && -n "$their_skills" ]]; then
            skill_complement_count=$(comm -13 <(echo "$my_skills") <(echo "$their_skills") | wc -l | tr -d ' ')
        fi

        # Get common interests list for display
        local common_list=""
        if [[ $common_interests_count -gt 0 ]]; then
            common_list=$(comm -12 <(echo "$my_interests") <(echo "$their_interests") | head -3 | tr '\n' ',' | sed 's/,$//')
        fi

        # Get their display_name
        local their_name
        their_name=$(grep '^display_name:' "$p" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

        # Simple scoring: interests * 10 + skill_complement * 5
        local score=$((common_interests_count * 10 + skill_complement_count * 5))

        # Only include if score > 0
        if [[ $score -gt 0 ]]; then
            matches+=("${score}|${other_user}|${their_name}|${common_list}|${common_interests_count}|${skill_complement_count}")
        fi
    done

    # Sort by score descending, take top N
    if [[ ${#matches[@]} -gt 0 ]]; then
        printf '%s\n' "${matches[@]}" | sort -t'|' -k1 -rn | head -n "$top_n"
    fi
}

# Display matches in formatted card
display_matches() {
    local top_n="${1:-5}"
    local matches
    matches=$(get_matches "$top_n")

    if [[ -z "$matches" ]]; then
        echo ""
        echo "未找到匹配的用户"
        echo ""
        echo "可能原因:"
        echo "  1. 社区用户较少"
        echo "  2. 你的兴趣/技能标签太少"
        echo ""
        echo "建议:"
        echo "  • /friends profile edit — 完善你的标签"
        echo "  • /friends explore — 浏览社区"
        return 0
    fi

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║       智能匹配推荐 (Top ${top_n})            ║"
    echo "╚════════════════════════════════════════╝"
    echo ""
    echo "────────────────────────────────────────"

    local count=0
    while IFS='|' read -r score other_user their_name common_list common_count skill_count; do
        count=$((count + 1))
        echo ""
        echo "${count}. @${other_user} (${their_name}) — 匹配度 ${score}分"
        echo "   共同兴趣：${common_list:-无}"
        echo "   技能互补：${skill_count} 项"
        echo "   -> /friends auto ${other_user}"
    done <<< "$matches"

    echo ""
    echo "────────────────────────────────────────"
    echo ""
}

# Main
usage() {
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list [--top N]    List top matches (default: 5)"
    echo "  display [--top N] Display formatted match cards"
    echo ""
    echo "Options:"
    echo "  --top N    Number of matches to show (default: 5)"
    exit 1
}

main() {
    local cmd="${1:-display}"
    shift || true

    local top_n=5

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --top)
                top_n="${2:-5}"
                shift 2 || true
                ;;
            *)
                usage
                ;;
        esac
    done

    # Check init
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "ERROR: Not initialized. Run /friends init first." >&2
        exit 1
    fi

    # Check repo
    if [[ ! -d "${REPO_DIR}/.git" ]]; then
        echo "ERROR: Repo not cloned. Run /friends init first." >&2
        exit 1
    fi

    # Sync pull first
    info "同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull 2>/dev/null || echo "WARN: Sync failed, continuing..."

    case "$cmd" in
        list)
            get_matches "$top_n"
            ;;
        display)
            display_matches "$top_n"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
