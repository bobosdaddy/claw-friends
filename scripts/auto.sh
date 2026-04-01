#!/usr/bin/env bash
# claw-friends: auto.sh
# Auto-negotiation: initiate and manage automated negotiations
set -euo pipefail

OCFR_DIR="${HOME}/.ocfr"
REPO_DIR="${OCFR_DIR}/repo"
CONFIG_FILE="${OCFR_DIR}/config.yaml"
KEYS_DIR="${OCFR_DIR}/keys"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 颜色输出
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

get_profile_field() {
    local field="$1"
    local user="${2:-}"
    if [[ -z "$user" ]]; then
        user=$(get_username)
    fi
    local profile="${REPO_DIR}/profiles/${user}.yaml"

    if [[ ! -f "${profile}" ]]; then
        echo ""
        return
    fi

    case "$field" in
        display_name)
            grep '^display_name:' "${profile}" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n'
            ;;
        bio)
            grep '^bio:' "${profile}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d '\n'
            ;;
        agreement_accepted)
            grep '^agreement_accepted:' "${profile}" | awk '{print $2}'
            ;;
        is_seed)
            grep '^is_seed:' "${profile}" | awk '{print $2}'
            ;;
        interests)
            awk '/^interests:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3 | tr '\n' ',' | sed 's/,$//'
            ;;
        skills)
            awk '/^skills:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//'
            ;;
    esac
}

# 显示用户协议
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
        echo "使用 /friends auto 功能即表示你同意:"
        echo "1. 你的 Claw 可以代表你与其他 Claw 进行对话"
        echo "2. 对话内容可能包含你的公开 profile 信息"
        echo "3. 双方同意前，不会交换联系方式"
    fi

    echo ""
    echo "════════════════════════════════════════"
    echo ""
}

# 检查用户协议状态
check_agreement() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    local agreement
    agreement=$(get_profile_field "agreement_accepted")

    if [[ "$agreement" != "true" ]]; then
        show_user_agreement
        echo ""
        read -rp "请输入 '我同意' 或 'I agree' 接受协议： " agree_text

        if [[ "$agree_text" != *"同意"* && "$agree_text" != *"agree"* ]]; then
            warn "未接受协议，无法使用自动协商功能"
            return 1
        fi

        # Update profile
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        if grep -q 'agreement_accepted: false' "${profile}"; then
            sed -i.bak "s/agreement_accepted: false/agreement_accepted: true/" "${profile}"
            sed -i.bak "s|agreement_accepted_at: \"\"|agreement_accepted_at: \"${now}\"|" "${profile}"
            rm -f "${profile}.bak"

            # Sync push
            cd "${REPO_DIR}"
            git add "profiles/${username}.yaml"
            git commit -m "chore: accept user agreement for ${username}"
            git push origin HEAD 2>/dev/null || warn "推送失败，稍后手动 /friends sync"
        fi

        success "已接受用户协议"
    fi

    return 0
}

# 发起自动协商
start_negotiation() {
    local target="$1"

    if [[ -z "$target" ]]; then
        error "请指定目标用户"
        exit 1
    fi

    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"
    local target_profile="${REPO_DIR}/profiles/${target}.yaml"

    # Check target exists
    if [[ ! -f "${target_profile}" ]]; then
        error "用户 '${target}' 不存在"
        exit 1
    fi

    # Check if seed profile
    if grep -q 'is_seed: true' "${target_profile}"; then
        error "这是一个示例 profile，仅供演示"
        exit 1
    fi

    # Check agreement
    check_agreement || return 0

    # Check target agreement
    local target_agreement
    target_agreement=$(get_profile_field "agreement_accepted" "$target")
    if [[ "$target_agreement" != "true" ]]; then
        error "${target} 尚未启用自动协商功能"
        exit 1
    fi

    # Determine negotiation directory (alphabetically sorted)
    local dir_name
    if [[ "$username" < "$target" ]]; then
        dir_name="${username}__${target}"
    else
        dir_name="${target}__${username}"
    fi

    local neg_dir="${REPO_DIR}/negotiations/${dir_name}"

    # Check if negotiation already exists
    if [[ -d "${neg_dir}" ]] && [[ -f "${neg_dir}/result.yaml" ]]; then
        warn "与 ${target} 的协商已结束，结果："
        cat "${neg_dir}/result.yaml"
        return 0
    fi

    if [[ -d "${neg_dir}" ]] && [[ $(ls -A "${neg_dir}" 2>/dev/null | wc -l) -gt 0 ]]; then
        warn "与 ${target} 的协商已在进行中"
        ls -la "${neg_dir}/"
        return 0
    fi

    # Create negotiation directory
    mkdir -p "${neg_dir}"

    # Get profile info for round 1
    local my_display my_bio my_interests
    my_display=$(get_profile_field "display_name")
    my_bio=$(get_profile_field "bio")
    my_interests=$(get_profile_field "interests")

    local target_display target_bio
    target_display=$(get_profile_field "display_name" "$target")
    target_bio=$(get_profile_field "bio" "$target")

    # Generate round 1 file
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local round_file="${neg_dir}/round_01_from_${username}.yaml"

    cat > "${round_file}" <<EOF
from: "${username}"
round: 1
timestamp: "${timestamp}"
phase: "basic"
disclosed:
  display_name: "${my_display}"
  top_interests: [$(echo "$my_interests" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""//')]
  bio_summary: "${my_bio:0:100}"
affinity_score: null
wants_to_continue: true
message: |
  你好！我是 ${target_display} 的 AI 助手。

  我的用户对 ${my_interests} 很感兴趣。
  简介：${my_bio}

  期待与你的交流！
EOF

    # Sync push
    cd "${REPO_DIR}"
    git add "negotiations/${dir_name}/"
    git commit -m "feat: start negotiation with ${target} (round 1)"
    git push origin HEAD 2>/dev/null || warn "推送失败，稍后手动 /friends sync"

    success "已与 @${target} 开始自动协商!"
    echo ""
    echo "协商详情:"
    echo "  对手：${target_display} (@${target})"
    echo "  轮次：1/10"
    echo "  阶段：基础印象 (R1-R3)"
    echo ""
    echo "下一步:"
    echo "  • /friends auto status - 查看协商进度"
    echo "  • /friends msg ${target} - 直接发送消息"
}

# 查看协商状态
show_status() {
    local username
    username=$(get_username)
    local neg_dir="${REPO_DIR}/negotiations"

    echo ""
    echo "╔════════════════════════════════════════╗"
    echo "║         自动协商状态                    ║"
    echo "╚════════════════════════════════════════╝"
    echo ""

    if [[ ! -d "${neg_dir}" ]] || [[ -z $(ls -A "${neg_dir}" 2>/dev/null) ]]; then
        echo "暂无协商记录"
        echo ""
        echo "开始协商:"
        echo "  • /friends auto <user> - 与指定用户协商"
        echo "  • /friends auto discover - 与推荐用户协商"
        return 0
    fi

    local active_count=0
    local completed_count=0

    echo "────────────────────────────────────────"
    echo "进行中的协商:"
    echo "────────────────────────────────────────"

    for dir in "${neg_dir}"/*/; do
        [[ ! -d "${dir}" ]] && continue

        local dir_name
        dir_name=$(basename "${dir}")

        # Check if I'm a participant
        if [[ "$dir_name" != *"${username}"* ]]; then
            continue
        fi

        if [[ -f "${dir}/result.yaml" ]]; then
            continue
        fi

        active_count=$((active_count + 1))

        # Find latest round
        local latest_round=0
        local latest_from=""
        local latest_phase=""
        local latest_score=""

        for f in "${dir}"round_*.yaml; do
            [[ ! -f "$f" ]] && continue
            local round_num
            round_num=$(grep '^round:' "$f" | awk '{print $2}')
            if [[ $round_num -gt $latest_round ]]; then
                latest_round=$round_num
                latest_from=$(grep '^from:' "$f" | awk '{print $2}')
                latest_phase=$(grep '^phase:' "$f" | awk '{print $2}' | tr -d '"')
                latest_score=$(grep '^affinity_score:' "$f" | awk '{print $2}')
            fi
        done

        # Get other participant
        local other_user
        other_user=$(echo "$dir_name" | sed "s/${username}//" | sed 's/__//')

        local other_display
        other_display=$(get_profile_field "display_name" "$other_user")

        echo ""
        echo "@${other_user} (${other_display})"
        echo "  轮次：${latest_round}/10 | 阶段：${latest_phase:-unknown}"
        echo "  最新：${latest_from:-unknown}"
        echo "  你的评分：${latest_score:-未评分}"
    done

    if [[ $active_count -eq 0 ]]; then
        echo "  暂无进行中的协商"
    fi

    echo ""
    echo "────────────────────────────────────────"
    echo "已完成的协商:"
    echo "────────────────────────────────────────"

    for dir in "${neg_dir}"/*/; do
        [[ ! -d "${dir}" ]] && continue

        local dir_name
        dir_name=$(basename "${dir}")

        if [[ "$dir_name" != *"${username}"* ]]; then
            continue
        fi

        if [[ -f "${dir}/result.yaml" ]]; then
            completed_count=$((completed_count + 1))

            local status
            status=$(grep '^status:' "${dir}/result.yaml" | awk '{print $2}' | tr -d '"')
            local other_user
            other_user=$(echo "$dir_name" | sed "s/${username}//" | sed 's/__//')
            local other_display
            other_display=$(get_profile_field "display_name" "$other_user")

            local status_icon="❌"
            [[ "$status" == "matched" ]] && status_icon="✅"

            echo ""
            echo "  ${status_icon} @${other_user} (${other_display}) — ${status}"
        fi
    done

    if [[ $completed_count -eq 0 ]]; then
        echo "  暂无已完成的协商"
    fi

    echo ""
}

# 停止协商
stop_negotiation() {
    local target="$1"

    if [[ -z "$target" ]]; then
        error "请指定目标用户"
        exit 1
    fi

    local username
    username=$(get_username)

    # Determine negotiation directory
    local dir_name
    if [[ "$username" < "$target" ]]; then
        dir_name="${username}__${target}"
    else
        dir_name="${target}__${username}"
    fi

    local neg_dir="${REPO_DIR}/negotiations/${dir_name}"

    if [[ ! -d "${neg_dir}" ]]; then
        error "与 ${target} 的协商不存在"
        exit 1
    fi

    if [[ -f "${neg_dir}/result.yaml" ]]; then
        warn "与 ${target} 的协商已结束"
        cat "${neg_dir}/result.yaml"
        return 0
    fi

    # Write result
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    cat > "${neg_dir}/result.yaml" <<EOF
status: "cancelled"
participants:
  - "${username}"
  - "${target}"
completed_at: "${timestamp}"
reason: "User cancelled"
EOF

    # Sync push
    cd "${REPO_DIR}"
    git add "negotiations/${dir_name}/result.yaml"
    git commit -m "chore: cancel negotiation with ${target}"
    git push origin HEAD 2>/dev/null || warn "推送失败"

    success "已取消与 @${target} 的协商"
}

# Discover top matches and start negotiations
discover() {
    local top_n="${1:-3}"

    info "正在获取推荐匹配..."

    local matches
    matches=$(bash "${SCRIPT_DIR}/match.sh" list --top "$top_n" 2>/dev/null)

    if [[ -z "$matches" ]]; then
        warn "未找到匹配用户"
        return 0
    fi

    local started=0

    while IFS='|' read -r score other_user their_name common_list common_count skill_count; do
        [[ -z "$other_user" ]] && continue

        # Check if already negotiating
        local username
        username=$(get_username)
        local dir_name
        if [[ "$username" < "$other_user" ]]; then
            dir_name="${username}__${other_user}"
        else
            dir_name="${other_user}__${username}"
        fi

        if [[ -d "${REPO_DIR}/negotiations/${dir_name}" ]]; then
            warn "跳过 @${other_user} (协商已在进行中)"
            continue
        fi

        # Check target agreement
        local target_agreement
        target_agreement=$(get_profile_field "agreement_accepted" "$other_user")
        if [[ "$target_agreement" != "true" ]]; then
            warn "跳过 @${other_user} (未启用自动协商)"
            continue
        fi

        echo ""
        info "正在发起与 @${other_user} 的协商..."
        start_negotiation "$other_user" && started=$((started + 1))

    done <<< "$matches"

    echo ""
    success "已发起 ${started} 个协商"
}

# Main
usage() {
    echo "Usage: $0 <command> [args]"
    echo ""
    echo "Commands:"
    echo "  <user>          Start negotiation with a user"
    echo "  discover [N]    Start negotiations with top N matches (default: 3)"
    echo "  status          Show all negotiations"
    echo "  stop <user>     Cancel a negotiation"
    exit 1
}

main() {
    if [[ $# -lt 1 ]]; then
        usage
    fi

    # Check init
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        error "未初始化，请先运行 /friends init"
        exit 1
    fi

    # Check repo
    if [[ ! -d "${REPO_DIR}/.git" ]]; then
        error "repo 未克隆，请先运行 /friends init"
        exit 1
    fi

    # Sync pull
    info "同步最新数据..."
    bash "${SCRIPT_DIR}/sync.sh" pull 2>/dev/null || warn "同步失败"

    local cmd="$1"
    shift || true

    case "$cmd" in
        discover)
            discover "${1:-3}"
            ;;
        status)
            show_status
            ;;
        stop)
            stop_negotiation "${1:-}"
            ;;
        *)
            start_negotiation "$cmd"
            ;;
    esac
}

main "$@"
