#!/usr/bin/env bash
# claw-friends: profile.sh
# Profile management: view, edit, update
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../templates/profile_template.yaml"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        error "未初始化。请先运行 /friends init"
        exit 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# 显示 profile 卡片
show_profile_card() {
    local profile_file="$1"
    local is_own="${2:-false}"

    if [ ! -f "${profile_file}" ]; then
        error "Profile 文件不存在"
        return 1
    fi

    local display_name bio github
    display_name=$(grep '^display_name:' "${profile_file}" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n')
    bio=$(grep '^bio:' "${profile_file}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n')
    github=$(grep '^github:' "${profile_file}" | sed 's/^github: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n')

    local interests skills looking_for
    interests=$(awk '/^interests:$/,/^[a-z_]+:/' "${profile_file}" | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//')
    skills=$(awk '/^skills:$/,/^[a-z_]+:/' "${profile_file}" | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//')
    looking_for=$(awk '/^looking_for:$/,/^[a-z_]+:/' "${profile_file}" | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//')

    local updated_at
    updated_at=$(grep '^updated_at:' "${profile_file}" | sed 's/^updated_at: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n')

    echo ""
    echo "┌──────────────────────────────────────┐"
    echo "│  ${display_name} (@${github})"
    echo "│  ────────────────────────────────────"
    echo "│  ${bio}"
    echo "│"
    echo "│  Interests: ${interests:-未填写}"
    echo "│  Skills:    ${skills:-未填写}"
    echo "│  Looking for: ${looking_for:-未填写}"
    echo "│"
    echo "│  Updated: ${updated_at}"
    echo "└──────────────────────────────────────┘"
    echo ""
}

# 编辑 profile
edit_profile() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "${profile}" ]; then
        error "Profile 不存在"
        exit 1
    fi

    # 先 sync pull
    info "同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull 2>/dev/null || warn "同步失败"

    echo ""
    echo "当前 profile:"
    show_profile_card "${profile}" "true"

    echo ""
    echo "────────────────────────────────────────"
    echo "编辑模式 (直接输入新值，留空跳过):"
    echo "────────────────────────────────────────"
    echo ""

    # 获取当前值
    local current_display current_bio current_interests current_skills current_looking
    current_display=$(grep '^display_name:' "${profile}" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    current_bio=$(grep '^bio:' "${profile}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    current_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "${profile}" | grep '^ *-' | sed 's/^ *- *//')
    current_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "${profile}" | grep '^ *-' | sed 's/^ *- *//')
    current_looking=$(awk '/^looking_for:$/,/^[a-z_]+:/' "${profile}" | grep '^ *-' | sed 's/^ *- *//')

    # 交互式编辑
    echo "1. 显示名称 (Display name)"
    echo "   当前：${current_display}"
    read -rp "   新的显示名称：[$(echo "$current_display" | head -c 30)...] " new_display
    new_display="${new_display:-$current_display}"

    echo ""
    echo "2. 个人简介 (Bio)"
    echo "   当前：${current_bio}"
    read -rp "   新的简介：" new_bio
    new_bio="${new_bio:-$current_bio}"

    echo ""
    echo "3. 兴趣爱好 (Interests, 逗号分隔)"
    echo "   当前：$(echo "$current_interests" | tr '\n' ',' | sed 's/,$//')"
    read -rp "   新的兴趣列表：" new_interests_input
    if [[ -n "$new_interests_input" ]]; then
        new_interests="$new_interests_input"
    else
        new_interests="$(echo "$current_interests" | tr '\n' ',' | sed 's/,$//')"
    fi

    echo ""
    echo "4. 技能 (Skills, 逗号分隔)"
    echo "   当前：$(echo "$current_skills" | tr '\n' ',' | sed 's/,$//')"
    read -rp "   新的技能列表：" new_skills_input
    if [[ -n "$new_skills_input" ]]; then
        new_skills="$new_skills_input"
    else
        new_skills="$(echo "$current_skills" | tr '\n' ',' | sed 's/,$//')"
    fi

    echo ""
    echo "5. 期待合作 (Looking for, 逗号分隔)"
    echo "   当前：$(echo "$current_looking" | tr '\n' ',' | sed 's/,$//')"
    read -rp "   新的期待：" new_looking_input
    if [[ -n "$new_looking_input" ]]; then
        new_looking="$new_looking_input"
    else
        new_looking="$(echo "$current_looking" | tr '\n' ',' | sed 's/,$//')"
    fi

    # 生成新的 YAML
    local updated_at
    updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    # 读取公钥
    local public_key=""
    if [ -f "${OCFR_DIR}/keys/public.pem" ]; then
        public_key=$(cat "${OCFR_DIR}/keys/public.pem" | sed 's/^/  /')
    fi

    # 格式化 interests 为 YAML 列表
    local interests_yaml=""
    if [[ -n "$new_interests" ]]; then
        IFS=',' read -ra interest_array <<< "$new_interests"
        for item in "${interest_array[@]}"; do
            item=$(echo "$item" | xargs)  # trim
            [[ -n "$item" ]] && interests_yaml+="  - ${item}"$'\n'
        done
    fi
    [[ -z "$interests_yaml" ]] && interests_yaml="  []"$'\n'

    # 格式化 skills 为 YAML 列表
    local skills_yaml=""
    if [[ -n "$new_skills" ]]; then
        IFS=',' read -ra skill_array <<< "$new_skills"
        for item in "${skill_array[@]}"; do
            item=$(echo "$item" | xargs)
            [[ -n "$item" ]] && skills_yaml+="  - ${item}"$'\n'
        done
    fi
    [[ -z "$skills_yaml" ]] && skills_yaml="  []"$'\n'

    # 格式化 looking_for 为 YAML 列表
    local looking_yaml=""
    if [[ -n "$new_looking" ]]; then
        IFS=',' read -ra looking_array <<< "$new_looking"
        for item in "${looking_array[@]}"; do
            item=$(echo "$item" | xargs)
            [[ -n "$item" ]] && looking_yaml+="  - ${item}"$'\n'
        done
    fi
    [[ -z "$looking_yaml" ]] && looking_yaml="  []"$'\n'

    # 写入文件
    cat > "${profile}" <<EOF
username: "${username}"
display_name: "${new_display}"
github: "${username}"
avatar_url: "https://github.com/${username}.png"
bio: "${new_bio}"
interests:
${interests_yaml}skills:
${skills_yaml}looking_for:
${looking_yaml}platforms:
  []
public_key: |
${public_key}updated_at: "${updated_at}"

# Auto-negotiation fields
ideal_type:
  preferred_interests:
    []
  preferred_skills:
    []
  personality_traits:
    []
  deal_breakers:
    []
  description: ""
agreement_accepted: $(grep '^agreement_accepted:' "${profile}" | awk '{print $2}' || echo "false")
agreement_accepted_at: "$(grep '^agreement_accepted_at:' "${profile}" | sed 's/^agreement_accepted_at: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' || echo "")"
is_seed: false
EOF

    success "Profile 已更新"

    # Sync push
    echo ""
    info "正在同步到远程仓库..."
    bash "${SCRIPT_DIR}/sync.sh" push 2>/dev/null || {
        warn "推送失败，请手动运行 /friends sync"
    }

    echo ""
    echo "更新后的 profile:"
    show_profile_card "${profile}" "true"
}

# 查看指定用户的 profile
view_profile() {
    local target="$1"

    if [[ -z "$target" ]]; then
        error "请指定用户名"
        exit 1
    fi

    # Sync pull
    info "同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull 2>/dev/null || warn "同步失败"

    local profile="${REPO_DIR}/profiles/${target}.yaml"

    if [[ ! -f "${profile}" ]]; then
        error "用户 '${target}' 不存在"
        exit 1
    fi

    # 检查是否是种子用户
    if grep -q 'is_seed: true' "${profile}"; then
        warn "这是一个示例 profile，仅供演示"
    fi

    show_profile_card "${profile}" "false"
}

# 计算 profile 完整度
calculate_completeness() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [[ ! -f "${profile}" ]]; then
        echo "0"
        return
    fi

    local score=0

    # display_name: 10%
    grep -q '^display_name:' "${profile}" && score=$((score + 10))

    # bio: 15%
    local bio
    bio=$(grep '^bio:' "${profile}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    [[ -n "$bio" && "$bio" != "null" ]] && score=$((score + 15))

    # interests: 25% (每项 5%, 最高 25%)
    local interests_count
    interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
    local interest_score=$((interests_count * 5))
    [[ $interest_score -gt 25 ]] && interest_score=25
    score=$((score + interest_score))

    # skills: 25% (每项 5%, 最高 25%)
    local skills_count
    skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
    local skill_score=$((skills_count * 5))
    [[ $skill_score -gt 25 ]] && skill_score=25
    score=$((score + skill_score))

    # looking_for: 10%
    local looking_count
    looking_count=$(awk '/^looking_for:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
    [[ $looking_count -gt 0 ]] && score=$((score + 10))

    # ideal_type: 15%
    local ideal_count=0
    grep -q 'preferred_interests:' "${profile}" && ideal_count=$((ideal_count + 1))
    grep -q 'preferred_skills:' "${profile}" && ideal_count=$((ideal_count + 1))
    grep -q 'personality_traits:' "${profile}" && ideal_count=$((ideal_count + 1))
    grep -q 'deal_breakers:' "${profile}" && ideal_count=$((ideal_count + 1))
    grep -q 'description:' "${profile}" && ideal_count=$((ideal_count + 1))
    score=$((score + ideal_count * 3))

    echo "$score"
}

# --- Main ---

usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  view          View your own profile"
    echo "  edit          Edit your profile interactively"
    echo "  view <user>   View another user's profile"
    echo "  completeness  Show profile completeness score"
    exit 1
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    # 检查初始化
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "未初始化，请先运行 /friends init"
        exit 1
    fi

    # 检查 repo
    if [[ ! -d "${REPO_DIR}/.git" ]]; then
        error "repo 未克隆，请先运行 /friends init"
        exit 1
    fi

    case "$1" in
        view)
            if [[ -n "${2:-}" ]]; then
                view_profile "$2"
            else
                local username
                username=$(get_username)
                local profile="${REPO_DIR}/profiles/${username}.yaml"
                show_profile_card "${profile}" "true"
            fi
            ;;
        edit)
            edit_profile
            ;;
        completeness)
            local score
            score=$(calculate_completeness)
            echo "Profile 完整度：${score}%"
            ;;
        *)
            usage
            ;;
    esac
}

main "$@"
