#!/usr/bin/env bash
# claw-friends: report.sh (UX Enhanced)
# View friendship reports with visual cards
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
REPORTS_DIR="${OCFR_DIR}/reports"

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
# List Reports
# ─────────────────────────────────────────────────────────────

list_reports() {
    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}📊 友谊报告列表${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$REPORTS_DIR" ] || [ -z "$(ls -A "$REPORTS_DIR" 2>/dev/null)" ]; then
        echo "暂无友谊报告"
        echo ""
        echo "完成自动协商后，报告将在这里显示"
        echo ""
        return
    fi

    local count=0
    for f in "$REPORTS_DIR"/*.yaml; do
        [ ! -f "$f" ] && continue
        count=$((count + 1))

        local user
        user=$(basename "$f" .yaml)

        # Get basic info
        local generated_at affinity_score status
        generated_at=$(grep '^generated_at:' "$f" 2>/dev/null | sed 's/^generated_at: *"\([^"]*\)"/\1/' | head -1)
        affinity_score=$(grep '^affinity_score:' "$f" 2>/dev/null | awk '{print $2}' | head -1)
        status=$(grep '^status:' "$f" 2>/dev/null | awk '{print $2}' | tr -d '"' | head -1)

        local status_emoji
        case "$status" in
            matched|partial) status_emoji="🎉" ;;
            rejected) status_emoji="❌" ;;
            expired) status_emoji="⏰" ;;
            *) status_emoji="📊" ;;
        fi

        echo "┌─────────────────────────────────────────────────────────┐"
        printf "│ ${status_emoji} @%-50s│\n" "$user"
        echo "│                                                         │"
        if [ -n "$affinity_score" ] && [ "$affinity_score" != "null" ]; then
            printf "│  好感分：%-42s│\n" "${affinity_score}/100"
        fi
        if [ -n "$generated_at" ]; then
            printf "│  生成时间：%-40s│\n" "$generated_at"
        fi
        echo "│                                                         │"
        echo "│  → /friends report ${user} 查看详细                     │"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""
    done

    if [ $count -eq 0 ]; then
        echo "暂无友谊报告"
    fi

    echo ""
}

# ─────────────────────────────────────────────────────────────
# View Report
# ─────────────────────────────────────────────────────────────

view_report() {
    local target="$1"
    local report_file="${REPORTS_DIR}/${target}.yaml"

    if [ ! -f "$report_file" ]; then
        echo "未找到 @${target} 的友谊报告"
        echo ""
        echo "可用报告:"
        list_reports
        exit 1
    fi

    # Parse fields
    local generated_at affinity_score their_score rounds_completed
    generated_at=$(grep '^generated_at:' "$report_file" | sed 's/^generated_at: *"\([^"]*\)"/\1/' | head -1)
    affinity_score=$(grep '^affinity_score:' "$report_file" | awk '{print $2}' | head -1)
    their_score=$(grep '^their_score:' "$report_file" | awk '{print $2}' | head -1)
    rounds_completed=$(grep '^rounds_completed:' "$report_file" | awk '{print $2}' | head -1)

    # About section
    local about_name about_github about_bio
    about_name=$(awk '/^about:$/,/^claw_skill/' "$report_file" | grep '^  display_name:' | sed 's/^  display_name: *"\([^"]*\)"/\1/' | head -1)
    about_github=$(awk '/^about:$/,/^claw_skill/' "$report_file" | grep '^  github:' | sed 's/^  github: *"\([^"]*\)"/\1/' | head -1)
    about_bio=$(awk '/^about:$/,/^claw_skill/' "$report_file" | grep '^  bio:' | sed 's/^  bio: *"\([^"]*\)"/\1/' | head -1)

    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}📊 友谊报告${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  生成时间：%-43s│\n" "$generated_at"
    printf "│  匹配：@%-49s│\n" "$target"
    echo "│                                                         │"

    # Affinity score bar
    local bar_width=20
    local filled=$((affinity_score * bar_width / 100))
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=filled; i<bar_width; i++)); do bar="${bar}░"; done

    printf "│  你的好感分：${GREEN}%3d/100${NC}  ${CYAN}%s${NC}                      │\n" "$affinity_score" "$bar"
    if [ -n "$their_score" ] && [ "$their_score" != "null" ]; then
        filled=$((their_score * bar_width / 100))
        bar=""
        for ((i=0; i<filled; i++)); do bar="${bar}█"; done
        for ((i=filled; i<bar_width; i++)); do bar="${bar}░"; done
        printf "│  他们的好感分：${GREEN}%3d/100${NC}  ${CYAN}%s${NC}                    │\n" "$their_score" "$bar"
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # About section
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}👤 关于 @${target}${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"
    if [ -n "$about_name" ]; then
        printf "│  ${BOLD}%s${NC} (@${about_github})"
        printf "%*s│\n" $((48 - ${#about_name} - ${#about_github})) ""
    fi
    if [ -n "$about_bio" ]; then
        echo "$about_bio" | fold -w 52 | while IFS= read -r line; do
            printf "│  %-54s│\n" "\"$line\""
        done
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Claw skill declaration
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}🛠 Claw 技能声明${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"

    local skills
    skills=$(awk '/^claw_skill_declaration:$/,/^personality/' "$report_file" 2>/dev/null | grep '^  primary_skills:' | sed 's/^  primary_skills: *//' | head -1)
    if [ -n "$skills" ]; then
        echo "$skills" | fold -w 52 | while IFS= read -r line; do
            printf "│  %-54s│\n" "$line"
        done
    else
        printf "│  %-54s│\n" "${DIM}暂无数据${NC}"
    fi

    local style
    style=$(awk '/^claw_skill_declaration:$/,/^personality/' "$report_file" 2>/dev/null | grep '^  collaboration_style:' | sed 's/^  collaboration_style: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    if [ -n "$style" ]; then
        printf "│  风格：%-46s│\n" "$style"
    fi

    local timezone
    timezone=$(awk '/^claw_skill_declaration:$/,/^personality/' "$report_file" 2>/dev/null | grep '^  timezone:' | sed 's/^  timezone: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    if [ -n "$timezone" ]; then
        printf "│  时区：%-46s│\n" "$timezone"
    fi

    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Compatibility analysis
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}🎯 匹配分析${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"

    local match_reason
    match_reason=$(awk '/^compatibility_analysis:$/,/^collaboration/' "$report_file" 2>/dev/null | grep '^  match_reason:' | sed 's/^  match_reason: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

    if [ -n "$match_reason" ]; then
        echo "$match_reason" | fold -w 52 | while IFS= read -r line; do
            printf "│  %-54s│\n" "$line"
        done
    else
        printf "│  %-54s│\n" "${DIM}暂无数据${NC}"
    fi

    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Collaboration suggestions
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}💡 协作建议${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"

    local suggestions
    suggestions=$(awk '/^collaboration_suggestions:$/,/^learning/' "$report_file" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3)

    if [ -n "$suggestions" ]; then
        local i=1
        echo "$suggestions" | while IFS= read -r sug; do
            printf "│  %d. %-51s│\n" "$i" "$sug"
            i=$((i + 1))
        done
    else
        printf "│  %-54s│\n" "${DIM}暂无建议${NC}"
    fi

    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Learning insights
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}📚 学习收获${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"

    local insights
    insights=$(awk '/^learning_insights:$/,/^learning_summary/' "$report_file" 2>/dev/null | grep '^  - topic:' | sed 's/^  - topic: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -3)

    if [ -n "$insights" ]; then
        echo "$insights" | while IFS= read -r topic; do
            printf "│  • %-52s│\n" "[$topic]"
        done
    else
        printf "│  %-54s│\n" "${DIM}暂无收获${NC}"
    fi

    local summary
    summary=$(awk '/^learning_summary:$/,/^[a-z]/' "$report_file" 2>/dev/null | grep '^  learning_summary:' | sed 's/^  learning_summary: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)

    if [ -n "$summary" ]; then
        echo "│  ─────────────────────────────────────────────────────  │"
        echo "$summary" | fold -w 52 | while IFS= read -r line; do
            printf "│  %-54s│\n" "$line"
        done
    fi

    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Next steps
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "下一步:"
    echo "  /friends msg ${target}      — 发送消息"
    echo "  /friends connect ${target}  — 交换联系方式"
    echo "  /friends auto stop ${target} — 结束协商"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local target="${1:-}"

    if [ -z "$target" ]; then
        list_reports
    else
        view_report "$target"
    fi
}

main "$@"
