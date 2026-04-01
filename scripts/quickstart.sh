#!/usr/bin/env bash
# claw-friends: quickstart.sh
# Quick Start引导流程：一键式新用户引导，3 步完成首次匹配
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
KEYS_DIR="${OCFR_DIR}/keys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# --- 工具函数 ---

# 从 config.yaml 获取 username
get_username() {
    if [ ! -f "${CONFIG_FILE}" ]; then
        error "未初始化。请先运行 /friends init"
        exit 1
    fi
    grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' '
}

# 读取 profile 字段
get_profile_field() {
    local field="$1"
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "${profile}" ]; then
        echo ""
        return
    fi

    # 简单 YAML 解析
    case "$field" in
        display_name)
            grep '^display_name:' "${profile}" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n'
            ;;
        bio)
            grep '^bio:' "${profile}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n'
            ;;
        interests)
            awk '/^interests:$/,/^[a-z_]+:/' "${profile}" | grep '^ *-' | sed 's/^ *- *//' | tr -d '\n' | tr '\n' ','
            ;;
        skills)
            awk '/^skills:$/,/^[a-z_]+:/' "${profile}" | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//'
            ;;
        agreement_accepted)
            grep '^agreement_accepted:' "${profile}" | awk '{print $2}'
            ;;
        is_seed)
            grep '^is_seed:' "${profile}" | awk '{print $2}'
            ;;
    esac
}

# 计算 profile 完整度 (0-100)
calculate_profile_completeness() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "${profile}" ]; then
        echo "0"
        return
    fi

    local score=0

    # display_name: 10%
    local display_name
    display_name=$(get_profile_field "display_name")
    [[ -n "$display_name" ]] && score=$((score + 10))

    # bio: 15%
    local bio
    bio=$(get_profile_field "bio")
    [[ -n "$bio" && "$bio" != "null" ]] && score=$((score + 15))

    # interests: 25% (每项 5%, 最高 25%)
    local interests_count=0
    if grep -q '^interests:' "${profile}"; then
        interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
    fi
    local interest_score=$((interests_count * 5))
    [[ $interest_score -gt 25 ]] && interest_score=25
    score=$((score + interest_score))

    # skills: 25% (每项 5%, 最高 25%)
    local skills_count=0
    if grep -q '^skills:' "${profile}"; then
        skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
    fi
    local skill_score=$((skills_count * 5))
    [[ $skill_score -gt 25 ]] && skill_score=25
    score=$((score + skill_score))

    # looking_for: 10%
    if grep -q '^looking_for:' "${profile}"; then
        local looking_count
        looking_count=$(awk '/^looking_for:$/,/^[a-z_]+:/' "${profile}" | grep -c '^ *-' || echo 0)
        [[ $looking_count -gt 0 ]] && score=$((score + 10))
    fi

    # ideal_type: 15% (每子项 3%)
    if grep -q '^ideal_type:' "${profile}"; then
        local ideal_subfields=0
        grep -q 'preferred_interests:' "${profile}" && ideal_subfields=$((ideal_subfields + 1))
        grep -q 'preferred_skills:' "${profile}" && ideal_subfields=$((ideal_subfields + 1))
        grep -q 'personality_traits:' "${profile}" && ideal_subfields=$((ideal_subfields + 1))
        grep -q 'deal_breakers:' "${profile}" && ideal_subfields=$((ideal_subfields + 1))
        grep -q 'description:' "${profile}" && ideal_subfields=$((ideal_subfields + 1))
        local ideal_score=$((ideal_subfields * 3))
        score=$((score + ideal_score))
    fi

    echo "$score"
}

# --- GitHub 资料增强 ---

# 从 GitHub API 推断兴趣和技能
enhance_from_github() {
    info "正在分析你的 GitHub 资料..."

    local username
    username=$(get_username)

    # 使用 GraphQL 批量获取数据
    local graphql_response
    graphql_response=$(gh api graphql -f query='
      query($user: String!) {
        user(login: $user) {
          name
          bio
          company
          location
          repositories(first: 100, ownership: OWNER, orderBy: {field: PUSHED_AT, direction: DESC}) {
            nodes {
              name
              primaryLanguage { name }
              topics { nodes { name } }
              stargazerCount
            }
          }
          starredRepositories(first: 100) {
            nodes {
              primaryLanguage { name }
              topics { nodes { name } }
            }
          }
          contributionsCollection {
            contributionCalendar {
              totalContributions
            }
          }
        }
      }
    ' -F user="$username" 2>/dev/null) || {
        warn "GitHub API 调用失败，跳过增强"
        return 1
    }

    # 解析语言分布
    local languages
    languages=$(echo "$graphql_response" | jq -r '
      .data.user.repositories.nodes
      | map(select(.primaryLanguage != null))
      | group_by(.primaryLanguage.name)
      | map({name: .[0].primaryLanguage.name, count: length})
      | sort_by(-.count)
      | .[0:5]
      | .[].name
    ' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    # 解析主题
    local topics
    topics=$(echo "$graphql_response" | jq -r '
      [.data.user.repositories.nodes[].topics.nodes[].name,
       .data.user.starredRepositories.nodes[].topics.nodes[].name]
      | flatten
      | group_by(.)
      | map({name: .[0], count: length})
      | sort_by(-.count)
      | .[0:5]
      | .[].name
    ' 2>/dev/null | tr '\n' ',' | sed 's/,$//')

    # 合并推荐
    local recommendations=()

    if [[ -n "$languages" ]]; then
        IFS=',' read -ra lang_array <<< "$languages"
        for lang in "${lang_array[@]:0:3}"; do
            [[ -n "$lang" && "$lang" != "null" ]] && recommendations+=("$lang")
        done
    fi

    if [[ -n "$topics" ]]; then
        IFS=',' read -ra topic_array <<< "$topics"
        for topic in "${topic_array[@]:0:2}"; do
            [[ -n "$topic" && "$topic" != "null" ]] && recommendations+=("$topic")
        done
    fi

    # 显示推荐
    echo ""
    echo "根据你的 GitHub 仓库和 Star，推荐添加以下标签:"
    echo ""

    if [[ ${#recommendations[@]} -eq 0 ]]; then
        warn "未能推断出足够标签，建议手动补充"
        return 1
    fi

    echo "  技能/语言:"
    for i in "${!recommendations[@]}"; do
        echo "    ✓ ${recommendations[$i]}"
    done
    echo ""

    # 返回推荐列表 (逗号分隔)
    printf '%s\n' "${recommendations[@]}" | tr '\n' ',' | sed 's/,$//'
}

# --- 匹配功能 ---

# 获取 Top N 匹配用户 (调用 match.sh)
get_top_matches() {
    local top_n="${1:-3}"
    bash "${SCRIPT_DIR}/match.sh" list --top "$top_n" 2>/dev/null
}

# --- 用户协议 ---

show_user_agreement() {
    local agreement_template="${SCRIPT_DIR}/../templates/user_agreement.md"

    echo ""
    echo "════════════════════════════════════════"
    echo "          Claw Friends 用户协议"
    echo "════════════════════════════════════════"
    echo ""

    if [[ -f "$agreement_template" ]]; then
        cat "$agreement_template"
    else
        cat <<'EOF'
## 自动协商条款

使用 `/friends quickstart` 或 `/friends auto` 功能即表示你同意:

1. 你的 Claw 可以代表你与其他 Claw 进行对话
2. 对话内容可能包含你的公开 profile 信息
3. 双方同意前，不会交换联系方式

## 数据使用条款

- GitHub 数据仅用于 profile 增强
- 推断标签可随时手动修改
- 所有数据存储在本地 + 你控制的 GitHub repo

## 隐私保护

- 私钥永远不离开你的设备
- 消息使用 RSA+AES 端到端加密
- 种子用户为示例数据，不参与真实匹配
EOF
    fi

    echo ""
    echo "════════════════════════════════════════"
    echo ""
}

# --- 主流程 ---

run_quickstart() {
    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║   🚀 Claw Friends 快速开始引导          ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    # 步骤 1: 检查 profile 完整度
    echo "步骤 1/4: 检查资料完整度..."
    local score
    score=$(calculate_profile_completeness)

    if [[ $score -lt 30 ]]; then
        warn "Profile 完整度仅 ${score}%"
        echo ""
        echo "建议先完善资料，否则匹配质量会很差。"
        echo ""
        read -rp "是否现在编辑 profile? [Y/n] " ans
        if [[ "$ans" != "n" && "$ans" != "N" ]]; then
            bash "${SCRIPT_DIR}/profile.sh" edit 2>/dev/null || {
                info "编辑功能暂时不可用，继续引导流程..."
            }
        fi

        # 重新计算
        score=$(calculate_profile_completeness)
    fi

    success "Profile 完整度：${score}%"
    echo ""

    # 步骤 2: 检查用户协议
    echo "步骤 2/4: 检查用户协议..."
    local agreement
    agreement=$(get_profile_field "agreement_accepted")

    if [[ "$agreement" != "true" ]]; then
        show_user_agreement
        read -rp "请输入 '我同意' 或 'I agree' 接受协议: " agree_text
        if [[ "$agree_text" != *"同意"* && "$agree_text" != *"agree"* ]]; then
            warn "未接受协议，无法继续使用自动协商功能"
            echo ""
            echo "你可以使用以下功能:"
            echo "  • /friends explore - 浏览社区"
            echo "  • /friends profile edit - 编辑资料"
            return 0
        fi

        # 更新 profile
        local username
        username=$(get_username)
        local profile="${REPO_DIR}/profiles/${username}.yaml"
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        # 使用 sed 更新
        if grep -q 'agreement_accepted: false' "${profile}"; then
            sed -i.bak "s/agreement_accepted: false/agreement_accepted: true/" "${profile}"
            sed -i.bak "s|agreement_accepted_at: \"\"|agreement_accepted_at: \"${now}\"|" "${profile}"
            rm -f "${profile}.bak"

            # 提交并推送
            cd "${REPO_DIR}"
            git add "profiles/${username}.yaml"
            git commit -m "chore: accept user agreement for ${username}"
            git push origin HEAD 2>/dev/null || warn "推送失败，稍后手动 /friends sync"
        fi

        success "已接受用户协议"
    else
        success "用户协议已接受"
    fi
    echo ""

    # 步骤 3: GitHub 资料增强 (可选)
    echo "步骤 3/4: GitHub 资料增强..."
    local username
    username=$(get_username)
    local current_interests
    current_interests=$(awk '/^interests:$/,/^[a-z_]+:/' "${REPO_DIR}/profiles/${username}.yaml" 2>/dev/null | grep -c '^ *-' || echo 0)
    local current_skills
    current_skills=$(awk '/^skills:$/,/^[a-z_]+:/' "${REPO_DIR}/profiles/${username}.yaml" 2>/dev/null | grep -c '^ *-' || echo 0)

    if [[ $current_interests -lt 3 || $current_skills -lt 3 ]]; then
        info "检测到兴趣/技能较少，可以从 GitHub 推断"
        echo ""
        read -rp "是否从 GitHub 仓库推断标签？[Y/n] " enhance_ans
        if [[ "$enhance_ans" != "n" && "$enhance_ans" != "N" ]]; then
            local enhanced
            enhanced=$(enhance_from_github)
            if [[ -n "$enhanced" ]]; then
                success "推断完成：${enhanced}"
                # TODO: 实际更新 profile
            fi
        fi
    else
        info "资料已足够丰富，跳过增强"
    fi
    echo ""

    # 步骤 4: 运行匹配算法
    echo "步骤 4/4: 运行匹配算法..."
    info "正在分析社区成员..."

    local matches
    matches=$(get_top_matches 5)

    if [[ -z "$matches" ]]; then
        warn "未找到匹配用户"
        echo ""
        echo "可能原因:"
        echo "  1. 社区还在成长中 (当前用户较少)"
        echo "  2. 你的标签太少，试试 /friends profile edit"
        echo ""
        return 0
    fi

    # 显示 Top 3
    echo ""
    echo "为你找到以下匹配:"
    echo "────────────────────────────────────────"

    local count=0
    local selections=()

    while IFS='|' read -r score other_user their_name common_list common_count skill_count; do
        count=$((count + 1))
        [[ $count -gt 3 ]] && break

        selections+=("$other_user")

        echo ""
        echo "${count}. @${other_user} (${their_name}) — 匹配度 ${score}分"
        echo "   共同兴趣：${common_list:-无}"
        echo "   技能互补：${skill_count} 项他们有你没有的技能"
        echo ""
    done <<< "$matches"

    echo "────────────────────────────────────────"
    echo ""

    # 用户选择
    read -rp "想和谁聊聊？(输入 1-${count} 或 s 跳过): " choice

    if [[ "$choice" =~ ^[1-3]$ ]] && [[ $choice -le $count ]]; then
        local target_idx=$((choice - 1))
        local target="${selections[$target_idx]}"

        echo ""
        info "正在发起与 @${target} 的自动协商..."

        # 调用 auto 命令
        # 注意：这里应该调用 skill 的 auto 逻辑，但为了简化直接创建 negotiation
        bash "${SCRIPT_DIR}/auto.sh" "$target" 2>/dev/null || {
            warn "auto 功能暂时不可用，你可以手动运行 /friends auto ${target}"
        }

        success "已完成快速开始!"
        echo ""
        echo "下一步:"
        echo "  • /friends auto status - 查看协商进度"
        echo "  • /friends explore - 浏览更多社区成员"
        echo "  • /friends - 查看完整命令列表"
    else
        info "已跳过，你可以稍后手动运行 /friends auto <user>"
    fi

    echo ""
    success "快速开始完成!"
}

# --- 主程序 ---

main() {
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

    # sync pull
    info "同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull 2>/dev/null || warn "同步失败，继续..."

    run_quickstart
}

main "$@"
