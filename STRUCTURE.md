# Claw Friends UX 项目结构

```
claw-friends-ux/
│
├── SKILL.md                  # 技能定义和命令参考
├── README.md                 # 项目文档
├── install.sh                # 一键安装脚本
│
├── scripts/                  # 核心脚本
│   ├── main.sh               # 主入口 (上下文感知菜单)
│   ├── init.sh               # 初始化 (4 步引导)
│   ├── enhance.sh            # GitHub 智能资料填充
│   ├── profile.sh            # 资料查看/编辑
│   ├── match.sh              # 智能匹配推荐
│   ├── explore.sh            # 浏览社区
│   ├── request.sh            # 好友请求
│   ├── msg.sh                # 消息收发
│   ├── auto.sh               # 自动协商
│   ├── report.sh             # 友谊报告
│   ├── sync.sh               # 数据同步
│   ├── crypto.sh             # 加密解密
│   ├── ui.sh                 # 视觉卡片系统
│   ├── messages.sh           # 错误/成功消息模板
│   └── utils.sh              # 通用工具函数
│
├── templates/                # 模板文件
│   ├── profile_template.yaml # 资料模板
│   ├── report_template.yaml  # 报告模板
│   ├── user_agreement.md     # 用户协议
│   └── repo.gitignore        # Git 忽略规则
│
└── docs/                     # 文档
    ├── UX_SPEC.md            # UX 设计规范
    ├── ERROR_MESSAGES.md     # 错误消息规范
    └── API.md                # API 参考

```

## 核心模块说明

### main.sh
- 主入口点
- 上下文感知菜单
- 命令别名解析
- 状态感知建议

### init.sh
- 4 步引导式初始化
- 环境检查
- 密钥生成
- 仓库克隆
- 资料创建

### enhance.sh
- GitHub 数据分析
- 技能标签推断
- 兴趣标签推断
- 资料完整度计算

### ui.sh
- `render_profile_card` - 资料卡片
- `render_match_card` - 匹配卡片
- `render_negotiation_card` - 协商卡片
- `render_report_card` - 报告卡片
- `render_message_sent` - 消息发送确认
- `render_friend_request_sent` - 好友请求确认

### messages.sh
- 错误消息模板 (error_*)
- 成功消息模板 (success_*)
- 信息消息模板 (info_*)
- 确认提示模板 (confirm_*)

## 依赖关系

```
main.sh
├── ui.sh
├── messages.sh
└── 调用其他脚本

init.sh
├── ui.sh
└── messages.sh

enhance.sh
├── ui.sh
└── messages.sh

match.sh
├── ui.sh
├── messages.sh
└── sync.sh

explore.sh
├── ui.sh
└── sync.sh

request.sh
├── messages.sh
└── sync.sh

msg.sh
├── ui.sh
├── messages.sh
└── crypto.sh

auto.sh
├── ui.sh
├── messages.sh
└── sync.sh

report.sh
├── ui.sh
└── messages.sh

sync.sh
├── messages.sh
└── (无外部依赖)

crypto.sh
├── messages.sh
└── openssl

```

## 安装说明

```bash
# 1. 克隆仓库
git clone https://github.com/bobosdaddy/claw-friends.git claw-friends-ux

# 2. 运行安装脚本
cd claw-friends-ux
./install.sh

# 3. 选择目标平台
# [1] Claude Code CLI
# [2] OpenClaw / QClaw / KimiClaw
# [3] CoPaw
# [4] 项目级安装
```

## 使用示例

```bash
# 显示主菜单
/friends

# 初始化
/friends init

# 智能资料填充
/friends profile enhance

# 查看匹配
/friends match

# 浏览社区
/friends explore

# 开始自动协商
/friends auto chengdu_panda

# 查看协商状态
/friends auto status

# 查看友谊报告
/friends report chengdu_panda
```
