#!/usr/bin/env bash
# claw-friends: msg.sh (UX Enhanced)
# Send and view encrypted messages
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
KEYS_DIR="${OCFR_DIR}/keys"

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

check_friendship() {
    local user1="$1"
    local user2="$2"

    # Check both directions
    local req1="${REPO_DIR}/matches/${user2}/from_${user1}.yaml"
    local req2="${REPO_DIR}/matches/${user1}/from_${user2}.yaml"

    for req in "$req1" "$req2"; do
        if [ -f "$req" ]; then
            local status
            status=$(grep '^status:' "$req" 2>/dev/null | awk '{print $2}' | tr -d '"')
            if [ "$status" = "accepted" ]; then
                return 0
            fi
        fi
    done

    return 1
}

# ─────────────────────────────────────────────────────────────
# View Inbox
# ─────────────────────────────────────────────────────────────

view_inbox() {
    local username
    username=$(get_username)
    local messages_dir="${REPO_DIR}/messages/${username}"

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}📬 消息收件箱${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [ ! -d "$messages_dir" ] || [ -z "$(ls -A "$messages_dir" 2>/dev/null)" ]; then
        echo "收件箱为空"
        echo ""
        echo "有新消息时会显示在这里"
        echo ""
        return
    fi

    # Group by sender
    declare -A senders

    for f in "$messages_dir"/*.yaml; do
        [ ! -f "$f" ] && continue
        local from
        from=$(grep '^from:' "$f" | awk '{print $2}' | tr -d '"')
        if [ -n "$from" ]; then
            senders["$from"]=$((${senders["$from"]:-0} + 1))
        fi
    done

    if [ ${#senders[@]} -eq 0 ]; then
        echo "收件箱为空"
        return
    fi

    echo "┌─────────────────────────────────────────────────────────┐"
    for sender in "${!senders[@]}"; do
        local count=${senders[$sender]}
        local display_name="$sender"

        # Get display name
        local profile="${REPO_DIR}/profiles/${sender}.yaml"
        if [ -f "$profile" ]; then
            display_name=$(grep '^display_name:' "$profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
        fi

        # Get latest message preview
        local latest_file
        latest_file=$(ls -t "$messages_dir/from_${sender}_"*.yaml 2>/dev/null | head -1)
        local preview="..."
        if [ -n "$latest_file" ]; then
            # Try to decrypt for preview
            preview=$(bash "${SCRIPT_DIR}/crypto.sh" decrypt "$latest_file" 2>/dev/null | head -c 50 || echo "[加密消息]")
            if [ ${#preview} -gt 50 ]; then
                preview="${preview}..."
            fi
        fi

        printf "│  @%-20s  %-5s  %-25s│\n" "$sender" "[$count]" "$preview"
    done
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    echo "查看消息：/friends msg <用户名>"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# View Conversation
# ─────────────────────────────────────────────────────────────

view_conversation() {
    local target="$1"
    local username
    username=$(get_username)

    local my_messages="${REPO_DIR}/messages/${target}/from_${username}_*.yaml"
    local their_messages="${REPO_DIR}/messages/${username}/from_${target}_*.yaml"

    # Collect all messages
    local all_messages=()

    for f in $their_messages; do
        [ -f "$f" ] && all_messages+=("their:$f")
    done

    for f in $my_messages; do
        [ -f "$f" ] && all_messages+=("my:$f")
    done

    if [ ${#all_messages[@]} -eq 0 ]; then
        echo ""
        echo "暂无消息记录"
        echo ""
        echo "发送第一条消息：/friends msg ${target} \"你的消息\""
        echo ""
        return
    fi

    # Get target display name
    local target_profile="${REPO_DIR}/profiles/${target}.yaml"
    local target_display="$target"
    if [ -f "$target_profile" ]; then
        target_display=$(grep '^display_name:' "$target_profile" | sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | head -1)
    fi

    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  与 @${target} (${target_display}) 的对话"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""

    # Sort and display
    for item in "${all_messages[@]}"; do
        local type="${item%%:*}"
        local file="${item#*:}"

        local timestamp
        timestamp=$(grep '^timestamp:' "$file" | awk '{print $2}' | tr -d '"')

        local content
        if [ "$type" = "my" ]; then
            # Read from local sent cache
            local cache_file="${OCFR_DIR}/sent/${target}/$(basename "$file" .yaml).txt"
            if [ -f "$cache_file" ]; then
                content=$(cat "$cache_file")
            else
                content="[消息]"
            fi
            echo -e "  ${BLUE}你${NC} [${timestamp}]"
        else
            # Decrypt received message
            content=$(bash "${SCRIPT_DIR}/crypto.sh" decrypt "$file" 2>/dev/null || echo "[解密失败]")
            echo -e "  ${GREEN}${target_display}${NC} [${timestamp}]"
        fi

        # Word wrap content
        echo "$content" | fold -w 55 | while IFS= read -r line; do
            echo "    $line"
        done
        echo ""
    done
}

# ─────────────────────────────────────────────────────────────
# Send Message
# ─────────────────────────────────────────────────────────────

send_message() {
    local target="$1"
    local content="$2"

    local username
    username=$(get_username)

    # Check target exists
    local target_profile="${REPO_DIR}/profiles/${target}.yaml"
    if [ ! -f "$target_profile" ]; then
        error_user_not_found "$target"
        exit 1
    fi

    # Check if seed profile
    if grep -q 'is_seed: true' "$target_profile"; then
        error_seed_profile "$target"
        exit 1
    fi

    # Check friendship
    if ! check_friendship "$username" "$target"; then
        echo ""
        echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${YELLOW}║${NC}  ${BOLD}⚠️  你们还不是好友${NC}"
        echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "发送消息前需要先建立好友关系。"
        echo ""
        echo "选择一种方式:"
        echo "  [1] 发送好友请求 + 自动协商 (推荐)"
        echo "      → AI 助手自动交流，10 轮后生成友谊报告"
        echo "      → 适合寻找深度合作/交流机会"
        echo ""
        echo "  [2] 只发送好友请求"
        echo "      → 等待对方手动接受"
        echo "      → 适合先建立联系"
        echo ""
        echo "  [3] 取消"
        echo ""
        echo -n "选择："
        read -r choice

        case "$choice" in
            1)
                echo ""
                echo -e "${BLUE}⟳${NC} 正在发送好友请求并启动协商..."
                bash "${SCRIPT_DIR}/request.sh" "$target"
                echo ""
                echo "正在启动自动协商..."
                bash "${SCRIPT_DIR}/auto.sh" start "$target"
                ;;
            2)
                bash "${SCRIPT_DIR}/request.sh" "$target"
                ;;
            *)
                echo "已取消"
                exit 0
                ;;
        esac
        return
    fi

    # Get recipient's public key
    local public_key
    public_key=$(grep -A 30 '^public_key:' "$target_profile" | tail -n +2 | head -n 30)

    # Write to temp file
    local temp_pubkey
    temp_pubkey=$(mktemp /tmp/ocfr_pub_XXXXXX.pem)
    echo "$public_key" > "$temp_pubkey"

    # Encrypt message
    local encrypted
    encrypted=$(echo -n "$content" | bash "${SCRIPT_DIR}/crypto.sh" encrypt "$temp_pubkey")

    # Clean up temp file
    rm -f "$temp_pubkey"

    # Parse encrypted output
    local encrypted_key iv encrypted_content
    encrypted_key=$(echo "$encrypted" | grep '^encrypted_key:' | sed 's/^encrypted_key: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    iv=$(echo "$encrypted" | grep '^iv:' | sed 's/^iv: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    encrypted_content=$(echo "$encrypted" | grep '^encrypted_content:' | sed 's/^encrypted_content: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

    # Create message file
    local timestamp
    timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    local msg_id=$(date +%s%N | md5sum | head -c 8)

    local messages_dir="${REPO_DIR}/messages/${target}"
    mkdir -p "$messages_dir"

    local msg_file="${messages_dir}/from_${username}_${timestamp}.yaml"

    cat > "$msg_file" <<EOF
from: "${username}"
to: "${target}"
timestamp: "${timestamp}"
encrypted_key: "${encrypted_key}"
iv: "${iv}"
encrypted_content: "${encrypted_content}"
EOF

    # Save plaintext to local sent cache
    local sent_dir="${OCFR_DIR}/sent/${target}"
    mkdir -p "$sent_dir"
    echo -n "$content" > "${sent_dir}/${timestamp}.txt"

    # Sync
    echo ""
    echo -e "${BLUE}⟳${NC} 正在发送消息..."
    cd "${REPO_DIR}"
    git add "messages/" 2>/dev/null || true
    git commit -m "feat: message from ${username} to ${target}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || true

    render_message_sent "$target" "$content" "$timestamp"
}

# ─────────────────────────────────────────────────────────────
# Interactive Mode
# ─────────────────────────────────────────────────────────────

interactive_chat() {
    local target="$1"

    echo ""
    echo "与 @${target} 聊天 (输入 /quit 退出)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show history
    view_conversation "$target"

    # Chat loop
    while true; do
        echo -n "你 > "
        read -r input

        if [ "$input" = "/quit" ] || [ "$input" = "/q" ] || [ "$input" = "/back" ]; then
            echo "退出聊天"
            return
        fi

        if [ -n "$input" ]; then
            send_message "$target" "$input"
        fi
    done
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    local target="${1:-}"
    local message="${2:-}"

    # Sync first
    bash "${SCRIPT_DIR}/sync.sh" pull >/dev/null 2>&1 || true

    if [ -z "$target" ]; then
        view_inbox
        return
    fi

    # Check for inbox command
    if [ "$target" = "inbox" ] || [ "$target" = "in" ]; then
        view_inbox
        return
    fi

    # If message provided, send it
    if [ -n "$message" ]; then
        send_message "$target" "$message"
        return
    fi

    # Otherwise, show conversation and enter interactive mode
    view_conversation "$target"

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "操作:"
    echo "  输入消息直接发送"
    echo "  /quit 或 /q 退出"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    interactive_chat "$target"
}

main "$@"
