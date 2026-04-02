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
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCFR_DIR="${HOME}/.ocfr"

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

print_step() {
    echo -e "${BLUE}Step ${1}/${2}:${NC} ${3}..."
}

# Progress bar
print_progress() {
    local current="$1"
    local total="$2"
    local width=30
    local percentage=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))

    printf "  ["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%\n" "$percentage"
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
    echo ""

    local missing=()
    local can_auto_install=()

    # Check git
    if command -v git >/dev/null 2>&1; then
        local git_version
        git_version=$(git --version | awk '{print $3}')
        print_success "git ${git_version}"
    else
        missing+=("git")
        can_auto_install+=("git")
    fi

    # Check bash
    if command -v bash >/dev/null 2>&1; then
        local bash_version
        bash_version=$(bash --version | head -1 | awk '{print $4}')
        print_success "bash ${bash_version}"
    else
        missing+=("bash")
        can_auto_install+=("bash")
    fi

    # Check openssl
    if command -v openssl >/dev/null 2>&1; then
        local openssl_version
        openssl_version=$(openssl version | awk '{print $2}')
        print_success "openssl ${openssl_version}"
    else
        missing+=("openssl")
        can_auto_install+=("openssl")
    fi

    # Check gh CLI
    if command -v gh >/dev/null 2>&1; then
        local gh_version
        gh_version=$(gh --version | head -1 | awk '{print $3}')
        print_success "gh CLI ${gh_version}"

        # Check auth status
        if gh auth status >/dev/null 2>&1; then
            local gh_user
            gh_user=$(gh api user --jq '.login')
            print_success "GitHub 已认证：@${gh_user}"
        else
            print_warning "GitHub CLI 未认证 (安装后需认证)"
        fi
    else
        missing+=("gh (GitHub CLI)")
        can_auto_install+=("gh")
    fi

    echo ""

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}❌ 缺少必要工具${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "需要安装以下工具:"
        for tool in "${missing[@]}"; do
            echo "  • ${tool}"
        done
        echo ""

        # Offer auto-install
        echo -n "是否自动安装缺失的依赖？[Y/n]: "
        read -r install_choice

        if [[ "$install_choice" != "n" && "$install_choice" != "N" ]]; then
            install_missing_deps "${can_auto_install[@]}"
        else
            echo ""
            echo "请手动安装:"
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
                    openssl)
                        echo "  macOS: brew install openssl"
                        echo "  Linux: sudo apt install openssl"
                        ;;
                    gh)
                        echo "  macOS: brew install gh"
                        echo "  Linux: sudo apt install gh"
                        ;;
                esac
            done
            echo ""
            exit 1
        fi
    else
        print_success "依赖检查通过"
    fi

    echo ""
}

install_missing_deps() {
    local platform
    platform=$(check_platform)

    echo ""
    echo "正在安装缺失的依赖..."
    echo ""

    for dep in "$@"; do
        case "$platform" in
            macos)
                if command -v brew >/dev/null 2>&1; then
                    print_info "brew install ${dep}..."
                    brew install "${dep}" && print_success "${dep} 安装成功" || {
                        print_error "${dep} 安装失败"
                        exit 1
                    }
                else
                    print_error "Homebrew 未安装，请先安装 Homebrew"
                    echo "访问：https://brew.sh"
                    exit 1
                fi
                ;;
            linux)
                print_info "sudo apt install ${dep}..."
                sudo apt update -qq && sudo apt install -y "${dep}" && print_success "${dep} 安装成功" || {
                    print_error "${dep} 安装失败"
                    exit 1
                }
                ;;
        esac
    done

    echo ""
    print_success "所有依赖安装完成"
    echo ""
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

    # Remove old version if exists
    if [ -d "${target_dir}/claw-friends" ]; then
        print_info "检测到旧版本，正在备份..."
        cp -r "${target_dir}/claw-friends" "${target_dir}/claw-friends.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        rm -rf "${target_dir}/claw-friends"
        print_success "旧版本已备份"
    fi

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

    if [ -f "${script_dir}/install.sh" ]; then
        cp "${script_dir}/install.sh" "${target_dir}/claw-friends/"
        print_success "install.sh 已复制"
    fi

    # Set permissions
    chmod +x "${target_dir}/claw-friends/scripts/"*.sh 2>/dev/null || true
    print_success "权限已设置"
}

# ─────────────────────────────────────────────────────────────
# GitHub Auth Helper
# ─────────────────────────────────────────────────────────────

github_auth() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  🔐 GitHub 认证                                       ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    if command -v gh >/dev/null 2>&1; then
        if gh auth status >/dev/null 2>&1; then
            local gh_user
            gh_user=$(gh api user --jq '.login')
            print_success "GitHub 已认证：@${gh_user}"
            echo ""
            echo "无需重复认证"
            return 0
        fi

        echo "检测到 GitHub CLI 未认证"
        echo ""
        echo "是否现在认证？[Y/n]: "
        read -r auth_choice

        if [[ "$auth_choice" != "n" && "$auth_choice" != "N" ]]; then
            echo ""
            print_info "启动 GitHub 认证..."
            gh auth login

            if gh auth status >/dev/null 2>&1; then
                gh_user=$(gh api user --jq '.login')
                echo ""
                print_success "GitHub 认证成功：@${gh_user}"
            else
                print_warning "认证失败，稍后可手动运行：gh auth login"
            fi
        else
            print_info "已跳过，稍后手动运行：gh auth login"
        fi
    else
        print_warning "gh CLI 未安装，跳过认证"
        echo "安装后运行：gh auth login"
    fi

    echo ""
}

# ─────────────────────────────────────────────────────────────
# Quick Start Helper
# ─────────────────────────────────────────────────────────────

quick_start() {
    echo ""
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║  🚀 快速开始                                          ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo ""

    echo "是否现在初始化 Claw Friends？"
    echo ""
    echo "  [1] 是，立即初始化 (推荐)"
    echo "  [2] 否，稍后手动运行 /friends init"
    echo ""
    echo -n "选择 [1-2]: "
    read -r init_choice

    case "$init_choice" in
        1)
            echo ""
            print_info "正在启动初始化..."
            echo ""
            # Set up PATH to find the script
            export PATH="${target_dir}/claw-friends/scripts:${PATH}"
            bash "${target_dir}/claw-friends/scripts/init.sh"
            ;;
        *)
            echo ""
            print_info "已跳过"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Uninstall
# ─────────────────────────────────────────────────────────────

uninstall() {
    local target_dir="$1"

    echo ""
    echo -e "${YELLOW}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${NC}  ${BOLD}⚠️  卸载 Claw Friends UX${NC}"
    echo -e "${YELLOW}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo "卸载将删除:"
    echo "  • 技能文件：${target_dir}/claw-friends/"
    echo "  • 本地数据将保留 (~/.ocfr/)"
    echo ""
    echo -n "确认卸载？[y/N]: "
    read -r confirm

    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        if [ -d "${target_dir}/claw-friends" ]; then
            rm -rf "${target_dir}/claw-friends"
            echo ""
            print_success "卸载完成"
            echo ""
            echo "如需完全清理数据:"
            echo "  rm -rf ~/.ocfr/"
            echo ""
        else
            print_warning "未找到安装目录"
        fi
    else
        echo "已取消"
    fi
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

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "命令速查:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ${CYAN}/friends${NC}          — 主菜单"
    echo "  ${CYAN}/friends init${NC}     — 初始化"
    echo "  ${CYAN}/friends match${NC}    — 智能匹配"
    echo "  ${CYAN}/friends explore${NC}  — 浏览社区"
    echo "  ${CYAN}/friends auto${NC}     — 自动协商"
    echo "  ${CYAN}/friends help${NC}     — 帮助"
    echo ""

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "新功能:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  ${CYAN}/friends match --batch${NC}       — 批量发送请求"
    echo "  ${CYAN}/friends explore -i rust${NC}     — 按兴趣筛选"
    echo "  ${CYAN}/friends auto status -v${NC}      — 详细状态"
    echo ""

    echo "提示：重启 Claude Code 以加载新技能"
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    print_header

    # Check for uninstall flag
    if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
        local target_dir
        target_dir=$(check_claude_platform)
        uninstall "$target_dir"
        exit 0
    fi

    # Check for upgrade flag
    if [ "${1:-}" = "--upgrade" ] || [ "${1:-}" = "-U" ]; then
        print_info "正在检查更新..."
        echo ""

        local current_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [ -d "${current_dir}/.git" ]; then
            cd "${current_dir}"
            if git pull origin main >/dev/null 2>&1; then
                print_success "已更新到最新版本"
                echo ""
                print_info "正在重新安装..."
            else
                print_warning "已是最新版本或更新失败"
            fi
        else
            print_warning "非 git 安装，无法自动升级"
            echo "请重新运行安装脚本"
        fi
    fi

    # Check platform
    local platform
    platform=$(check_platform)
    print_info "检测到平台：${platform}"

    # Check dependencies
    check_dependencies

    # GitHub auth check
    if command -v gh >/dev/null 2>&1; then
        if ! gh auth status >/dev/null 2>&1; then
            github_auth
        fi
    fi

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

    # Quick start
    quick_start "${target_dir}"
}

main "$@"
