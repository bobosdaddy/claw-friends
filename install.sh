#!/usr/bin/env bash
# claw-friends-ux: install.sh
# One-click installer for all platforms
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🦞 Claw Friends UX - 安装程序${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
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

print_info() {
    echo -e "  ${CYAN}ℹ${NC} $1"
}

# ─────────────────────────────────────────────────────────────
# Check Prerequisites
# ─────────────────────────────────────────────────────────────

check_platform() {
    local platform="unknown"

    case "$(uname -s)" in
        Darwin*)
            platform="macos"
            ;;
        Linux*)
            if grep -q "Android" /proc/version 2>/dev/null; then
                platform="android"
            else
                platform="linux"
            fi
            ;;
        *)
            platform="unknown"
            ;;
    esac

    echo "$platform"
}

check_claude_platform() {
    echo ""
    echo "请选择你的 Claude 平台:"
    echo ""
    echo "  [1] Claude Code CLI (~/.claude/skills/)"
    echo "  [2] OpenClaw / QClaw / KimiClaw"
    echo "  [3] CoPaw (~/.copaw/customized_skills/)"
    echo "  [4] 项目级安装 (当前目录)"
    echo ""
    echo -n "选择 [1-4]: "
    read -r choice

    case "$choice" in
        1)
            echo "${HOME}/.claude/skills"
            ;;
        2)
            echo "${HOME}/.openclaw/skills"
            ;;
        3)
            echo "${HOME}/.copaw/customized_skills"
            ;;
        4)
            echo "$(pwd)/.claude/skills"
            ;;
        *)
            echo "${HOME}/.claude/skills"
            ;;
    esac
}

check_dependencies() {
    print_info "检查依赖..."

    local missing=()

    command -v git >/dev/null 2>&1 || missing+=("git")
    command -v bash >/dev/null 2>&1 || missing+=("bash")

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "缺少依赖：${missing[*]}"
        echo ""
        echo "请先安装:"
        for dep in "${missing[@]}"; do
            case "$dep" in
                git)
                    echo "  macOS: brew install git"
                    echo "  Linux: sudo apt install git"
                    ;;
                bash)
                    echo "  macOS: brew install bash"
                    echo "  Linux: sudo apt install bash"
                    ;;
            esac
        done
        exit 1
    fi

    print_success "依赖检查通过"
}

# ─────────────────────────────────────────────────────────────
# Installation
# ─────────────────────────────────────────────────────────────

install() {
    local target_dir="$1"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    print_info "安装到：${target_dir}"

    # Create target directory
    mkdir -p "${target_dir}"

    # Copy skill files
    print_info "复制技能文件..."

    if [ -d "${script_dir}/scripts" ]; then
        cp -r "${script_dir}/scripts" "${target_dir}/claw-friends/"
        print_success "脚本文件已复制"
    fi

    if [ -d "${script_dir}/templates" ]; then
        mkdir -p "${target_dir}/claw-friends/templates"
        cp "${script_dir}/templates/"* "${target_dir}/claw-friends/templates/" 2>/dev/null || true
        print_success "模板文件已复制"
    fi

    if [ -f "${script_dir}/SKILL.md" ]; then
        cp "${script_dir}/SKILL.md" "${target_dir}/claw-friends/"
        print_success "SKILL.md 已复制"
    fi

    if [ -f "${script_dir}/README.md" ]; then
        cp "${script_dir}/README.md" "${target_dir}/claw-friends/"
        print_success "README.md 已复制"
    fi

    # Set permissions
    chmod +x "${target_dir}/claw-friends/scripts/"*.sh 2>/dev/null || true
    print_success "权限已设置"
}

# ─────────────────────────────────────────────────────────────
# Post-Install Check
# ─────────────────────────────────────────────────────────────

post_install() {
    local target_dir="$1"

    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  ✅ 安装完成！                                        ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    print_success "安装位置：${target_dir}/claw-friends/"
    echo ""

    echo "下一步:"
    echo ""
    echo "  1. 确保已安装依赖:"
    echo -e "     ${CYAN}brew install gh openssl${NC}  (macOS)"
    echo -e "     ${CYAN}sudo apt install gh openssl${NC}  (Linux)"
    echo ""
    echo "  2. 认证 GitHub CLI:"
    echo -e "     ${CYAN}gh auth login${NC}"
    echo ""
    echo "  3. 开始使用:"
    echo -e "     ${CYAN}/friends${NC}  — 显示主菜单"
    echo -e "     ${CYAN}/friends init${NC}  — 初始化"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "提示：重启 Claude Code 以加载新技能"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    print_header

    # Check platform
    local platform
    platform=$(check_platform)
    print_info "检测到平台：${platform}"

    # Check dependencies
    check_dependencies

    # Get target directory
    local target_dir
    target_dir=$(check_claude_platform)

    # Install
    echo ""
    echo "开始安装..."
    echo ""
    install "${target_dir}"

    # Post-install
    post_install "${target_dir}"
}

main "$@"
