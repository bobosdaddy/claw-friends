#!/usr/bin/env bash
# claw-friends: init.sh (UX Enhanced)
# Interactive 4-step initialization with visual feedback
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

# Directories
OCFR_DIR="${HOME}/.ocfr"
KEYS_DIR="${OCFR_DIR}/keys"
REPO_DIR="${OCFR_DIR}/repo"
DEFAULT_REPO="https://github.com/bobosdaddy/claw-friends-data"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─────────────────────────────────────────────────────────────
# Helper Functions
# ─────────────────────────────────────────────────────────────

print_header() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  🦞 ${BOLD}Claw Friends — 去中心化社交网络${NC}                    ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    local step="$1"
    local total="$2"
    local message="$3"
    echo -e "${BLUE}Step ${step}/${total}:${NC} ${message}..."
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

check_prerequisites() {
    print_step 1 4 "检查环境"

    local missing=()
    local auth_error=""

    # Check git
    if command -v git >/dev/null 2>&1; then
        local git_version
        git_version=$(git --version | awk '{print $3}')
        print_success "git ${git_version}"
    else
        missing+=("git")
    fi

    # Check openssl
    if command -v openssl >/dev/null 2>&1; then
        local openssl_version
        openssl_version=$(openssl version | awk '{print $2}')
        print_success "openssl ${openssl_version}"
    else
        missing+=("openssl")
    fi

    # Check gh CLI
    if command -v gh >/dev/null 2>&1; then
        local gh_version
        gh_version=$(gh --version | head -1 | awk '{print $3}')
        print_success "gh CLI ${gh_version}"

        # Check auth
        if gh auth status >/dev/null 2>&1; then
            local gh_user
            gh_user=$(gh api user --jq '.login')
            print_success "GitHub 已认证：${gh_user}"
            echo "$gh_user"
        else
            auth_error="true"
        fi
    else
        missing+=("gh (GitHub CLI)")
    fi

    if [ ${#missing[@]} -gt 0 ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}❌ 缺少必要工具${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "需要安装以下工具:"
        for tool in "${missing[@]}"; do
            echo "  • ${tool}"
        done
        echo ""
        echo "安装命令:"
        echo -e "  ${CYAN}macOS:${NC}"
        echo "    brew install gh openssl"
        echo -e "  ${CYAN}Linux:${NC}"
        echo "    sudo apt install gh openssl git"
        echo ""
        exit 1
    fi

    if [ -n "$auth_error" ]; then
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${NC}  ${BOLD}❌ GitHub CLI 未认证${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "请先认证 GitHub CLI:"
        echo ""
        echo -e "  ${CYAN}gh auth login${NC}"
        echo ""
        echo "然后重新运行 /friends init"
        echo ""
        exit 1
    fi

    print_progress 1 4
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Generate Keys
# ─────────────────────────────────────────────────────────────

keygen() {
    print_step 2 4 "生成加密密钥"

    mkdir -p "${KEYS_DIR}"

    if [ -f "${KEYS_DIR}/private.pem" ]; then
        echo ""
        print_warning "密钥已存在"
        echo ""
        echo "私钥路径：${KEYS_DIR}/private.pem"
        echo ""
        echo "要继续吗？这将使旧消息无法解密 (y/N):"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_info "保留原密钥"
            print_progress 2 4
            return 0
        fi
        echo "正在重新生成..."
    fi

    # Generate RSA-2048
    if openssl genrsa -out "${KEYS_DIR}/private.pem" 2048 2>/dev/null; then
        print_success "RSA-2048 私钥已生成"
    else
        print_error "私钥生成失败"
        exit 1
    fi

    # Extract public key
    if openssl rsa -in "${KEYS_DIR}/private.pem" -pubout -out "${KEYS_DIR}/public.pem" 2>/dev/null; then
        print_success "RSA-2048 公钥已提取"
    else
        print_error "公钥提取失败"
        exit 1
    fi

    # Set permissions
    chmod 600 "${KEYS_DIR}/private.pem"
    chmod 644 "${KEYS_DIR}/public.pem"
    print_success "私钥权限设置为 600 (仅所有者可读)"

    print_warning "重要：私钥丢失将导致历史消息永久无法恢复！"
    print_info "建议备份：~/.ocfr/keys/private.pem"

    print_progress 2 4
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Clone Repo
# ─────────────────────────────────────────────────────────────

clone_repo() {
    print_step 3 4 "克隆数据仓库"

    local repo_url="${1:-${DEFAULT_REPO}}"

    mkdir -p "${OCFR_DIR}"

    if [ -d "${REPO_DIR}/.git" ]; then
        print_info "仓库已存在，正在更新..."
        cd "${REPO_DIR}"

        local branch
        branch=$(git symbolic-ref --short HEAD 2>/dev/null || echo "main")

        if git pull --rebase origin "${branch}" >/dev/null 2>&1; then
            print_success "仓库已更新"
        else
            print_warning "更新失败，将继续使用本地版本"
        fi
    else
        print_info "正在克隆 ${repo_url}..."

        if git clone "${repo_url}" "${REPO_DIR}" >/dev/null 2>&1; then
            print_success "仓库克隆完成"

            cd "${REPO_DIR}"
            mkdir -p profiles matches messages negotiations connects

            # Install .gitignore
            local gitignore_template="${SCRIPT_DIR}/../templates/repo.gitignore"
            if [ -f "${gitignore_template}" ] && [ ! -f .gitignore ]; then
                cp "${gitignore_template}" .gitignore
                print_success "已安装 .gitignore"
            fi

            # Install seed profiles
            local seed_script="${SCRIPT_DIR}/seed.sh"
            if [ -x "${seed_script}" ]; then
                bash "${seed_script}" install 2>/dev/null && \
                    print_success "已安装示例用户资料" || true
            fi

            # Commit structure
            if [ -n "$(git status --porcelain)" ]; then
                git add profiles/ matches/ messages/ negotiations/ connects/ .gitignore 2>/dev/null || true
                git commit -m "chore: initialize structure" >/dev/null 2>&1 || true
                git push origin HEAD 2>/dev/null || print_warning "推送失败，稍后手动同步"
            fi
        else
            print_error "克隆失败"
            echo ""
            echo "请检查:"
            echo "  • 网络连接"
            echo "  • 仓库 URL 是否正确"
            echo ""
            exit 1
        fi
    fi

    # Count community members
    local member_count
    member_count=$(find "${REPO_DIR}/profiles" -name "*.yaml" 2>/dev/null | \
        xargs grep -L 'is_seed: true' 2>/dev/null | wc -l | tr -d ' ')

    print_success "当前社区成员：${member_count} 人"
    print_progress 3 4
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Create Profile
# ─────────────────────────────────────────────────────────────

create_profile() {
    print_step 4 4 "创建你的资料"

    local username="$1"
    local profile_file="${REPO_DIR}/profiles/${username}.yaml"

    # Auto-detect from GitHub
    local gh_name gh_bio
    gh_name=$(gh api user --jq '.name // .login')
    gh_bio=$(gh api user --jq '.bio // empty')

    echo ""
    print_info "从 GitHub 检测到:"
    echo "  用户名：@${username}"
    echo "  姓名：${gh_name:-未设置}"
    echo "  简介：${gh_bio:-未设置}"
    echo ""

    # Ask for display name
    local display_name
    echo -n "  显示名称 [${gh_name:-$username}]: "
    read -r display_name
    display_name="${display_name:-${gh_name:-$username}}"

    print_success "显示名称：${display_name}"

    # Get public key
    local public_key
    public_key=$(cat "${KEYS_DIR}/public.pem")

    # Generate profile YAML
    local updated_at
    updated_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local bio="${gh_bio:-Hello from @${username}!}"

    cat > "${profile_file}" <<EOF
username: "${username}"
display_name: "${display_name}"
github: "${username}"
avatar_url: "https://github.com/${username}.png"
bio: "${bio}"
interests: []
skills: []
looking_for:
  - interesting conversations
platforms: {}
public_key: |
$(echo "$public_key" | sed 's/^/  /')
updated_at: "${updated_at}"
ideal_type:
  preferred_interests: []
  preferred_skills: []
  personality_traits: []
  deal_breakers: []
  description: ""
agreement_accepted: false
agreement_accepted_at: ""
is_seed: false
EOF

    print_success "资料文件已创建"

    # Write config
    cat > "${OCFR_DIR}/config.yaml" <<EOF
username: "${username}"
repo_url: "${DEFAULT_REPO}"
repo_path: "${REPO_DIR}"
auto_sync: true
message_retention: 100
auto_negotiate: true
affinity_threshold: 70
abandon_threshold: 30
max_rounds: 10
EOF

    print_success "配置文件已写入"

    # Push to remote
    cd "${REPO_DIR}"
    git add "profiles/${username}.yaml" 2>/dev/null || true
    git commit -m "feat: add profile for ${username}" >/dev/null 2>&1 || true
    git push origin HEAD 2>/dev/null || print_warning "推送失败，稍后手动 /friends sync"

    print_success "资料已同步到社区"
    print_progress 4 4
    echo ""
}

# ─────────────────────────────────────────────────────────────
# Show Success Screen
# ─────────────────────────────────────────────────────────────

show_success_screen() {
    local username="$1"
    local display_name="$2"

    print_header

    echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}✅ 初始化完成！欢迎 @${username}${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Profile card preview
    echo "你的资料卡:"
    echo "┌─────────────────────────────────────────┐"
    echo "│  ${display_name} (@${username})"
    echo "│  ───────────────────────────────────────"
    echo "│"
    echo "│  🏷️  兴趣：(空) ⚠️"
    echo "│  🛠️  技能：(空) ⚠️"
    echo "│  🎯 寻找：interesting conversations"
    echo "│"
    echo "│  📊 资料完整度：25%"
    echo "└─────────────────────────────────────────┘"
    echo ""

    # Auto-enhance flow
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${YELLOW}🚀 快速开始 (推荐)${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "检测到你的 GitHub 账号：@${username}"
    echo ""
    echo "现在将自动分析你的 GitHub 项目，提取:"
    echo "  • 常用编程语言 → 技能标签"
    echo "  • 项目主题 → 兴趣标签"
    echo "  • Star 偏好 → 补充兴趣"
    echo ""
    echo -n "是否开始智能导入？[Y/n]: "
    read -r enhance_choice

    if [[ "$enhance_choice" != "n" && "$enhance_choice" != "N" ]]; then
        echo ""
        echo "正在分析 GitHub 数据..."
        bash "${SCRIPT_DIR}/enhance.sh" --auto-accept
    else
        echo ""
        echo "已跳过智能导入"
    fi

    # Next steps menu
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}下一步 (选择一项):${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  [1] 🎯 查看匹配推荐 (推荐)"
    echo "      → 基于你的技能和兴趣智能推荐"
    echo "      → 一键发送好友请求"
    echo ""
    echo "  [2] 📝 手动完善资料"
    echo "      → 编辑兴趣、技能、个人简介"
    echo ""
    echo "  [3] 🌍 浏览社区"
    echo "      → 查看现有成员"
    echo "      → 发现有趣的人"
    echo ""
    echo -n "请输入选择 [1-3]: "

    read -r choice

    case "$choice" in
        1)
            echo ""
            echo "正在为你寻找匹配..."
            bash "${SCRIPT_DIR}/match.sh" --top 5
            ;;
        2)
            echo ""
            echo "正在打开资料编辑..."
            bash "${SCRIPT_DIR}/profile.sh" edit
            ;;
        3|*)
            echo ""
            echo "正在加载社区成员..."
            bash "${SCRIPT_DIR}/explore.sh"
            ;;
    esac
}

# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────

main() {
    print_header

    # Check if already initialized
    if [ -f "${OCFR_DIR}/config.yaml" ]; then
        echo "⚠️  你似乎已经初始化过了"
        echo ""
        echo "配置文件：${OCFR_DIR}/config.yaml"
        echo ""
        echo "要重新配置吗？这将重新生成密钥 (y/N):"
        read -r confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            echo "好的！运行 /friends 查看可用命令"
            exit 0
        fi
    fi

    # Step 1: Check prerequisites
    local gh_username
    gh_username=$(check_prerequisites)

    # Step 2: Generate keys
    keygen

    # Step 3: Clone repo
    clone_repo

    # Step 4: Create profile
    create_profile "$gh_username"

    # Show success screen with next steps
    local display_name
    display_name=$(grep '^display_name:' "${REPO_DIR}/profiles/${gh_username}.yaml" | \
        sed 's/^display_name: *"\{0,1\}\([^"]*\)"\{0,1\}/\1/')

    show_success_screen "$gh_username" "$display_name"
}

# Run
main "$@"
