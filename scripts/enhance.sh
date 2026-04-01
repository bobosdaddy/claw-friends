#!/usr/bin/env bash
# claw-friends: enhance.sh (UX Enhanced)
# Smart GitHub profile enhancement with visual feedback
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

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  🧠 ${BOLD}GitHub 智能资料填充${NC}                              ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_loading() {
    echo -e "  ${CYAN}⟳${NC} $1..."
}

print_success() {
    echo -e "  ${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "  ${YELLOW}⚠️${NC}  $1"
}

print_error() {
    echo -e "  ${RED}✗${NC} $1"
}

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        echo "ERROR: Not initialized" >&2
        exit 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# ─────────────────────────────────────────────────────────────
# GitHub Data Fetching
# ─────────────────────────────────────────────────────────────

fetch_github_data() {
    local username="$1"

    print_loading "获取仓库语言"
    local languages
    languages=$(gh api "users/${username}/repos?per_page=100" 2>/dev/null \
        | jq -r '.[].primaryLanguage.name // empty' \
        | sort | uniq -c | sort -rn | head -5 \
        | awk '{print $2}')

    print_loading "获取项目主题"
    local repo_topics
    repo_topics=$(gh api "users/${username}/repos?per_page=100" 2>/dev/null \
        | jq -r '.[].topics[] // empty' \
        | sort | uniq -c | sort -rn | head -10 \
        | awk '{print $2}')

    print_loading "分析 Star 偏好"
    local star_topics
    star_topics=$(gh api "users/${username}/starred?per_page=100" 2>/dev/null \
        | jq -r '.[].topics[] // empty' \
        | sort | uniq -c | sort -rn | head -5 \
        | awk '{print $2}')

    print_loading "获取贡献活跃度"
    local contrib_count
    contrib_count=$(gh api "users/${username}/events" 2>/dev/null \
        | jq -r 'select(.type=="PushEvent") | .repo.name' | wc -l | tr -d ' ')

    # Output as structured data
    echo "LANGUAGES:${languages}"
    echo "REPO_TOPICS:${repo_topics}"
    echo "STAR_TOPICS:${star_topics}"
    echo "CONTRIB_COUNT:${contrib_count}"
}

# ─────────────────────────────────────────────────────────────
# Display Results
# ─────────────────────────────────────────────────────────────

display_inferred_tags() {
    local languages="$1"
    local repo_topics="$2"
    local star_topics="$3"

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📊 智能推断结果${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Skills from languages
    echo "┌─────────────────────────────────────────────────┐"
    echo "│  🛠️  推荐技能 (从仓库语言)                      │"
    echo "├─────────────────────────────────────────────────┤"
    if [ -n "$languages" ]; then
        for lang in $languages; do
            printf "│   %-38s │\n" "✓ ${lang}"
        done
    else
        printf "│   %-38s │\n" "暂无数据"
    fi
    echo "└─────────────────────────────────────────────────┘"
    echo ""

    # Interests from topics
    echo "┌─────────────────────────────────────────────────┐"
    echo "│  🏷️  推荐兴趣 (从仓库主题+Star)                 │"
    echo "├─────────────────────────────────────────────────┤"
    local all_topics
    all_topics=$(echo -e "${repo_topics}\n${star_topics}" | sort -u | head -8)
    if [ -n "$all_topics" ]; then
        local formatted_topics
        formatted_topics=$(echo "$all_topics" | tr '\n' ' ' | sed 's/  */  /g')
        local line=""
        for topic in $all_topics; do
            if [ ${#line} -lt 35 ]; then
                line="$line #$topic"
            else
                printf "│   %-38s │\n" "$line"
                line="#$topic"
            fi
        done
        if [ -n "$line" ]; then
            printf "│   %-38s │\n" "$line"
        fi
    else
        printf "│   %-38s │\n" "暂无数据"
    fi
    echo "└─────────────────────────────────────────────────┘"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Calculate Completeness Score
# ─────────────────────────────────────────────────────────────

calculate_completeness() {
    local profile_file="$1"

    local score=0

    # display_name (10%)
    local display_name
    display_name=$(grep '^display_name:' "$profile_file" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -n "$display_name" ]; then
        score=$((score + 10))
    fi

    # bio (15%)
    local bio
    bio=$(grep '^bio:' "$profile_file" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -n "$bio" ] && [ ${#bio} -ge 20 ]; then
        score=$((score + 15))
    elif [ -n "$bio" ]; then
        score=$((score + 5))
    fi

    # interests (25% - 5% per item, max 5)
    local interests_count
    interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null \
        | grep '^ *-' | wc -l | tr -d ' ')
    interests_count=$((interests_count > 5 ? 5 : interests_count))
    score=$((score + interests_count * 5))

    # skills (25% - 5% per item, max 5)
    local skills_count
    skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null \
        | grep '^ *-' | wc -l | tr -d ' ')
    skills_count=$((skills_count > 5 ? 5 : skills_count))
    score=$((score + skills_count * 5))

    # looking_for (10%)
    local looking_for
    looking_for=$(grep '^looking_for:' "$profile_file" -A 2 | grep '^ *-' | wc -l | tr -d ' ')
    if [ "$looking_for" -gt 0 ]; then
        score=$((score + 10))
    fi

    # ideal_type (15%)
    local ideal_count
    ideal_count=$(awk '/^ideal_type:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null \
        | grep -E '^\s+\w+:.*\S' | wc -l | tr -d ' ')
    ideal_count=$((ideal_count > 5 ? 5 : ideal_count))
    score=$((score + ideal_count * 3))

    echo "$score"
}

# ─────────────────────────────────────────────────────────────
# Update Profile
# ─────────────────────────────────────────────────────────────

update_profile() {
    local username="$1"
    local languages="$2"
    local topics="$3"
    local profile_file="${REPO_DIR}/profiles/${username}.yaml"

    # Convert to YAML arrays
    local skills_yaml=""
    for lang in $languages; do
        skills_yaml="${skills_yaml}  - ${lang}\n"
    done

    local interests_yaml=""
    for topic in $topics; do
        interests_yaml="${interests_yaml}  - ${topic}\n"
    done

    # Read current profile
    local current_interests
    current_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-')
    local current_skills
    current_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile_file" 2>/dev/null | grep '^ *-')

    # Merge (avoid duplicates)
    local new_interests="$current_interests"
    for topic in $topics; do
        if ! echo "$current_interests" | grep -q "$topic"; then
            new_interests="${new_interests}  - ${topic}\n"
        fi
    done

    local new_skills="$current_skills"
    for lang in $languages; do
        if ! echo "$current_skills" | grep -q "$lang"; then
            new_skills="${new_skills}  - ${lang}\n"
        fi
    done

    # Create updated profile
    local updated_at
    updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # Use sed to update interests and skills sections
    local temp_file
    temp_file=$(mktemp)

    # Read and rebuild profile
    local in_interests=false
    local in_skills=false
    local interests_written=false
    local skills_written=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^interests: ]]; then
            echo "$line"
            echo -e "$new_interests" | grep -v '^$'
            in_interests=true
            interests_written=true
            continue
        elif [[ "$line" =~ ^skills: ]]; then
            echo "$line"
            echo -e "$new_skills" | grep -v '^$'
            in_skills=true
            skills_written=true
            continue
        elif [[ "$line" =~ ^looking_for: ]] && [ "$in_interests" = true ]; then
            in_interests=false
        elif [[ "$line" =~ ^platforms: ]] && [ "$in_skills" = true ]; then
            in_skills=false
        fi

        # Skip old interest/skill items
        if [ "$in_interests" = true ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        fi
        if [ "$in_skills" = true ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        fi

        echo "$line"
    done < "$profile_file" > "$temp_file"

    # Update updated_at
    sed -i.bak "s/^updated_at:.*/updated_at: \"${updated_at}\"/" "$temp_file"
    rm -f "$profile_file.bak"

    mv "$temp_file" "$profile_file"
}

# ─────────────────────────────────────────────────────────────
# Main Flow
# ─────────────────────────────────────────────────────────────

main() {
    print_header

    local username
    username=$(get_username)
    local profile_file="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "$profile_file" ]; then
        print_error "资料文件不存在"
        echo "请先运行 /friends init 初始化"
        exit 1
    fi

    # Show current completeness
    local current_score
    current_score=$(calculate_completeness "$profile_file")

    echo "当前资料完整度：${current_score}%"
    if [ "$current_score" -lt 30 ]; then
        echo -e "${YELLOW}⚠️  资料较空洞，匹配质量会受影响${NC}"
    elif [ "$current_score" -lt 70 ]; then
        echo -e "${BLUE}ℹ  资料尚可，但可以更完善${NC}"
    else
        echo -e "${GREEN}✓  资料完整度良好${NC}"
    fi
    echo ""

    # Fetch data
    print_loading "正在分析 GitHub 数据"
    echo ""

    local data
    data=$(fetch_github_data "$username")

    local languages repo_topics star_topics contrib_count
    languages=$(echo "$data" | grep '^LANGUAGES:' | sed 's/^LANGUAGES://')
    repo_topics=$(echo "$data" | grep '^REPO_TOPICS:' | sed 's/^REPO_TOPICS://')
    star_topics=$(echo "$data" | grep '^STAR_TOPICS:' | sed 's/^STAR_TOPICS://')
    contrib_count=$(echo "$data" | grep '^CONTRIB_COUNT:' | sed 's/^CONTRIB_COUNT://')

    print_success "分析完成"

    # Display results
    display_inferred_tags "$languages" "$repo_topics" "$star_topics"

    # Ask for confirmation
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  要添加这些标签到你的资料吗？                         ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo -n "  [Y/n]: "
    read -r confirm

    if [[ "$confirm" != "n" && "$confirm" != "N" ]]; then
        print_loading "更新资料"

        # Combine topics
        local all_topics
        all_topics=$(echo -e "${repo_topics}\n${star_topics}" | sort -u | grep -v '^$')

        update_profile "$username" "$languages" "$all_topics"

        # Sync
        cd "${REPO_DIR}"
        git add "profiles/${username}.yaml" 2>/dev/null || true
        git commit -m "chore: enhance profile from GitHub for ${username}" >/dev/null 2>&1 || true
        git push origin HEAD 2>/dev/null || print_warning "推送失败，稍后手动 /friends sync"

        print_success "资料已更新"

        # Show new score
        local new_score
        new_score=$(calculate_completeness "$profile_file")

        echo ""
        echo "资料完整度：${current_score}% → ${GREEN}${new_score}%${NC}"

        if [ "$new_score" -ge 70 ]; then
            echo ""
            echo -e "${GREEN}✓ 资料已足够完善，可以开始匹配了!${NC}"
            echo ""
            echo "下一步:"
            echo "  /friends match  — 查看智能推荐"
            echo "  /friends explore  — 浏览社区"
        fi
    else
        echo ""
        echo "已跳过。你可以随时手动编辑:"
        echo "  /friends profile edit"
    fi

    echo ""
}

main "$@"
