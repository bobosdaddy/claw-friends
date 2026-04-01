# 产品需求文档：快速开始引导 (Quick Start)

**版本**: 1.0  
**状态**: 草案  
**创建日期**: 2026-04-01  
**优先级**: P0  
**关联版本**: v0.5.0

---

## 1. 执行摘要

### 1.1 问题陈述

当前 `claw-friends` 新用户初始化后面临"空转"问题：

- **Profile 空洞**: init 仅填充 GitHub 基本信息，`interests`/`skills`/`ideal_type` 为空数组
- **行动迷茫**: 用户完成 init 后不知道下一步该做什么
- **摩擦点多**: 需要手动执行 4-5 个命令才能完成首次匹配
- **协议打断**: 首次使用 `/friends auto` 时突然弹出用户协议，打断心流

**影响**: 新用户可能在完成 init 后流失，无法体验到产品核心价值（匹配 + 交流）

### 1.2 解决方案

新增 **快速开始引导流程**，通过两个新特性降低冷启动门槛：

1. **GitHub 资料增强**: init 时自动从 GitHub 推断兴趣/技能标签
2. **`/friends quickstart` 命令**: 一键式引导，3 步完成首次匹配

### 1.3 预期收益

| 指标 | 当前基线 | 目标值 |
|------|----------|--------|
| init → 首次 match 时间 | ~10 分钟 | <2 分钟 |
| profile 完整率 | <30% (估算) | >80% |
| 新用户 7 日留存 | 未知 | >60% |
| 首周匹配成功率 | 未知 | >40% |

---

## 2. 背景与现状

### 2.1 当前用户旅程

```
Day 0: 新用户安装 claw-friends
  ↓
/friends init
  ├── 检查依赖 (git, openssl, gh)
  ├── 读取 GitHub 资料 (login, name, bio)
  ├── 询问 display_name (唯一问题)
  ├── 生成 RSA 密钥
  ├── 克隆 repo
  └── 推送空 profile
  ↓
✅ "初始化完成！"
  ↓
❓ 用户面对空 profile:
   - interests: []
   - skills: []
   - looking_for: ["interesting conversations"]
   - ideal_type: { empty }
  ↓
用户需要主动发现:
   - /friends profile edit (完善资料)
   - /friends explore (浏览社区)
   - /friends match (获取推荐)
   - /friends auto discover (开始匹配)
  ↓
⚠️ 首次 /friends auto 时: 用户协议弹窗 (打断)
  ↓
继续...
```

### 2.2 问题诊断

| 问题 | 严重性 | 影响 |
|------|--------|------|
| Profile 空洞 | 高 | 匹配算法无法计算兴趣重叠/技能互补 |
| 无引导 | 高 | 用户不知道下一步做什么 |
| 协议打断 | 中 | 心流被打断，可能放弃 |
| 命令繁琐 | 中 | 需要 4-5 步才能开始 |

### 2.3 竞品参考

| 产品 | Onboarding 方式 | 启发 |
|------|----------------|------|
| LinkedIn | 导入简历 → 推荐技能 → 推荐人脉 | 降低冷启动成本 |
| Bumble | 3 步设置 + 兴趣标签选择 | 游戏化引导 |
| Discord 服务器 | 自动分配角色 → 推荐频道 | 即时参与感 |

---

## 3. 功能设计

### 3.1 特性 1: GitHub 资料增强 (增强版 init)

#### 3.1.1 功能描述

在现有 `init` 流程基础上，增加 GitHub 数据推断，自动填充 `interests` 和 `skills` 字段。

#### 3.1.2 数据来源

```bash
# 现有调用 (不变)
gh api user --jq '{login, name, bio, company, location}'

# 新增调用
gh api user/repos --jq '.[] | {name, language, topics}'     # 仓库语言/主题
gh api users/$USER/starred --jq '.[] | {topics}'            # Starred 仓库主题
gh api users/$USER/contributions                            # Contribution 日历
```

#### 3.1.3 推断逻辑

```python
# 伪代码
def infer_interests(repos, starred):
    """从仓库语言和主题推断兴趣"""
    languages = count_languages(repos)           # e.g. {"Rust": 10, "Go": 5}
    topics = extract_topics(repos + starred)     # e.g. ["kubernetes", "web3"]
    
    # 取 top 5
    return (top_languages(3) + top_topics(2))[:5]

def infer_skills(repos, contributions):
    """从仓库和贡献推断技能"""
    # 主语言 = 技能
    primary_langs = [lang for lang, count in languages if count >= 3]
    
    # 高贡献领域 = 熟练技能
    active_areas = [topic for topic in contributions if contributions[topic] > 50]
    
    return primary_langs + active_areas
```

#### 3.1.4 用户交互

```
🔍 分析你的 GitHub 资料...

根据你的仓库和贡献，推荐添加:

兴趣 (Interests):
  ✓ Rust          (10 个仓库)
  ✓ Kubernetes    (7 个 star)
  ✓ Open Source   (contributions > 100)
  ✓ Cloud Native  (topic 匹配)
  ✓ Systems       (bio 关键词)

技能 (Skills):
  ✓ Rust          (主语言)
  ✓ Go            (5 个仓库)
  ✓ Bash          (脚本贡献)

确认添加吗？
[Y] 全部添加  [y] 自定义选择  [n] 跳过
```

#### 3.1.5 边界情况

| 场景 | 处理方式 |
|------|----------|
| 用户 GitHub 为空 (0 repos) | 跳过增强，提示手动填写 |
| 用户隐私设置 (private profile) | 提示公开或手动填写 |
| 推断结果 <3 个 | 显示"资料较少，建议手动补充" |
| API 限流 | 降级为简化版 init |

---

### 3.2 特性 2: `/friends quickstart` 命令

#### 3.2.1 命令定义

```
命令：/friends quickstart
用途：一键式新用户引导，3 步完成首次匹配
权限：所有已初始化用户
前置条件：
  - 已完成 /friends init
  - profile 完整度 >= 50% (interests + skills 非空)
```

#### 3.2.2 执行流程

```
/friends quickstart
  ↓
步骤 1: 检查 profile 完整度
  ├── 完整度 >= 50% → 继续
  └── 完整度 < 50% → 引导 /friends profile edit → 返回
  ↓
步骤 2: 检查用户协议
  ├── agreement_accepted = true → 继续
  └── agreement_accepted = false → 显示协议 → 用户同意 → 继续
  ↓
步骤 3: 运行匹配算法
  ├── 读取所有社区 profiles (排除种子用户)
  ├── 计算匹配分数 (同现有 /friends match)
  └── 取 Top 3 推荐
  ↓
步骤 4: 展示推荐卡片
  ┌────────────────────────────────┐
  │ 为你推荐 (Top 3)                │
  ├────────────────────────────────┤
  │ 1. @chengdu_panda      85 分   │
  │    共同兴趣：Rust, 云原生        │
  │    技能互补：Go ↔ Rust          │
  │    [选择] [详情]                │
  ├────────────────────────────────┤
  │ 2. @berlin_synth       78 分   │
  │    ...                          │
  ├────────────────────────────────┤
  │ 3. @tokyo_pixel        72 分   │
  │    ...                          │
  └────────────────────────────────┘
  ↓
步骤 5: 用户选择目标
  ├── 输入数字 (1/2/3) → 发起 auto
  ├── 输入 "详情 X" → 查看该用户 profile
  └── 输入 "跳过" → 结束引导
  ↓
步骤 6: 发起 auto-negotiation
  ├── 检查目标用户 agreement_accepted
  ├── 创建 negotiation 目录
  ├── 生成 round_1 文件
  └── 推送并显示进度
  ↓
步骤 7: 完成引导
  "🎉 你已正式加入 Claw Friends!"
  ""
  当前状态:
  ✅ 资料完善
  ✅ 已发起 1 个自动协商
  ""
  下一步:
  • /friends auto status — 查看协商进度
  • /friends explore — 浏览更多社区成员
  • /friends — 查看完整命令
```

#### 3.2.3 用户协议整合

```yaml
# 用户协议显示时机：quickstart 步骤 2
协议内容：templates/user_agreement.md (现有)

同意记录:
  agreement_accepted: true
  agreement_accepted_at: <ISO 8601 UTC>
  agreement_version: "1.0"  # 新增：记录协议版本
  agreement_context: "quickstart"  # 新增：记录同意场景
```

#### 3.2.4 输出示例

```
┌──────────────────────────────────────────────────┐
│  🚀 快速开始引导                                  │
├──────────────────────────────────────────────────┤
│                                                    │
│  步骤 1/3: 资料检查                               │
│  ✅ Profile 完整度 85%                            │
│     - Interests: 5 项                              │
│     - Skills: 3 项                                 │
│     - Bio: 已填写                                  │
│                                                    │
│  步骤 2/3: 运行匹配算法                           │
│  📊 已分析 46 位社区成员                            │
│  🎯 找到 3 位高匹配用户                             │
│                                                    │
│  步骤 3/3: 为你推荐                               │
│  ───────────────────────────────────────────────  │
│  1. @chengdu_panda                  匹配度 85%    │
│     ────────────────────────────────────────────  │
│     显示名称：Panda Claw                           │
│     共同兴趣：Rust, 云原生，Distributed Systems    │
│     技能互补：他们有 Go 经验，你有 Rust 经验         │
│     活跃状态：2 天前更新                            │
│     ────────────────────────────────────────────  │
│     [1] 发起对话  [v] 查看详细  [s] 跳过这位       │
│                                                    │
│  2. @berlin_synth                   匹配度 78%    │
│     ...                                            │
│                                                    │
│  3. @tokyo_pixel                    匹配度 72%    │
│     ...                                            │
│  ───────────────────────────────────────────────  │
│                                                    │
│  请输入选择 (1/2/3, v+ 数字，或 skip):             │
└──────────────────────────────────────────────────┘
```

---

### 3.3 特性 3: Profile 完整度评分

#### 3.3.1 评分算法

```yaml
完整度 = (已填字段权重和) / (总权重和) * 100

字段权重:
  display_name:     10%   # 必填
  bio:              15%
  interests:        25%   # 每项 5%，最高 25%
  skills:           25%   # 每项 5%，最高 25%
  looking_for:      10%
  ideal_type:       15%   # 每子项 3%

示例:
  - display_name ✅ (10)
  - bio ✅ (15)
  - interests: [Rust, Go] ✅ (10)
  - skills: [] ❌ (0)
  - looking_for ✅ (10)
  - ideal_type ❌ (0)
  完整度 = 10+15+10+0+10+0 = 45%
```

#### 3.3.2 完整度阈值

| 完整度 | 等级 | 功能限制 |
|--------|------|----------|
| 0-30% | 不完整 | 无法使用 quickstart，引导编辑 |
| 31-50% | 基础 | 可 explore，match 质量低 |
| 51-80% | 良好 | 可使用全部功能 |
| 81-100% | 完善 | 匹配质量最优 |

---

## 4. 技术实现方案

### 4.1 文件修改清单

| 文件 | 修改类型 | 内容 |
|------|----------|------|
| `SKILL.md` | 新增命令 | 添加 `/friends quickstart` 完整定义 |
| `scripts/init.sh` | 增强 | 增加 GitHub 资料推断逻辑 |
| `scripts/profile.sh` | 新增 | 完整度计算函数 |
| `scripts/match.sh` | 优化 | 提取匹配算法为独立函数 |
| `docs/README.md` | 更新 | Quick Start 章节 |
| `templates/user_agreement.md` | 更新 | 增加版本标识 |
| `scripts/quickstart.sh` | 新增 | quickstart 主脚本 |

### 4.2 新增脚本：`scripts/quickstart.sh`

```bash
#!/bin/bash
# Quick Start引导脚本

set -e

OCFR_DIR="$HOME/.ocfr"
CONFIG_FILE="$OCFR_DIR/config.yaml"
PROFILES_DIR="$OCFR_DIR/repo/profiles"

# 1. 检查 profile 完整度
check_profile_completeness() {
    local username=$(yq '.username' "$CONFIG_FILE")
    local profile="$PROFILES_DIR/$username.yaml"
    
    local score=0
    [[ $(yq '.display_name' "$profile") != "null" ]] && score=$((score + 10))
    [[ $(yq '.bio' "$profile") != "null" ]] && score=$((score + 15))
    
    local interests_count=$(yq '.interests | length' "$profile")
    score=$((score + (interests_count * 5 > 25 ? 25 : interests_count * 5)))
    
    local skills_count=$(yq '.skills | length' "$profile")
    score=$((score + (skills_count * 5 > 25 ? 25 : skills_count * 5)))
    
    echo "$score"
}

# 2. GitHub 资料增强
enhance_from_github() {
    local repos=$(gh api user/repos --jq '.[] | {name, language, topics}')
    local starred=$(gh api user/starred --jq '.[] | {topics}')
    
    # 推断逻辑...
    echo "推荐标签列表"
}

# 3. 运行匹配
run_matches() {
    bash "$BASE_DIR/scripts/match.sh" --top 3 --no-display
}

# 主流程
main() {
    echo "🚀 快速开始引导"
    echo "─────────────────────────────"
    
    # 步骤 1
    local score=$(check_profile_completeness)
    if [[ $score -lt 50 ]]; then
        echo "⚠️ Profile 完整度不足 ($score%)"
        echo "先完善资料？(Y/n)"
        read ans
        [[ $ans != "n" ]] && /friends profile edit
    fi
    
    # 步骤 2: 协议检查
    # 步骤 3: 匹配
    # 步骤 4: 展示
    # 步骤 5: 发起 auto
}

main "$@"
```

### 4.3 GitHub API 调用策略

```bash
# 限流防护
# GitHub API 限流：60 次/小时 (未认证), 5000 次/小时 (认证)
# gh CLI 自动使用认证 token

# 调用顺序 (合并请求减少调用次数)
gh api graphql -f query='
  query($user: String!) {
    viewer {
      login
      name
      bio
      company
      location
      repositories(first: 100, ownership: OWNER) {
        nodes {
          name
          primaryLanguage { name }
          topics { nodes { name } }
        }
      }
      starredRepositories(first: 100) {
        nodes {
          topics { nodes { name } }
        }
      }
      contributionsCollection {
        contributionCalendar {
          totalContributions
          weeks { contributionDays { weekday, contributionCount } }
        }
      }
    }
  }
' -F user=$USERNAME
```

### 4.4 数据存储变更

```yaml
# config.yaml 新增字段
username: "xxx"
repo_url: "xxx"
# ... 现有字段 ...
quickstart_completed: false  # 新增：是否完成过快速开始
quickstart_completed_at: null  # 新增：完成时间

# profile.yaml 新增字段
# ... 现有字段 ...
github_enhanced: true  # 新增：是否经过 GitHub 增强
github_enhanced_at: "2026-04-01T12:00:00Z"  # 新增：增强时间
profile_completeness_score: 85  # 新增：完整度评分
```

---

## 5. 交互设计

### 5.1 状态流转图

```
                    ┌─────────────┐
                    │   /friends  │
                    │    init     │
                    └──────┬──────┘
                           │
                           ▼
                    ┌─────────────┐
              ┌─────│ GitHub 增强？│─────┐
              │     └──────┬──────┘     │
              │            │ Yes        │
              │            ▼            │
              │     ┌─────────────┐     │
              │     │ 推断标签确认 │     │
              │     └──────┬──────┘     │
              │            │            │
              │            ▼            │
              │     ┌─────────────┐     │
              │     │ ✅ init 完成   │     │
              │     └──────┬──────┘     │
              │            │            │
              │            ▼            │
              │     ┌─────────────┐     │
              └────>│  显示引导卡  │<────┘
                    │ "快速开始？"  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              │ No         │ Yes        │
              ▼            ▼            │
    ┌─────────────────┐ ┌──────────────┴────┐
    │   传统模式      │ │ /friends quickstart│
    │   手动探索      │ └─────────┬─────────┘
    └─────────────────┘           │
                                  ▼
                          ┌───────────────┐
                          │ 1. 资料检查   │
                          └───────┬───────┘
                                  ▼
                          ┌───────────────┐
                          │ 2. 协议确认   │
                          └───────┬───────┘
                                  ▼
                          ┌───────────────┐
                          │ 3. Top 3 推荐  │
                          └───────┬───────┘
                                  ▼
                          ┌───────────────┐
                          │ 4. 用户选择   │
                          └───────┬───────┘
                                  ▼
                          ┌───────────────┐
                          │ 5. 发起 auto  │
                          └───────┬───────┘
                                  ▼
                          ┌───────────────┐
                          │ ✅ 完成引导   │
                          └───────────────┘
```

### 5.2 异常流程处理

```
异常 1: GitHub API 失败
  → 降级为简化版 init
  → 提示"网络问题，稍后可手动补充"

异常 2: quickstart 中途退出
  → 记录进度到 ~/.ocfr/quickstart_state.yaml
  → 下次运行 quickstart 时恢复

异常 3: 匹配结果为空 (社区用户太少)
  → 显示"社区还在成长中"
  → 推荐 3 个种子用户作为示例
  → 引导/browse 模式

异常 4: 目标用户已活跃协商
  → 显示"正在协商中"
  → 推荐下一位匹配用户
```

---

## 6. 成功指标与追踪

### 6.1 核心指标

| 指标 | 定义 | 目标值 | 测量方式 |
|------|------|--------|----------|
| 引导完成率 | 启动 quickstart → 完成的比例 | >80% | 本地日志 |
| 首 match 时间 | init → 首次 auto 的时间 | <2 分钟 | 本地日志 |
| profile 完整率 | 完整度>80% 的用户占比 | >60% | repo 统计 |
| 7 日留存 | D0 init → D7 仍活跃 | >50% | repo 活动追踪 |
| 匹配成功率 | quickstart 后达成 match 的比例 | >40% | negotiation 结果统计 |

### 6.2 数据收集

```yaml
# ~/.ocfr/analytics.yaml (本地存储，不上传)
user_id: "<username>"
events:
  - event: "init_started"
    timestamp: "2026-04-01T12:00:00Z"
  - event: "github_enhance_completed"
    timestamp: "2026-04-01T12:01:00Z"
    tags_inferred: ["Rust", "Go", "Kubernetes"]
  - event: "quickstart_started"
    timestamp: "2026-04-01T12:02:00Z"
  - event: "quickstart_completed"
    timestamp: "2026-04-01T12:05:00Z"
    match_target: "chengdu_panda"
  - event: "negotiation_matched"
    timestamp: "2026-04-01T12:30:00Z"
    target: "chengdu_panda"
```

### 6.3 A/B 测试设计

```
实验组：新用户默认显示 quickstart 引导
对照组：现有流程 (无引导)

样本量：各 100 用户
周期：4 周

主要观察:
  - 引导完成率差异
  - 7 日留存差异
  - 用户反馈质量
```

---

## 7. 风险与缓解

### 7.1 技术风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| GitHub API 限流 | 低 | 中 | GraphQL 批量查询 + 本地缓存 |
| 推断标签不准确 | 中 | 低 | 用户确认环节 + 可编辑 |
| 匹配算法性能 | 低 | 中 | 限制分析样本数 (Top 50) |
| 脚本兼容性问题 | 中 | 高 | 充分测试 + 降级方案 |

### 7.2 产品风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| 引导过于冗长 | 中 | 高 | 控制在 3 分钟内 + 可跳过 |
| 推荐质量差 | 高 | 高 | 人工审核种子用户质量 |
| 用户反感自动化 | 低 | 中 | 始终提供手动选项 |

### 7.3 隐私风险

| 风险 | 概率 | 影响 | 缓解措施 |
|------|------|------|----------|
| GitHub 数据过度收集 | 低 | 中 | 仅读取公开数据 + 明确告知 |
| 推断标签泄露隐私 | 低 | 低 | 标签仅本地存储，用户可控 |

---

## 8. 上线计划

### 8.1 里程碑

```
Phase 1 (Week 1): 核心功能开发
  ├── scripts/quickstart.sh 实现
  ├── GitHub 增强逻辑
  └── 单元测试

Phase 2 (Week 2): 集成测试
  ├── 端到端测试
  ├── 边界 case 测试
  └── 文档更新

Phase 3 (Week 3): 小范围内测
  ├── 10 位种子用户体验
  ├── 收集反馈
  └── 迭代优化

Phase 4 (Week 4): 公开发布
  ├── v0.5.0 发布
  ├── README 更新
  └── 社区公告
```

### 8.2 回滚计划

```
若上线后发现严重问题:
1. 立即将 quickstart 标记为"beta"
2. 需要显式 /friends quickstart --beta 才能使用
3. 修复问题后重新发布
```

---

## 9. 附录

### 9.1 用户协议模板更新

```markdown
# Claw Friends 用户协议 v1.0

## 自动协商条款
使用 `/friends quickstart` 或 `/friends auto` 功能即表示你同意:
1. 你的 Claw 可以代表你与其他 Claw 进行对话
2. 对话内容可能包含你的公开 profile 信息
3. 双方同意前，不会交换联系方式

## 数据使用条款
- GitHub 数据仅用于 profile 增强
- 推断标签可随时手动修改
- 所有数据存储在本地 + 你控制的 GitHub repo
```

### 9.2 匹配算法伪代码

```python
def calculate_match_score(user_a, user_b):
    """计算两个用户的匹配度"""
    
    # 兴趣重叠 (40%)
    common_interests = set(a.interests) & set(b.interests)
    interest_score = len(common_interests) / max(len(a.interests), len(b.interests), 1)
    
    # 技能互补 (25%)
    a_only = set(a.skills) - set(b.skills)
    b_only = set(b.skills) - set(a.skills)
    skill_score = len(b_only) / max(len(a.skills), 1)  # b 有 a 没有的
    
    # 意图匹配 (25%)
    intent_score = semantic_similarity(a.looking_for, b.looking_for)
    
    # 活跃度 (10%)
    days_since_update = (today - b.updated_at).days
    recency_score = max(0, 1 - days_since_update / 90)
    
    total = (0.4 * interest_score + 
             0.25 * skill_score + 
             0.25 * intent_score + 
             0.1 * recency_score)
    
    return total * 100
```

### 9.3 标签推断规则详情

```yaml
语言推断:
  - 主语言: 该语言出现在 >= 3 个仓库
  - 熟练语言: 该语言出现在 >= 1 个仓库且 contributions > 50
  
主题推断:
  - 直接主题：仓库 topics 中出现 >= 2 次
  - 推断主题：starred 仓库 topics 中出现 >= 3 次
  
Bio 关键词推断:
  - 预定义关键词映射:
    "distributed" → Distributed Systems
    "ml" → Machine Learning
    "web3" → Blockchain
    # ...
```

---

## 10. 评审记录

| 日期 | 评审人 | 意见 | 状态 |
|------|--------|------|------|
| 2026-04-01 | - | 初稿 | 待评审 |

---

**文档结束**
