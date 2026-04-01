#!/usr/bin/env bash
# claw-friends: auto.sh (UX Enhanced)
# Auto-negotiation with visual progress cards
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
TEMPLATE_DIR="${SCRIPT_DIR}/../templates"

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
            grep '^display_name:' "${profile}" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1
            ;;
        bio)
            grep '^bio:' "${profile}" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1
            ;;
        agreement_accepted)
            grep '^agreement_accepted:' "${profile}" | awk '{print $2}' | tr -d '"'
            ;;
        is_seed)
            grep '^is_seed:' "${profile}" | awk '{print $2}' | tr -d '"'
            ;;
        interests)
            awk '/^interests:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | head -3 | tr '\n' ',' | sed 's/,$//'
            ;;
        skills)
            awk '/^skills:$/,/^[a-z_]+:/' "${profile}" 2>/dev/null | grep '^ *-' | sed 's/^ *- *//' | tr '\n' ',' | sed 's/,$//'
            ;;
        *)
            echo ""
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# User Agreement
# ─────────────────────────────────────────────────────────────

show_user_agreement() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║          Claw Friends 用户协议                       ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    local agreement_file="${TEMPLATE_DIR}/user_agreement.md"
    if [[ -f "$agreement_file" ]]; then
        cat "$agreement_file"
    else
        echo "使用 /friends auto 功能即表示你同意:"
        echo "1. 你的 Claw 可以代表你与其他 Claw 进行对话"
        echo "2. 对话内容可能包含你的公开 profile 信息"
        echo "3. 双方同意前，不会交换联系方式"
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

check_agreement() {
    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"

    local agreement
    agreement=$(get_profile_field "agreement_accepted")

    if [[ "$agreement" != "true" ]]; then
        show_user_agreement
        echo "请输入 '我同意' 或 'I agree' 接受协议"
        echo -n "> "
        read -r agree_text

        if [[ "$agree_text" != *"同意"* && "$agree_text" != *"agree"* ]]; then
            echo ""
            echo -e "${YELLOW}⚠️  未接受协议，无法使用自动协商功能${NC}"
            echo ""
            echo "你仍可以使用其他功能:"
            echo "  /friends explore  — 浏览社区"
            echo "  /friends match    — 获取推荐"
            echo "  /friends request  — 发送好友请求"
            echo ""
            return 1
        fi

        # Update profile
        local now
        now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

        if grep -q 'agreement_accepted: false' "${profile}"; then
            sed -i.bak "s/agreement_accepted: false/agreement_accepted: true/" "${profile}"
            sed -i.bak "s|agreement_accepted_at: \"\"|agreement_accepted_at: \"${now}\"|" "${profile}"
            rm -f "${profile}.bak"

            # Sync
            cd "${REPO_DIR}"
            git add "profiles/${username}.yaml"
            git commit -m "chore: accept user agreement for ${username}" >/dev/null 2>&1 || true
            git push origin HEAD 2>/dev/null || true
        fi

        echo ""
        echo -e "${GREEN}✓ 已接受用户协议${NC}"
        echo ""
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────
# Start Negotiation
# ─────────────────────────────────────────────────────────────

start_negotiation() {
    local target="$1"

    if [[ -z "$target" ]]; then
        echo "用法：/friends auto <用户名>"
        exit 1
    fi

    local username
    username=$(get_username)
    local profile="${REPO_DIR}/profiles/${username}.yaml"
    local target_profile="${REPO_DIR}/profiles/${target}.yaml"

    # Check target exists
    if [[ ! -f "${target_profile}" ]]; then
        error_user_not_found "$target"
        exit 1
    fi

    # Check if seed profile
    if grep -q 'is_seed: true' "${target_profile}"; then
        error_seed_profile "$target"
        exit 1
    fi

    # Check agreement
    check_agreement || return 0

    # Check target agreement
    local target_agreement
    target_agreement=$(get_profile_field "agreement_accepted" "$target")
    if [[ "$target_agreement" != "true" ]]; then
        error_target_not_opted_in "$target"
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
        error_negotiation_ended "$target" "已结束"
        exit 1
    fi

    if [[ -d "${neg_dir}" ]] && [[ $(ls -A "${neg_dir}" 2>/dev/null | wc -l) -gt 0 ]]; then
        error_negotiation_exists "$target"
        exit 1
    fi

    # Create negotiation directory
    mkdir -p "${neg_dir}"

    # Get profile info for round 1
    local my_display my_bio my_interests
    my_display=$(get_profile_field "display_name")
    my_bio=$(get_profile_field "bio")
    my_interests=$(get_profile_field "interests")

    # Create round 1 file
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local round_file="${neg_dir}/round_01_from_${username}.yaml"

    # Generate bio summary (first 50 chars)
    local bio_summary="${my_bio:0:50}"
    if [ ${#my_bio} -gt 50 ]; then
        bio_summary="${bio_summary}..."
    fi

    # Get top 3 interests
    local top_interests
    top_interests=$(echo "$my_interests" | tr ',' '\n' | head -3 | tr '\n' ',' | sed 's/,$//')

    cat > "$round_file" <<EOF
from: "${username}"
round: 1
timestamp: "${timestamp}"
phase: "basic"
disclosed:
  display_name: "${my_display}"
  top_interests: [${top_interests}]
  bio_summary: "${bio_summary}"
affinity_score: null
wants_to_continue: true
message: "你好！我是 ${my_display} 的 AI 助手。我的主人对 ${top_interests} 很感兴趣，正在寻找有趣的交流和合作机会。期待了解更多关于你的信息！"
EOF

    # Sync
    echo ""
    echo -e "${BLUE}⟳${NC} 正在发起协商..."
    cd "${REPO_DIR}"
    git add "negotiations/" 2>/dev/null || true
    git commit -m "feat: start negotiation with ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🤖 自动协商已启动${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "与 @${target} 的协商已开始"
    echo ""
    echo "协商过程:"
    echo "  R1-R3: 基础印象 (兴趣、简介)"
    echo "  R4-R6: 深度了解 (技能、项目)"
    echo "  R7-R9: 个人偏好 (工作风格、时区)"
    echo "  R10:   友谊报告"
    echo ""
    echo "查看进度：/friends auto status"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# View Status
# ─────────────────────────────────────────────────────────────

view_status() {
    local username
    username=$(get_username)
    local negotiations_dir="${REPO_DIR}/negotiations"

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🤖 自动协商状态${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ ! -d "$negotiations_dir" ]] || [[ -z "$(ls -A "$negotiations_dir" 2>/dev/null)" ]]; then
        echo "暂无协商记录"
        echo ""
        echo "开始第一次协商:"
        echo -e "  ${CYAN}/friends auto <用户名>${NC}"
        echo -e "  ${CYAN}/friends auto discover${NC} — 自动发现匹配"
        echo ""
        return
    fi

    local active=()
    local completed=()

    for dir in "$negotiations_dir"/*/; do
        [[ ! -d "$dir" ]] && continue

        local dir_name
        dir_name=$(basename "$dir")

        # Check if user is participant
        if [[ "$dir_name" != *"$username"* ]]; then
            continue
        fi

        if [[ -f "${dir}result.yaml" ]]; then
            completed+=("$dir")
        else
            active+=("$dir")
        fi
    done

    # Show active
    if [[ ${#active[@]} -gt 0 ]]; then
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  ⏳ 进行中 (${#active[@]})"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""

        for dir in "${active[@]}"; do
            local dir_name
            dir_name=$(basename "$dir")

            # Find latest round
            local latest_round=0
            local latest_file=""
            for f in "$dir"/round_*.yaml; do
                [[ ! -f "$f" ]] && continue
                local round_num
                round_num=$(grep '^round:' "$f" | awk '{print $2}')
                if [[ "$round_num" -gt "$latest_round" ]]; then
                    latest_round="$round_num"
                    latest_file="$f"
                fi
            done

            # Get partner name
            local partner
            partner=$(echo "$dir_name" | sed "s/${username}__//" | sed "s/__${username}//")

            # Get phase
            local phase="basic"
            if [[ "$latest_round" -ge 4 ]] && [[ "$latest_round" -lt 7 ]]; then
                phase="detailed"
            elif [[ "$latest_round" -ge 7 ]]; then
                phase="personal"
            fi

            # Get scores
            local my_score="?"
            local their_score="?"
            if [[ -n "$latest_file" ]]; then
                my_score=$(grep '^affinity_score:' "$latest_file" 2>/dev/null | awk '{print $2}' | tr -d '"')
                my_score="${my_score:-null}"
                [[ "$my_score" = "null" ]] && my_score="?"
            fi

            # Get partner display name
            local partner_profile="${REPO_DIR}/profiles/${partner}.yaml"
            local partner_display="$partner"
            if [[ -f "$partner_profile" ]]; then
                partner_display=$(grep '^display_name:' "$partner_profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
            fi

            # Render card
            echo "┌─────────────────────────────────────────────────────────┐"
            printf "│ %-54s│\n" "@${partner} (${partner_display})"
            echo "│                                                         │"
            printf "│  进度：Round %-2d/10  阶段：%-20s│\n" "$latest_round" "$phase"
            printf "│  你的好感分：%-38s│\n" "${my_score}/100"
            echo "│                                                         │"
            printf "│  状态：%-46s│\n" "等待响应"
            echo "│                                                         │"
            echo "│  [v] 详情  [s] 停止                                     │"
            echo "└─────────────────────────────────────────────────────────┘"
            echo ""
        done
    fi

    # Show completed
    if [[ ${#completed[@]} -gt 0 ]]; then
        echo "┌─────────────────────────────────────────────────────────┐"
        echo "│  ✓ 已完成 (${#completed[@]})"
        echo "└─────────────────────────────────────────────────────────┘"
        echo ""

        for dir in "${completed[@]}"; do
            local dir_name
            dir_name=$(basename "$dir")
            local result_file="${dir}result.yaml"

            local status
            status=$(grep '^status:' "$result_file" | awk '{print $2}' | tr -d '"')

            local partner
            partner=$(echo "$dir_name" | sed "s/${username}__//" | sed "s/__${username}//")

            local partner_profile="${REPO_DIR}/profiles/${partner}.yaml"
            local partner_display="$partner"
            if [[ -f "$partner_profile" ]]; then
                partner_display=$(grep '^display_name:' "$partner_profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
            fi

            local status_emoji
            case "$status" in
                matched) status_emoji="🎉" ;;
                rejected) status_emoji="❌" ;;
                expired) status_emoji="⏰" ;;
                cancelled) status_emoji="🚫" ;;
                *) status_emoji="📋" ;;
            esac

            echo "  ${status_emoji} @${partner} (${partner_display}) — ${status}"

            if [[ "$status" = "matched" ]]; then
                echo "    → /friends report ${partner} 查看报告"
                echo "    → /friends connect ${partner} 交换联系方式"
            fi
        done
        echo ""
    fi
}

# ─────────────────────────────────────────────────────────────
# Stop Negotiation
# ─────────────────────────────────────────────────────────────

stop_negotiation() {
    local target="$1"

    if [[ -z "$target" ]]; then
        echo "用法：/friends auto stop <用户名>"
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

    if [[ ! -d "$neg_dir" ]]; then
        echo "未找到与 @${target} 的协商"
        exit 1
    fi

    # Create result file
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

    # Sync
    cd "${REPO_DIR}"
    git add "negotiations/" 2>/dev/null || true
    git commit -m "chore: cancel negotiation with ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    echo ""
    echo "已停止与 @${target} 的协商"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Auto Discover
# ─────────────────────────────────────────────────────────────

auto_discover() {
    echo ""
    echo "🔍 正在寻找最佳匹配..."
    echo ""

    # Check agreement
    check_agreement || return 0

    # Get matches (top 3)
    local matches
    matches=$(bash "${SCRIPT_DIR}/match.sh" --top 3 2>/dev/null)

    if [[ -z "$matches" ]]; then
        echo "暂未找到合适的匹配对象"
        echo ""
        echo "建议:"
        echo "  /friends profile enhance — 完善资料"
        echo "  /friends explore — 浏览社区"
        echo ""
        return
    fi

    local started=0

    echo "$matches" | head -3 | while IFS='|' read -r score user name common complement reason; do
        # Check if already negotiating
        local dir_name
        if [[ "$username" < "$user" ]]; then
            dir_name="${username}__${user}"
        else
            dir_name="${user}__${username}"
        fi

        if [[ -d "${REPO_DIR}/negotiations/${dir_name}" ]] && [[ ! -f "${REPO_DIR}/negotiations/${dir_name}/result.yaml" ]]; then
            echo "⏭️  跳过 @${user} — 协商已在进行中"
            continue
        fi

        # Check target agreement
        local target_agreement
        target_agreement=$(get_profile_field "agreement_accepted" "$user")
        if [[ "$target_agreement" != "true" ]]; then
            echo "⏭️  跳过 @${user} — 对方未启用自动协商"
            continue
        fi

        # Start negotiation
        echo "🚀 启动与 @${user} 的协商..."
        start_negotiation "$user"
        started=$((started + 1))
    done

    echo ""
    echo "查看进度：/friends auto status"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local action="${1:-status}"
    local target="${2:-}"

    case "$action" in
        start|s)
            start_negotiation "$target"
            ;;
        status|st|list|ls|"")
            view_status
            ;;
        stop|cancel)
            stop_negotiation "$target"
            ;;
        discover|auto|d)
            auto_discover
            ;;
        *)
            # If first arg looks like a username, start negotiation
            if [[ "$action" != "--"* ]] && [[ -n "$action" ]]; then
                start_negotiation "$action"
            else
                view_status
            fi
            ;;
    esac
}

main "$@"
