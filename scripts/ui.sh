#!/usr/bin/env bash
# claw-friends: ui.sh (UX Enhanced)
# Visual card system and UI components
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[0;37m'
NC='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'

# ─────────────────────────────────────────────────────────────
# Profile Card
# ─────────────────────────────────────────────────────────────

render_profile_card() {
    local profile_file="$1"
    local is_self="${2:-false}"

    if [ ! -f "$profile_file" ]; then
        echo "Profile not found"
        return 1
    fi

    # Parse fields
    local display_name username github bio updated_at
    display_name=$(grep '^display_name:' "$profile_file" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    username=$(grep '^username:' "$profile_file" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    github=$(grep '^github:' "$profile_file" | sed 's/^github: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    bio=$(grep '^bio:' "$profile_file" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    updated_at=$(grep '^updated_at:' "$profile_file" | sed 's/^updated_at: *"\([^"]*\)"/\1/' | head -1)

    # Parse arrays
    local interests skills looking_for
    interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -5)
    skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -8)
    looking_for=$(awk '/^looking_for:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3)

    # Calculate completeness
    local completeness
    completeness=$(calculate_completeness "$profile_file")

    # Completeness indicator
    local completeness_icon
    if [ "$completeness" -lt 30 ]; then
        completeness_icon="⚠️ "
    elif [ "$completeness" -lt 70 ]; then
        completeness_icon="📝"
    else
        completeness_icon="✓"
    fi

    # Header
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    if [ "$is_self" = "true" ]; then
        echo -e "${CYAN}║${NC}  ${BOLD}🦞 我的资料${NC}                                      ${CYAN}║${NC}"
    else
        echo -e "${CYAN}║${NC}  ${BOLD}👤 用户资料${NC}                                      ${CYAN}║${NC}"
    fi
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Main card
    echo "┌─────────────────────────────────────────────────────────┐"

    # Name and avatar placeholder
    echo "│                                                         │"
    printf "│  %-54s│\n" "${BOLD}${display_name}${NC} @${username}"
    printf "│  %-54s│\n" "${DIM}https://github.com/${github}${NC}"
    echo "│                                                         │"

    # Bio
    if [ -n "$bio" ]; then
        local bio_lines
        bio_lines=$(echo "$bio" | fold -w 52)
        while IFS= read -r line; do
            printf "│  %-54s│\n" "\"$line\""
        done <<< "$bio_lines"
    else
        printf "│  %-54s│\n" "${DIM}暂无简介${NC}"
    fi
    echo "│                                                         │"

    # Separator
    echo "│  ─────────────────────────────────────────────────────  │"
    echo "│                                                         │"

    # Interests
    echo "│  ${BOLD}🏷️  兴趣${NC}"
    if [ -n "$interests" ]; then
        local interest_line=""
        while IFS= read -r interest; do
            if [ -n "$interest" ]; then
                interest_line="${interest_line}#${interest}  "
            fi
        done <<< "$interests"
        printf "│  %-54s│\n" "${interest_line}"
    else
        printf "│  %-54s│\n" "${DIM}暂无兴趣标签${NC}"
    fi
    echo "│                                                         │"

    # Skills
    echo "│  ${BOLD}🛠️  技能${NC}"
    if [ -n "$skills" ]; then
        local skill_line=""
        while IFS= read -r skill; do
            if [ -n "$skill" ]; then
                skill_line="${skill_line}${skill} · "
            fi
        done <<< "$skills"
        skill_line="${skill_line%…}"
        printf "│  %-54s│\n" "${skill_line}"
    else
        printf "│  %-54s│\n" "${DIM}暂无技能标签${NC}"
    fi
    echo "│                                                         │"

    # Looking for
    echo "│  ${BOLD}🎯 寻找${NC}"
    if [ -n "$looking_for" ]; then
        while IFS= read -r item; do
            if [ -n "$item" ]; then
                printf "│  • %-52s│\n" "$item"
            fi
        done <<< "$looking_for"
    else
        printf "│  %-54s│\n" "${DIM}暂无说明${NC}"
    fi
    echo "│                                                         │"

    # Footer
    echo "│  ─────────────────────────────────────────────────────  │"
    printf "│  %-30s  %-22s│\n" "📊 完整度：${completeness_icon}${completeness}%" "🕐 ${updated_at:-未知}"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Match Card
# ─────────────────────────────────────────────────────────────

render_match_card() {
    local rank="$1"
    local username="$2"
    local display_name="$3"
    local score="$4"
    local common_interests="$5"
    local skill_complement="$6"
    local match_reason="$7"

    # Progress bar for score
    local bar_width=20
    local filled=$((score * bar_width / 100))
    local empty=$((bar_width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done

    # Rank emoji
    local rank_emoji
    case "$rank" in
        1) rank_emoji="🥇" ;;
        2) rank_emoji="🥈" ;;
        3) rank_emoji="🥉" ;;
        *) rank_emoji="📍" ;;
    esac

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│ ${rank_emoji} ${BOLD}%-48s${NC} │\n" "${display_name} (@${username})"
    echo "│                                                         │"

    # Score
    printf "│  匹配度：${GREEN}%3d%%${NC}  ${CYAN}%s${NC}                               │\n" "$score" "$bar"
    echo "│                                                         │"

    # Common interests
    if [ -n "$common_interests" ]; then
        printf "│  ${BOLD}共同兴趣:${NC} %-38s│\n" "$common_interests"
    fi

    # Skill complement
    if [ -n "$skill_complement" ]; then
        printf "│  ${BOLD}技能互补:${NC} %-38s│\n" "$skill_complement 项他们有你没有的技能"
    fi
    echo "│                                                         │"

    # Match reason
    if [ -n "$match_reason" ]; then
        echo "│  ─────────────────────────────────────────────────────  │"
        echo "│  ${BOLD}💡 匹配原因:${NC}"
        # Word wrap the reason
        echo "$match_reason" | fold -w 50 | while IFS= read -r line; do
            printf "│  %-54s│\n" "$line"
        done
    fi

    echo "│                                                         │"
    echo "│  [1] 发起对话   [v] 查看详情   [→] 发送好友请求          │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Negotiation Status Card
# ─────────────────────────────────────────────────────────────

render_negotiation_card() {
    local target="$1"
    local display_name="$2"
    local round="$3"
    local max_rounds="$4"
    local phase="$5"
    local my_score="$6"
    local their_score="$7"
    local status="$8"
    local latest_update="$9"

    # Progress bar
    local bar_width=22
    local filled=$((round * bar_width / max_rounds))
    local empty=$((bar_width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=0; i<empty; i++)); do bar="${bar}░"; done

    # Phase emoji
    local phase_emoji
    case "$phase" in
        basic) phase_emoji="🌱" ;;
        detailed) phase_emoji="🌿" ;;
        personal) phase_emoji="🌸" ;;
        report) phase_emoji="📊" ;;
        *) phase_emoji="🔄" ;;
    esac

    # Status emoji
    local status_emoji
    case "$status" in
        waiting) status_emoji="⏳" ;;
        my_turn) status_emoji="✍️ " ;;
        matched) status_emoji="🎉" ;;
        rejected) status_emoji="❌" ;;
        expired) status_emoji="⏰" ;;
        *) status_emoji="🔄" ;;
    esac

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│ ${phase_emoji} ${BOLD}%-46s${NC} │\n" "与 @${target} (${display_name})"
    echo "│                                                         │"

    # Progress
    printf "│  进度：${CYAN}%s${NC} Round %d/%-2d                      │\n" "$bar" "$round" "$max_rounds"
    printf "│  阶段：%-45s│\n" "${phase} (${phase_emoji})"
    echo "│                                                         │"

    # Scores
    if [ -n "$my_score" ] && [ "$my_score" != "null" ]; then
        local my_emoji
        if [ "$my_score" -ge 70 ]; then my_emoji="😊"; elif [ "$my_score" -ge 50 ]; then my_emoji="😐"; else my_emoji="😕"; fi
        printf "│  你的好感分：%-36s${NC}│\n" "${my_score}/100 ${my_emoji}"
    fi

    if [ -n "$their_score" ] && [ "$their_score" != "null" ] && [ "$their_score" != "??" ]; then
        local their_emoji
        if [ "$their_score" -ge 70 ]; then their_emoji="😊"; elif [ "$their_score" -ge 50 ]; then their_emoji="😐"; else their_emoji="😕"; fi
        printf "│  他们的好感分：%-33s${NC}│\n" "${their_score}/100 ${their_emoji}"
    else
        printf "│  他们的好感分：%-33s│\n" "?? (等待对方评估)"
    fi
    echo "│                                                         │"

    # Latest update
    if [ -n "$latest_update" ]; then
        echo "│  ─────────────────────────────────────────────────────  │"
        echo "│  ${BOLD}最新动态:${NC}"
        echo "$latest_update" | fold -w 50 | while IFS= read -r line; do
            printf "│  %-54s│\n" "$line"
        done
    fi

    echo "│                                                         │"
    printf "│  状态：%-46s│\n" "${status_emoji} ${status}"

    # Actions based on status
    echo "│                                                         │"
    case "$status" in
        matched)
            echo "│  [r] 查看报告   [c] 交换联系方式   [m] 发消息       │"
            ;;
        waiting|my_turn)
            echo "│  [v] 查看详情   [s] 停止协商                        │"
            ;;
        *)
            echo "│  [v] 查看详情                                        │"
            ;;
    esac
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Friendship Report Card
# ─────────────────────────────────────────────────────────────

render_report_card() {
    local report_file="$1"

    if [ ! -f "$report_file" ]; then
        echo "Report not found"
        return 1
    fi

    # Parse fields
    local match_id generated_at affinity_score their_score
    match_id=$(grep '^match_id:' "$report_file" | sed 's/^match_id: *"\([^"]*\)"/\1/')
    generated_at=$(grep '^generated_at:' "$report_file" | sed 's/^generated_at: *"\([^"]*\)"/\1/')
    affinity_score=$(grep '^affinity_score:' "$report_file" | awk '{print $2}')
    their_score=$(grep '^their_score:' "$report_file" | awk '{print $2}')

    local about_name about_bio
    about_name=$(awk '/^about:$/,/^claw_skill/' "$report_file" | grep '^  display_name:' | sed 's/^  display_name: *"\([^"]*\)"/\1/')
    about_bio=$(awk '/^about:$/,/^claw_skill/' "$report_file" | grep '^  bio:' | sed 's/^  bio: *"\([^"]*\)"/\1/')

    echo ""
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}  ${BOLD}📊 友谊报告${NC}                                        ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  生成时间：%-43s│\n" "$generated_at"
    printf "│  匹配：${BOLD}%-50s${NC}│\n" "$match_id"
    echo "│                                                         │"

    # Affinity score with visual
    local bar_width=20
    local filled=$((affinity_score * bar_width / 100))
    local bar=""
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=filled; i<bar_width; i++)); do bar="${bar}░"; done

    printf "│  好感分：${GREEN}%3d/100${NC}  ${CYAN}%s${NC}                            │\n" "$affinity_score" "$bar"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # About section
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  ${BOLD}👤 关于 @$(echo "$match_id" | cut -d'__' -f2)${NC}"
    echo "│  ───────────────────────────────────────────────────────  │"
    printf "│  %-54s│\n" "${BOLD}${about_name}${NC}"
    if [ -n "$about_bio" ]; then
        echo "$about_bio" | fold -w 52 | while IFS= read -r line; do
            printf "│  %-54s│\n" "\"$line\""
        done
    fi
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Message Card
# ─────────────────────────────────────────────────────────────

render_message_sent() {
    local recipient="$1"
    local preview="$2"
    local timestamp="$3"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 消息已发送 (端到端加密)${NC}                      ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  收件人：${BOLD}%-46s${NC}│\n" "@${recipient}"
    printf "│  时间：%-49s│\n" "$timestamp"
    echo "│  状态：${GREEN}✓ 已加密${NC}  ${GREEN}✓ 已推送${NC}                            │"
    echo "│                                                         │"
    echo "│  ─────────────────────────────────────────────────────  │"
    echo "$preview" | fold -w 50 | while IFS= read -r line; do
        printf "│  %-54s│\n" "$line"
    done
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    echo "💡 提示：查看回复 /friends msg ${recipient}"
    echo ""
}

render_friend_request_sent() {
    local target="$1"
    local display_name="$2"

    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}📨 好友请求已发送${NC}                                  ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "┌─────────────────────────────────────────────────────────┐"
    printf "│  收件人：${BOLD}%-46s${NC}│\n" "${display_name} (@${target})"
    echo "│  状态：${YELLOW}⏳ 等待接受${NC}                                          │"
    echo "│                                                         │"
    echo "│  ─────────────────────────────────────────────────────  │"
    echo "│                                                         │"
    echo "│  💡 提示:                                               │"
    echo "│  • 对方接受后你们就可以发消息了                         │"
    echo "│  • 查看请求状态：/friends requests                      │"
    echo "│  • 撤回请求：/friends request cancel ${target}"
    printf "│                                                         │\n"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Helper: Calculate Completeness
# ─────────────────────────────────────────────────────────────

calculate_completeness() {
    local profile_file="$1"
    local score=0

    # display_name (10%)
    grep -q '^display_name:' "$profile_file" && score=$((score + 10))

    # bio (15%)
    local bio
    bio=$(grep '^bio:' "$profile_file" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -n "$bio" ] && [ ${#bio} -ge 20 ]; then
        score=$((score + 15))
    elif [ -n "$bio" ]; then
        score=$((score + 5))
    fi

    # interests (25%)
    local interests_count
    interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    interests_count=$((interests_count > 5 ? 5 : interests_count))
    score=$((score + interests_count * 5))

    # skills (25%)
    local skills_count
    skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    skills_count=$((skills_count > 5 ? 5 : skills_count))
    score=$((score + skills_count * 5))

    # looking_for (10%)
    grep -q '^looking_for:' "$profile_file" && score=$((score + 10))

    # ideal_type (15%)
    local ideal_count
    ideal_count=$(awk '/^ideal_type:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep -E '^\s+\w+:.*\S' | wc -l | tr -d ' ')
    ideal_count=$((ideal_count > 5 ? 5 : ideal_count))
    score=$((score + ideal_count * 3))

    echo "$score"
}

# Export functions for other scripts to source
export -f render_profile_card 2>/dev/null || true
export -f render_match_card 2>/dev/null || true
export -f render_negotiation_card 2>/dev/null || true
export -f render_report_card 2>/dev/null || true
export -f render_message_sent 2>/dev/null || true
export -f render_friend_request_sent 2>/dev/null || true
export -f calculate_completeness 2>/dev/null || true
