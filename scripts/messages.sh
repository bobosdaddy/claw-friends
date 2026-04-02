#!/usr/bin/env bash
# claw-friends: messages.sh (UX Enhanced)
# Friendly error messages and user-facing text
set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────────────────────
# Error Messages
# ─────────────────────────────────────────────────────────────

error_not_initialized() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}⚠️  你还没有初始化 Claw Friends${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "初始化将帮你:"
    echo "  • 生成加密密钥对 (RSA-2048)"
    echo "  • 创建个人资料"
    echo "  • 加入社区网络"
    echo ""
    echo "运行以下命令开始:"
    echo -e "  ${CYAN}/friends init${NC}"
    echo ""
}

error_user_not_found() {
    local user="$1"
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}📭 未找到用户：@${user}${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "可能原因:"
    echo "  • 用户名拼写错误"
    echo "  • 该用户尚未创建资料"
    echo "  • 用户资料已被删除"
    echo ""
    echo "试试:"
    echo -e "  ${CYAN}/friends explore${NC}  — 浏览社区成员"
    echo -e "  ${CYAN}/friends match${NC}    — 获取智能推荐"
    echo ""
}

error_seed_profile() {
    local user="$1"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}ℹ️  示例资料${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "@${user} 是一个示例资料，用于演示和测试。"
    echo ""
    echo "你可以:"
    echo -e "  ${CYAN}/friends explore${NC}  — 浏览真实社区成员"
    echo -e "  ${CYAN}/friends match${NC}    — 获取智能推荐"
    echo ""
}

error_not_friends() {
    local user="$1"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}🔒 你们还不是好友${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "要先成为好友才能发消息哦!"
    echo ""
    echo "发送好友请求:"
    echo -e "  ${CYAN}/friends request ${user}${NC}"
    echo ""
}

error_decryption_failed() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}🔓 消息解密失败${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "可能原因:"
    echo "  • 你的私钥已更改 (重新生成过密钥)"
    echo "  • 消息已损坏"
    echo ""
    echo "说明:"
    echo "  用旧密钥加密的消息无法用新密钥解密。"
    echo "  这是端到端加密的安全特性。"
    echo ""
    echo "如需重新生成密钥:"
    echo -e "  ${CYAN}/friends init --rekey${NC}"
    echo ""
}

error_sync_failed() {
    local details="$1"
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}🔄 数据同步失败${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "请检查:"
    echo "  • 网络连接是否正常"
    echo "  • GitHub 是否可访问"
    echo ""
    if [ -n "$details" ]; then
        echo "详细信息:"
        echo -e "  ${DIM}${details}${NC}"
        echo ""
    fi
    echo "稍后重试:"
    echo -e "  ${CYAN}/friends sync${NC}"
    echo ""
}

error_push_conflict() {
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}🔄 数据同步冲突${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "有其他用户同时更新了数据。"
    echo "正在自动合并..."
    echo ""
}

error_profile_empty() {
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}📝 资料太空了${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "你的资料完整度较低，匹配质量会受影响。"
    echo ""
    echo "完善资料:"
    echo -e "  ${CYAN}/friends profile edit${NC}"
    echo ""
    echo "智能导入 GitHub 数据:"
    echo -e "  ${CYAN}/friends profile enhance${NC}"
    echo ""
}

error_agreement_not_accepted() {
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}📋 需要接受用户协议${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "使用自动协商功能前，需要接受用户协议。"
    echo ""
    echo "协议内容:"
    echo "  1. 你的 Claw 可以代表你与其他 Claw 对话"
    echo "  2. 对话内容可能包含你的公开 profile 信息"
    echo "  3. 双方同意前，不会交换联系方式"
    echo ""
    echo "输入 ${CYAN}我同意${NC} 或 ${CYAN}I agree${NC} 接受协议"
    echo ""
}

error_target_not_opted_in() {
    local user="$1"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}ℹ️  对方未启用自动协商${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "@${user} 尚未接受用户协议，无法进行自动协商。"
    echo ""
    echo "你可以:"
    echo -e "  ${CYAN}/friends request ${user}${NC}  — 发送好友请求"
    echo -e "  ${CYAN}/friends msg ${user}${NC}     — 发送消息 (需先是好友)"
    echo ""
}

error_negotiation_exists() {
    local user="$1"
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${BOLD}ℹ️  协商已在进行中${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "你与 @${user} 的自动协商已在进行中。"
    echo ""
    echo "查看进度:"
    echo -e "  ${CYAN}/friends auto status${NC}"
    echo ""
    echo "停止协商:"
    echo -e "  ${CYAN}/friends auto stop ${user}${NC}"
    echo ""
}

error_negotiation_ended() {
    local user="$1"
    local reason="$2"
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}ℹ️  协商已结束${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "与 @${user} 的协商已结束：${reason}"
    echo ""
    echo "查看报告:"
    echo -e "  ${CYAN}/friends report ${user}${NC}"
    echo ""
}

error_network_required() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}🌐 需要网络连接${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "请检查网络连接，然后重试:"
    echo -e "  ${CYAN}/friends sync${NC}"
    echo ""
}

error_git_conflict() {
    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}🔄 Git 合并冲突${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "检测到数据冲突，可能同时有多个更新。"
    echo ""
    echo "解决步骤:"
    echo "  1. 手动拉取最新数据：cd ~/.ocfr/repo && git pull"
    echo "  2. 解决冲突文件 (如有)"
    echo "  3. 重新推送：git push"
    echo ""
    echo "或运行:"
    echo -e "  ${CYAN}/friends sync --force${NC} (强制覆盖远程)"
    echo ""
}

error_timeout() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}⏱️  操作超时${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "操作超时，可能原因:"
    echo "  • 网络连接缓慢"
    echo "  • GitHub 服务器响应慢"
    echo ""
    echo "建议:"
    echo "  • 检查网络连接"
    echo "  • 稍后重试"
    echo ""
}

error_prerequisites_missing() {
    local missing="$1"
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}❌ 缺少必要工具${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "需要安装:"
    echo "  ${missing}"
    echo ""
    echo "安装命令:"
    echo -e "  ${CYAN}macOS:${NC} brew install gh openssl git"
    echo -e "  ${CYAN}Linux:${NC} sudo apt install gh openssl git"
    echo ""
}

error_gh_not_authenticated() {
    echo ""
    echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}  ${BOLD}🔐 GitHub CLI 未认证${NC}"
    echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "请先认证 GitHub CLI:"
    echo ""
    echo -e "  ${CYAN}gh auth login${NC}"
    echo ""
    echo "然后重新运行命令"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Success Messages
# ─────────────────────────────────────────────────────────────

success_init_complete() {
    local username="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 初始化完成！欢迎 @${username}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

success_profile_updated() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 资料已更新${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

success_match_found() {
    local count="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🎯 找到 ${count} 个匹配${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

success_request_sent() {
    local user="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}📨 请求已发送给 @${user}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

success_request_accepted() {
    local user="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🎉 成为好友了！${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "你和 @${user} 现在是好友了!"
    echo ""
    echo "开始聊天:"
    echo -e "  ${CYAN}/friends msg ${user}${NC}"
    echo ""
}

success_negotiation_matched() {
    local user="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}🎉 匹配成功！${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "你和 @${user} 的 Claw 协商成功!"
    echo ""
    echo "查看友谊报告:"
    echo -e "  ${CYAN}/friends report ${user}${NC}"
    echo ""
    echo "交换联系方式:"
    echo -e "  ${CYAN}/friends connect ${user}${NC}"
    echo ""
}

success_message_sent() {
    local user="$1"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 消息已发送${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "消息已加密并推送给 @${user}"
    echo ""
}

success_sync_complete() {
    local profiles="$1"
    local messages="$2"
    local requests="$3"
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 同步完成${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "本次同步:"
    echo "  • ${profiles} 个新/更新资料"
    echo "  • ${messages} 条新消息"
    echo "  • ${requests} 个新好友请求"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Info Messages
# ─────────────────────────────────────────────────────────────

info_help() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}📖 Claw Friends 帮助${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "基础命令:"
    echo "  /friends init           初始化设置"
    echo "  /friends profile        查看/编辑资料"
    echo "  /friends explore        浏览社区"
    echo "  /friends match          智能推荐"
    echo ""
    echo "社交功能:"
    echo "  /friends request <user> 发送好友请求"
    echo "  /friends requests       查看好友请求"
    echo "  /friends msg <user>     发送/查看消息"
    echo ""
    echo "自动协商:"
    echo "  /friends auto <user>    开始自动协商"
    echo "  /friends auto discover  自动发现匹配"
    echo "  /friends auto status    查看协商状态"
    echo "  /friends report <user>  查看友谊报告"
    echo ""
    echo "其他:"
    echo "  /friends sync           手动同步"
    echo "  /friends help           显示此帮助"
    echo ""
}

info_main_menu() {
    local username="$1"
    local completeness="$2"
    local community_count="$3"

    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🦞 Claw Friends v0.2${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "你好，@${username}! 资料完整度：${completeness}%"
    echo "当前社区成员：${community_count} 人"
    echo ""

    # Completeness status
    if [ "$completeness" -lt 30 ]; then
        echo -e "${YELLOW}⚠️  资料较空洞，匹配质量会受影响${NC}"
    elif [ "$completeness" -lt 70 ]; then
        echo -e "${BLUE}ℹ  资料尚可，但可以更完善${NC}"
    else
        echo -e "${GREEN}✓  资料完整度良好${NC}"
    fi
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "快捷操作:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  [1] /friends profile edit   编辑资料"
    echo "  [2] /friends profile enhance  智能导入 GitHub"
    echo "  [3] /friends explore        浏览社区"
    echo "  [4] /friends match          获取推荐"
    echo "  [5] /friends help           帮助"
    echo ""
    echo -n "请输入选择 [1-5] 或命令："
}

# ─────────────────────────────────────────────────────────────
# Confirmation Prompts
# ─────────────────────────────────────────────────────────────

confirm_delete() {
    local item="$1"
    echo -n "确定要删除 ${item} 吗？[y/N]: "
}

confirm_exit() {
    echo -n "确定要退出吗？[y/N]: "
}

confirm_rekey() {
    echo ""
    echo "⚠️  重新生成密钥后，旧消息将无法解密!"
    echo ""
    echo -n "确定要继续吗？[y/N]: "
}

# Export functions
export -f error_not_initialized 2>/dev/null || true
export -f error_user_not_found 2>/dev/null || true
export -f error_seed_profile 2>/dev/null || true
export -f error_not_friends 2>/dev/null || true
export -f error_decryption_failed 2>/dev/null || true
export -f error_sync_failed 2>/dev/null || true
export -f error_push_conflict 2>/dev/null || true
export -f error_profile_empty 2>/dev/null || true
export -f error_agreement_not_accepted 2>/dev/null || true
export -f error_target_not_opted_in 2>/dev/null || true
export -f error_negotiation_exists 2>/dev/null || true
export -f error_negotiation_ended 2>/dev/null || true
export -f error_network_required 2>/dev/null || true
export -f error_prerequisites_missing 2>/dev/null || true
export -f error_gh_not_authenticated 2>/dev/null || true

export -f success_init_complete 2>/dev/null || true
export -f success_profile_updated 2>/dev/null || true
export -f success_match_found 2>/dev/null || true
export -f success_request_sent 2>/dev/null || true
export -f success_request_accepted 2>/dev/null || true
export -f success_negotiation_matched 2>/dev/null || true
export -f success_message_sent 2>/dev/null || true
export -f success_sync_complete 2>/dev/null || true

export -f info_help 2>/dev/null || true
export -f info_main_menu 2>/dev/null || true

export -f confirm_delete 2>/dev/null || true
export -f confirm_exit 2>/dev/null || true
export -f confirm_rekey 2>/dev/null || true
