#!/usr/bin/env bash
# claw-friends: profile.sh (UX Enhanced)
# View and edit profile with visual cards
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
# View Profile
# ─────────────────────────────────────────────────────────────

view_profile() {
    local target_user="${1:-}"
    local username
    username=$(get_username)

    if [ -z "$target_user" ]; then
        target_user="$username"
    fi

    local profile_file="${REPO_DIR}/profiles/${target_user}.yaml"

    if [ ! -f "$profile_file" ]; then
        error_user_not_found "$target_user"
        exit 1
    fi

    # Check if seed profile
    if grep -q 'is_seed: true' "$profile_file"; then
        error_seed_profile "$target_user"
        exit 1
    fi

    local is_self="false"
    [ "$target_user" = "$username" ] && is_self="true"

    render_profile_card "$profile_file" "$is_self"

    # Show actions for own profile
    if [ "$is_self" = "true" ]; then
        echo "操作:"
        echo "  [e] 编辑资料"
        echo "  [h] 智能导入 GitHub"
        echo "  [q] 返回"
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Edit Profile
# ─────────────────────────────────────────────────────────────

edit_profile() {
    local username
    username=$(get_username)
    local profile_file="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "$profile_file" ]; then
        error_profile_empty
        exit 1
    fi

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    # Show current profile
    view_profile

    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  编辑资料                                            ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""
    echo "请选择要编辑的部分:"
    echo ""
    echo "  [1] 显示名称 (display_name)"
    echo "  [2] 个人简介 (bio)"
    echo "  [3] 兴趣标签 (interests)"
    echo "  [4] 技能标签 (skills)"
    echo "  [5] 寻找什么 (looking_for)"
    echo "  [6] 理想类型 (ideal_type)"
    echo "  [7] 快速添加 (智能导入 GitHub)"
    echo "  [0] 保存并返回"
    echo ""
    echo -n "选择 [0-7]: "

    read -r choice

    case "$choice" in
        1)
            echo -n "新的显示名称："
            read -r new_value
            update_field "display_name" "$new_value" "$profile_file"
            ;;
        2)
            echo -n "新的个人简介："
            read -r new_value
            update_field "bio" "$new_value" "$profile_file"
            ;;
        3)
            edit_list_field "interests" "兴趣" "$profile_file"
            ;;
        4)
            edit_list_field "skills" "技能" "$profile_file"
            ;;
        5)
            edit_list_field "looking_for" "寻找" "$profile_file"
            ;;
        6)
            edit_ideal_type "$profile_file"
            ;;
        7)
            bash "${SCRIPT_DIR}/enhance.sh"
            return
            ;;
        0)
            echo "已保存"
            return
            ;;
        *)
            echo "无效选择"
            return
            ;;
    esac

    # Update timestamp
    update_timestamp "$profile_file"

    # Sync changes
    echo ""
    echo -e "${BLUE}⟳${NC} 正在同步更改..."
    cd "${REPO_DIR}"
    git add "profiles/${username}.yaml" 2>/dev/null || true
    git commit -m "chore: update profile for ${username}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || print_warning "推送失败，稍后手动 /friends sync"

    success_profile_updated

    # Recursive edit
    edit_profile
}

# ─────────────────────────────────────────────────────────────
# Update Field
# ─────────────────────────────────────────────────────────────

update_field() {
    local field="$1"
    local value="$2"
    local file="$3"

    if grep -q "^${field}:" "$file"; then
        sed -i.bak "s|^${field}:.*|${field}: \"${value}\"|" "$file"
        rm -f "${file}.bak"
    fi
}

update_timestamp() {
    local file="$1"
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    sed -i.bak "s/^updated_at:.*/updated_at: \"${timestamp}\"/" "$file"
    rm -f "${file}.bak"
}

# ─────────────────────────────────────────────────────────────
# Edit List Field
# ─────────────────────────────────────────────────────────────

edit_list_field() {
    local field="$1"
    local field_cn="$2"
    local file="$3"

    echo ""
    echo "当前 ${field_cn}:"
    awk "/^${field}:$/,/^[a-z_]+:/" "$file" 2>/dev/null | grep '^ *-' | sed 's/^ *- */  • /'

    echo ""
    echo "请输入新的 ${field_cn} (用逗号分隔，如：rust,go,python):"
    echo -n "> "
    read -r input

    if [ -z "$input" ]; then
        echo "已取消"
        return
    fi

    # Convert to YAML list
    local yaml_list=""
    IFS=',' read -ra items <<< "$input"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)  # trim
        if [ -n "$item" ]; then
            yaml_list="${yaml_list}  - ${item}\n"
        fi
    done

    # Update file
    local temp_file
    temp_file=$(mktemp)
    local in_field=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^${field}: ]]; then
            echo "$line"
            echo -e "$yaml_list" | grep -v '^$'
            in_field=true
            continue
        elif [[ "$line" =~ ^[a-z_]+: ]] && [ "$in_field" = true ]; then
            in_field=false
        fi

        if [ "$in_field" = true ] && [[ "$line" =~ ^[[:space:]]*-[[:space:]] ]]; then
            continue
        fi

        echo "$line"
    done < "$file" > "$temp_file"

    mv "$temp_file" "$file"
}

# ─────────────────────────────────────────────────────────────
# Edit Ideal Type
# ─────────────────────────────────────────────────────────────

edit_ideal_type() {
    local file="$1"
    local wizard_mode="${2:-false}"

    echo ""
    if [ "$wizard_mode" = "true" ]; then
        echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${NC}  ${BOLD}🎯 理想类型配置向导${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "这个配置将帮助你找到更匹配的合作伙伴"
        echo "每个步骤都可以直接回车跳过"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    else
        echo "理想类型配置:"
        echo ""
    fi

    # Preferred interests
    echo "1. 首选兴趣 (用逗号分隔，如：rust,cloud-native)"
    echo "   帮助匹配有共同话题的人"
    if [ "$wizard_mode" = "true" ]; then
        echo -e "   ${CYAN}示例：rust, distributed-systems, open-source${NC}"
    fi
    echo -n "> "
    read -r interests
    if [ -n "$interests" ]; then
        update_ideal_field "preferred_interests" "$interests" "$file"
        echo -e "  ${GREEN}✓${NC} 已添加首选兴趣"
    fi
    echo ""

    # Preferred skills
    echo "2. 首选技能 (用逗号分隔，如：go,python)"
    echo "   匹配技术互补的合作伙伴"
    if [ "$wizard_mode" = "true" ]; then
        echo -e "   ${CYAN}示例：rust, python, kubernetes${NC}"
    fi
    echo -n "> "
    read -r skills
    if [ -n "$skills" ]; then
        update_ideal_field "preferred_skills" "$skills" "$file"
        echo -e "  ${GREEN}✓${NC} 已添加首选技能"
    fi
    echo ""

    # Personality traits
    echo "3. 性格特质 (用逗号分隔)"
    echo "   匹配工作风格相近的人"
    if [ "$wizard_mode" = "true" ]; then
        echo -e "   ${CYAN}示例：early-mover, detail-oriented, mentor${NC}"
    fi
    echo -n "> "
    read -r traits
    if [ -n "$traits" ]; then
        update_ideal_field "personality_traits" "$traits" "$file"
        echo -e "  ${GREEN}✓${NC} 已添加性格特质"
    fi
    echo ""

    # Deal breakers
    echo "4. 否决项 (用逗号分隔，谨慎填写)"
    echo "   出现这些标签的用户将不会被推荐"
    if [ "$wizard_mode" = "true" ]; then
        echo -e "   ${CYAN}示例：no-commit, inactive${NC}"
    fi
    echo -n "> "
    read -r deal_breakers
    if [ -n "$deal_breakers" ]; then
        update_ideal_field "deal_breakers" "$deal_breakers" "$file"
        echo -e "  ${GREEN}✓${NC} 已添加否决项"
    fi
    echo ""

    # Description
    echo "5. 描述 (可选，一句话描述理想伙伴)"
    if [ "$wizard_mode" = "true" ]; then
        echo -e "   ${CYAN}示例：寻找一起开源创业的 Rust 开发者${NC}"
    fi
    echo -n "> "
    read -r description
    if [ -n "$description" ]; then
        update_field "ideal_type_description" "$description" "$file"
        echo -e "  ${GREEN}✓${NC} 已添加描述"
    fi
    echo ""

    if [ "$wizard_mode" = "true" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo -e "${GREEN}✓ 理想类型配置完成！${NC}"
        echo ""
        echo "下一步:"
        echo "  [1] 继续完善其他资料"
        echo "  [2] 开始查看匹配推荐"
        echo "  [3] 浏览社区"
        echo -n "选择 [1-3]: "
        read -r next_choice
        case "$next_choice" in
            2)
                bash "${SCRIPT_DIR}/match.sh"
                ;;
            3)
                bash "${SCRIPT_DIR}/explore.sh"
                ;;
            *)
                echo "返回资料编辑"
                ;;
        esac
    fi
}

update_ideal_field() {
    local field="$1"
    local value="$2"
    local file="$3"

    # Convert comma-separated to YAML list
    local yaml_list=""
    IFS=',' read -ra items <<< "$value"
    for item in "${items[@]}"; do
        item=$(echo "$item" | xargs)
        if [ -n "$item" ]; then
            yaml_list="${yaml_list}  - ${item}\n"
        fi
    done

    # Find and replace in ideal_type section
    local temp_file
    temp_file=$(mktemp)
    local in_ideal=false
    local in_subfield=false

    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ ^ideal_type: ]]; then
            echo "$line"
            in_ideal=true
            continue
        fi

        if [ "$in_ideal" = true ]; then
            if [[ "$line" =~ ^[[:space:]]+${field}: ]]; then
                echo "  ${field}:"
                echo -e "$yaml_list" | grep -v '^$'
                in_subfield=true
                continue
            elif [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]] && [ "$in_subfield" = true ]; then
                continue
            elif [[ "$line" =~ ^[[:space:]]+[a-z_]+: ]] && [ "$in_subfield" = true ]; then
                in_subfield=false
            elif [[ "$line" =~ ^[a-z_]+: ]]; then
                in_ideal=false
            fi
        fi

        echo "$line"
    done < "$file" > "$temp_file"

    mv "$temp_file" "$file"
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local action="${1:-view}"
    local target="${2:-}"

    case "$action" in
        view)
            view_profile "$target"
            ;;
        edit)
            edit_profile
            ;;
        edit_ideal_wizard)
            local username
            username=$(get_username)
            local profile_file="${REPO_DIR}/profiles/${username}.yaml"
            edit_ideal_type "$profile_file" "true"
            ;;
        *)
            echo "用法：/friends profile [view|edit] [user]"
            ;;
    esac
}

main "$@"
