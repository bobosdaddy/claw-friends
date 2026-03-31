# Claw Friends

A decentralized social networking skill for AI assistant users. Find friends by interests, share profiles, and exchange end-to-end encrypted messages — all through a shared GitHub repository. No server required.

Compatible with **OpenClaw**, **QClaw**, **KimiClaw**, **CoPaw**, and **Claude Code**.

## How It Works

```
You (any Claw + Skill)  <--git-->  GitHub Repo  <--git-->  Friends (any Claw + Skill)
```

- **Profiles** are YAML files stored in a shared GitHub repo
- **Matching** runs locally using your AI assistant's LLM to analyze compatibility
- **Messages** are encrypted with RSA+AES before being pushed to the repo
- **Private keys** never leave your machine

## Prerequisites

| Tool | Min Version | Install |
|------|-------------|---------|
| git | 2.20+ | Pre-installed on most systems |
| openssl | 1.1+ | `brew install openssl` / `apt install openssl` |
| gh (GitHub CLI) | 2.0+ | `brew install gh` / `apt install gh` |

You also need a GitHub account authenticated via `gh auth login`.

## Installation

### OpenClaw / KimiClaw

```bash
cp -r claw-friends ~/.openclaw/skills/
```

### QClaw

```bash
cp -r claw-friends ~/.openclaw/skills/
```

QClaw also reads `openclaw.plugin.json` for native plugin validation — it's already included in this package.

### CoPaw

```bash
cp -r claw-friends ~/.copaw/customized_skills/
```

### Claude Code

```bash
cp -r claw-friends ~/.claude/skills/
```

Or project-scoped (current working directory):

```bash
cp -r claw-friends .claude/skills/
```

## Quick Start

```
/friends init                    # Set up your profile and keys
/friends explore                 # Browse community members
/friends match                   # Get smart recommendations
/friends request alice-dev       # Send a friend request
/friends msg alice-dev "Hello!"  # Send an encrypted message
```

## Commands

### Setup

| Command | Description |
|---------|-------------|
| `/friends init` | First-time setup: generate RSA keys, clone repo, create profile |
| `/friends init --rekey` | Regenerate keys (old messages become unreadable) |
| `/friends sync` | Manually sync data with remote repo |

### Profile

| Command | Description |
|---------|-------------|
| `/friends profile` | View your own profile card |
| `/friends profile edit` | Edit your profile interactively |
| `/friends profile view <user>` | View another user's profile |

### Discovery

| Command | Description |
|---------|-------------|
| `/friends explore` | Browse all community members |
| `/friends explore --interest rust` | Filter by interest |
| `/friends explore --skill Python` | Filter by skill |
| `/friends match` | Get Top 5 smart match recommendations |
| `/friends match --top 10` | Get Top 10 recommendations |

### Social

| Command | Description |
|---------|-------------|
| `/friends request <user>` | Send a friend request |
| `/friends requests` | View and handle pending requests |

### Messaging

| Command | Description |
|---------|-------------|
| `/friends msg inbox` | View message inbox |
| `/friends msg <user>` | View conversation history |
| `/friends msg <user> "message"` | Send an encrypted message |

## Platform Compatibility

| Feature | OpenClaw | QClaw | KimiClaw | CoPaw | Claude Code |
|---------|----------|-------|----------|-------|-------------|
| All commands | ✅ | ✅ | ✅ | ✅ | ✅ |
| Auto dependency check | ✅ | ✅ | ✅ | — | — |
| Plugin manifest | — | ✅ | — | — | — |
| Skills dir | `~/.openclaw/skills/` | `~/.openclaw/skills/` | `~/.openclaw/skills/` | `~/.copaw/customized_skills/` | `~/.claude/skills/` |

Core scripts (`init.sh`, `sync.sh`, `crypto.sh`) use only `bash`, `git`, and `openssl` — platform-agnostic.

## Data Storage

### Remote (GitHub Repo)

```
claw-friends/               # Shared GitHub repository
├── profiles/               # Public user profiles
│   ├── alice-dev.yaml
│   └── bob-z.yaml
├── matches/                # Friend requests
│   ├── alice-dev/
│   │   └── from_bob-z.yaml
│   └── bob-z/
│       └── from_alice-dev.yaml
└── messages/               # Encrypted messages
    ├── alice-dev/
    │   └── from_bob-z_20260331T100000Z.yaml
    └── bob-z/
        └── from_alice-dev_20260331T093000Z.yaml
```

### Local (`~/.ocfr/`)

```
~/.ocfr/
├── config.yaml             # Your username, repo URL, settings
├── keys/
│   ├── private.pem         # RSA-2048 private key (never uploaded!)
│   └── public.pem          # RSA-2048 public key (embedded in profile)
├── repo/                   # Local clone of the shared repo
└── sent/                   # Plaintext copies of your sent messages (local only)
    └── bob-z/
        └── 20260331T100000Z.txt
```

## Security

### Encryption

Messages use **hybrid encryption** (RSA-2048 + AES-256-CBC):

1. A random AES-256 key is generated for each message
2. The message body is encrypted with AES-256-CBC
3. The AES key is encrypted with the recipient's RSA public key (OAEP/SHA-256)
4. Only the recipient can decrypt (using their local private key)

### Key Management

- **Private key** stays in `~/.ocfr/keys/private.pem` with `chmod 600`
- **Public key** is published in your profile YAML
- The skill explicitly instructs the AI to **never read or transmit the private key contents**
- If you need to regenerate keys: `/friends init --rekey` (old messages become unreadable)

## Limitations

- **Not real-time**: Messages sync on each command run, not instantly
- **Text only**: No file or image attachments
- **~1,000 user cap**: Git repos become slow with too many files
- **No message recall**: Once pushed, messages cannot be unsent
- **No group chat**: v0.1 supports 1-on-1 messaging only

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Not initialized" | Run `/friends init` |
| Sync fails | Check network; run `/friends sync` manually |
| Can't decrypt messages | Private key may have changed. Messages from before a rekey are lost. |
| Push conflicts | Skill auto-retries with rebase. If persistent, run `/friends sync`. |

## License

MIT-0
