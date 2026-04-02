#!/usr/bin/env bash
# claw-friends: doctor.sh
# Diagnostic and quick fix tool
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

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${BOLD}🔧 Claw Friends 健康检查${NC}"
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
# Checks
# ─────────────────────────────────────────────────────────────

check_initialization() {
    print_info "检查初始化状态..."

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "未初始化"
        return 1
    fi

    print_success "已初始化"
    return 0
}

check_github_auth() {
    print_info "检查 GitHub 认证..."

    if ! command -v gh >/dev/null 2>&1; then
        print_error "gh CLI 未安装"
        return 1
    fi

    if gh auth status >/dev/null 2>&1; then
        local gh_user
        gh_user=$(gh api user --jq '.login')
        print_success "GitHub 已认证：@${gh_user}"
        return 0
    else
        print_error "GitHub CLI 未认证"
        return 1
    fi
}

check_dependencies() {
    print_info "检查依赖..."

    local all_ok=true

    for cmd in git bash openssl gh; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_success "$cmd 已安装"
        else
            print_error "$cmd 未安装"
            all_ok=false
        fi
    done

    if [ "$all_ok" = true ]; then
        return 0
    else
        return 1
    fi
}

check_repo_status() {
    print_info "检查仓库状态..."

    if [ ! -d "${REPO_DIR}/.git" ]; then
        print_error "仓库不存在"
        return 1
    fi

    cd "${REPO_DIR}"

    # Check for uncommitted changes
    local changes
    changes=$(git status --short 2>/dev/null | wc -l | tr -d ' ')

    if [ "$changes" -gt 0 ]; then
        print_warning "有待提交的更改 (${changes} 个文件)"
    else
        print_success "工作区干净"
    fi

    # Check for upstream
    if git remote -v | grep -q origin; then
        print_success "已连接远程仓库"
    else
        print_error "未连接远程仓库"
        return 1
    fi

    return 0
}

check_keys() {
    print_info "检查密钥..."

    local keys_dir="${OCFR_DIR}/keys"

    if [ ! -d "$keys_dir" ]; then
        print_error "密钥目录不存在"
        return 1
    fi

    if [ -f "${keys_dir}/private.pem" ]; then
        print_success "私钥存在"
    else
        print_error "私钥不存在"
        return 1
    fi

    if [ -f "${keys_dir}/public.pem" ]; then
        print_success "公钥存在"
    else
        print_error "公钥不存在"
        return 1
    fi

    # Check permissions
    local perms
    perms=$(stat -c "%a" "${keys_dir}/private.pem" 2>/dev/null || stat -f "%Lp" "${keys_dir}/private.pem" 2>/dev/null)

    if [ "$perms" = "600" ]; then
        print_success "私钥权限正确 (600)"
    else
        print_warning "私钥权限：${perms} (建议 600)"
    fi

    return 0
}

check_profile() {
    print_info "检查资料..."

    if [ ! -f "${CONFIG_FILE}" ]; then
        print_error "配置文件不存在"
        return 1
    fi

    local username
    username=$(grep '^username:' "${CONFIG_FILE}" | sed 's/^username: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/' | tr -d ' ')

    local profile="${REPO_DIR}/profiles/${username}.yaml"

    if [ ! -f "$profile" ]; then
        print_error "资料文件不存在"
        return 1
    fi

    # Check completeness
    local completeness=0
    grep -q '^display_name:' "$profile" && completeness=$((completeness + 10))

    local bio
    bio=$(grep '^bio:' "$profile" | sed 's/^bio: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')
    if [ -n "$bio" ] && [ ${#bio} -ge 20 ]; then
        completeness=$((completeness + 15))
    elif [ -n "$bio" ]; then
        completeness=$((completeness + 5))
    fi

    local interests_count
    interests_count=$(awk '/^interests:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    interests_count=$((interests_count > 5 ? 5 : interests_count))
    completeness=$((completeness + interests_count * 5))

    local skills_count
    skills_count=$(awk '/^skills:$/,/^[a-z_]+:/' "$profile" 2>/dev/null | grep '^ *-' | wc -l | tr -d ' ')
    skills_count=$((skills_count > 5 ? 5 : skills_count))
    completeness=$((completeness + skills_count * 5))

    if [ "$completeness" -ge 70 ]; then
        print_success "资料完整度：${completeness}%"
    elif [ "$completeness" -ge 30 ]; then
        print_warning "资料完整度：${completeness}% (建议完善)"
    else
        print_error "资料完整度：${completeness}% (需要完善)"
    fi

    return 0
}

# ─────────────────────────────────────────────────────────────
# Quick Fixes
# ─────────────────────────────────────────────────────────────

fix_permissions() {
    print_info "修复权限..."

    local keys_dir="${OCFR_DIR}/keys"

    if [ -d "$keys_dir" ]; then
        chmod 600 "${keys_dir}/private.pem" 2>/dev/null || true
        chmod 644 "${keys_dir}/public.pem" 2>/dev/null || true
        print_success "密钥权限已修复"
    fi

    if [ -d "${REPO_DIR}" ]; then
        chmod 755 "${REPO_DIR}" 2>/dev/null || true
        print_success "仓库权限已修复"
    fi
}

sync_now() {
    print_info "正在同步..."

    bash "${SCRIPT_DIR}/sync.sh" 2>/dev/null && {
        print_success "同步完成"
    } || {
        print_error "同步失败"
    }
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    print_header

    echo "正在运行诊断..."
    echo ""

    local issues=0

    # Run checks
    check_initialization || issues=$((issues + 1))
    check_github_auth || issues=$((issues + 1))
    check_dependencies || issues=$((issues + 1))
    check_repo_status || issues=$((issues + 1))
    check_keys || issues=$((issues + 1))
    check_profile || issues=$((issues + 1))

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ "$issues" -eq 0 ]; then
        print_success "所有检查通过！"
        echo ""
        echo "你的 Claw Friends 状态良好"
    else
        print_warning "发现 ${issues} 个问题"
        echo ""
        echo "建议运行以下命令修复:"
        echo ""

        if ! check_initialization 2>/dev/null; then
            echo "  /friends init  — 初始化"
        fi

        if ! check_github_auth 2>/dev/null; then
            echo "  gh auth login  — GitHub 认证"
        fi

        if ! check_keys 2>/dev/null; then
            echo "  /friends init --rekey  — 重新生成密钥"
        fi
    fi

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "快捷操作:"
    echo ""
    echo "  [1] 同步数据"
    echo "  [2] 修复权限"
    echo "  [3] 重新初始化"
    echo "  [q] 退出"
    echo ""
    echo -n "选择 [1-3/q]:"
    read -r choice

    case "$choice" in
        1)
            sync_now
            ;;
        2)
            fix_permissions
            ;;
        3)
            echo ""
            echo "正在重新初始化..."
            bash "${SCRIPT_DIR}/init.sh"
            ;;
        *)
            echo "退出"
            ;;
    esac
}

main "$@"
