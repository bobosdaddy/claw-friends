---
name: claw-friends
description: >
  Social networking skill for AI assistant users across OpenClaw, QClaw, KimiClaw, CoPaw, and Claude Code.
  Find friends by interests and skills, share profiles, get smart match recommendations,
  and exchange end-to-end encrypted messages — all through a shared GitHub repository.
  No server required.
compatibility: "Requires git, openssl, and gh (GitHub CLI). Install gh via: brew install gh"
license: MIT-0
metadata:
  openclaw:
    emoji: "\U0001F99E"
    requires:
      bins: ["git", "openssl", "gh"]
    install:
      - id: gh-cli
        kind: brew
        formula: gh
        bins: ["gh"]
        label: "Install GitHub CLI (brew install gh)"
  clawdbot:
    emoji: "\U0001F99E"
    requires:
      bins: ["git", "openssl", "gh"]
    install:
      - id: gh-cli
        kind: brew
        formula: gh
        bins: ["gh"]
        label: "Install GitHub CLI (brew install gh)"
  copaw:
    emoji: "\U0001F99E"
user-invocable: true
---

# Claw Friends

A decentralized social networking skill for the AI assistant community. Uses a shared GitHub repository as the data layer — no server needed. Compatible with OpenClaw, QClaw, KimiClaw, CoPaw, and Claude Code.

## When to Activate

Activate when the user mentions any of: "friends", "friend", "social", "match", "profile", "buddy", "connect", "networking", "penpal", or uses any `/friends` command.

## Command Reference

| Command | Description |
|---------|-------------|
| `/friends init` | First-time setup: generate keys, clone repo, create profile |
| `/friends profile` | View your own profile card |
| `/friends profile edit` | Edit your profile interactively |
| `/friends profile view <user>` | View another user's profile card |
| `/friends explore` | Browse all community members |
| `/friends match` | Get smart match recommendations (Top 5) |
| `/friends request <user>` | Send a friend request |
| `/friends requests` | View and handle pending friend requests |
| `/friends msg inbox` | View message inbox |
| `/friends msg <user> [message]` | Send message or view conversation history |
| `/friends sync` | Manually sync data with remote repo |

## Configuration

- **Data directory**: `~/.ocfr/`
- **Repo clone**: `~/.ocfr/repo/`
- **RSA keys**: `~/.ocfr/keys/private.pem`, `~/.ocfr/keys/public.pem`
- **Config**: `~/.ocfr/config.yaml`
- **Default repo**: `https://github.com/bobosdaddy/claw-friends-data` (configurable during init)

## Implementation Instructions

### General Rules

1. **Always sync before reading remote data.** Run `bash {baseDir}/scripts/sync.sh pull` before any command that reads profiles, matches, or messages.
2. **Always sync after writing remote data.** Run `bash {baseDir}/scripts/sync.sh push` after any command that creates or modifies files in the repo.
3. **Never read or transmit the private key.** The file `~/.ocfr/keys/private.pem` must only be passed as a path argument to `openssl` commands via `{baseDir}/scripts/crypto.sh`. Never read its contents, log it, or include it in any output.
4. **Validate init state.** Before any command except `init`, check that `~/.ocfr/config.yaml` exists. If not, tell the user to run `/friends init` first.
5. **Use immutable writes.** When updating a YAML file, generate the complete new content and overwrite the file. Do not patch in place.
6. **Handle git conflicts.** If push fails, run `bash {baseDir}/scripts/sync.sh pull` then retry push. Max 3 retries.

---

### /friends init

**Purpose**: First-time setup for a new user.

**Steps**:

1. Check prerequisites:
   ```bash
   command -v git && command -v openssl && command -v gh
   gh auth status
   ```
   If any check fails, tell the user what to install or configure and stop.

2. Get the GitHub username:
   ```bash
   gh api user --jq '.login'
   ```
   Store as `$USERNAME`.

3. Ask the user to fill in their profile interactively. Collect:
   - `display_name` (required, string)
   - `bio` (required, max 200 chars)
   - `interests` (required, 1-10 tags as comma-separated list)
   - `skills` (required, 1-10 tags as comma-separated list)
   - `looking_for` (required, 1-5 items as comma-separated list)
   - `platforms` (optional: telegram, discord, wechat, email)

4. Generate RSA key pair:
   ```bash
   bash {baseDir}/scripts/init.sh keygen
   ```

5. Clone the repo (or pull if already cloned):
   ```bash
   bash {baseDir}/scripts/init.sh clone [repo_url]
   ```
   Default repo: `https://github.com/openclaw/friends`
   The user may specify a different repo URL.

6. Read the generated public key:
   ```bash
   cat ~/.ocfr/keys/public.pem
   ```

7. Generate the profile YAML with all collected fields + the public key + `updated_at` set to current UTC date. Write it to `~/.ocfr/repo/profiles/$USERNAME.yaml`.

8. Write the local config to `~/.ocfr/config.yaml`:
   ```yaml
   username: "<USERNAME>"
   repo_url: "<REPO_URL>"
   repo_path: "~/.ocfr/repo"
   auto_sync: true
   message_retention: 100
   ```

9. Sync (push the new profile):
   ```bash
   bash {baseDir}/scripts/sync.sh push
   ```

10. Show the user their rendered profile card and confirm success.

**If already initialized**: Check if `~/.ocfr/config.yaml` exists. If so, ask "You're already set up. Do you want to reconfigure?" If yes, proceed. If no, stop.

**--rekey flag**: If the user runs `/friends init --rekey`, only regenerate keys and update the public_key field in the existing profile. Warn that old encrypted messages will become unreadable.

---

### /friends profile

**Purpose**: View your own profile card.

**Steps**:
1. Read `~/.ocfr/config.yaml` to get `$USERNAME`.
2. Read `~/.ocfr/repo/profiles/$USERNAME.yaml`.
3. Render as a formatted card:

```
┌──────────────────────────────────────┐
│  {display_name} (@{username})        │
│  ──────────────────────────────────  │
│  {bio}                               │
│                                      │
│  Interests: {interests joined by ,}  │
│  Skills:    {skills joined by ,}     │
│  Looking for: {looking_for}          │
│  Contact: {platforms if any}         │
│                                      │
│  Updated: {updated_at}               │
└──────────────────────────────────────┘
```

---

### /friends profile edit

**Purpose**: Edit your profile interactively.

**Steps**:
1. Sync pull.
2. Read current profile YAML.
3. Show the current profile card to the user.
4. Ask: "What would you like to change?" Let the user describe changes in natural language.
5. Apply changes to the profile fields. Update `updated_at` to current UTC date.
6. Write the new complete YAML file (immutable write).
7. Sync push.
8. Show the updated profile card.

---

### /friends profile view \<user\>

**Purpose**: View another user's profile.

**Steps**:
1. Sync pull.
2. Check if `~/.ocfr/repo/profiles/<user>.yaml` exists. If not, tell the user "User not found."
3. Read and render the profile card (same format as own profile, but omit public_key from display).

---

### /friends explore

**Purpose**: Browse all community members.

**Steps**:
1. Sync pull.
2. List all `~/.ocfr/repo/profiles/*.yaml` files.
3. Read each file, exclude your own username.
4. Sort by `updated_at` descending (most recently active first).
5. Display a paginated summary list (10 per page):

```
Community Members ({total} people)
──────────────────────────────────
1. {display_name} (@{username})
   {skills[0:3] joined} | {looking_for[0]}

2. {display_name} (@{username})
   {skills[0:3] joined} | {looking_for[0]}
...
```

6. If the user provides filter flags like `--interest rust` or `--skill Python`, filter the list accordingly (case-insensitive substring match).
7. Suggest: "Use `/friends profile view <user>` for details, or `/friends match` for smart recommendations."

---

### /friends match

**Purpose**: Smart match recommendations using LLM analysis.

**Steps**:
1. Sync pull.
2. Read your own profile.
3. Read all other profiles.
4. For each candidate, compute a match score:

   **interests_score (40% weight)**:
   ```
   intersection = your_interests AND their_interests (case-insensitive)
   score = len(intersection) / max(len(yours), len(theirs))
   ```

   **skills_complementary (25% weight)**:
   ```
   they_have_you_dont = their_skills - your_skills (case-insensitive)
   score = len(they_have_you_dont) / max(len(your_skills), 1)
   cap at 1.0
   ```

   **intent_match (25% weight)**:
   Analyze both users' `looking_for` fields. Judge semantic compatibility on a 0-1 scale. Examples:
   - "open-source collaborator" + "looking for contributors" = 0.9
   - "study buddy" + "research partner" = 0.8
   - "job referral" + "pair programming" = 0.2

   **recency_score (10% weight)**:
   ```
   days_since = (today - their_updated_at).days
   score = max(0, 1 - days_since / 90)
   ```

   **total = 0.4 * interests + 0.25 * skills + 0.25 * intent + 0.1 * recency**

5. Sort by total score descending. Take top 5 (or `--top N`).
6. For each recommendation, generate a one-sentence match reason in the user's language.
7. Render:

```
Match Recommendations
┌──────────────────────────────────────┐
│ 1. {name} (@{user})       {score}%  │
│    "{match_reason}"                  │
│    Interests: {shared_interests}     │
│    -> /friends request {user}        │
├──────────────────────────────────────┤
│ 2. ...                               │
└──────────────────────────────────────┘
```

---

### /friends request \<user\>

**Purpose**: Send a friend request.

**Steps**:
1. Sync pull.
2. Validate target user exists in `profiles/`.
3. Check for duplicate: if `matches/<user>/from_<me>.yaml` exists and `status: pending`, tell the user they already sent a request.
4. **Check for mutual request**: if `matches/<me>/from_<user>.yaml` exists with `status: pending`, auto-accept both directions. Tell the user: "{user} already sent you a request! You're now friends. Use `/friends msg {user}` to chat."
5. If no duplicate or mutual, ask: "Send a message with your request? (optional)"
6. Create `matches/<user>/from_<me>.yaml`:
   ```yaml
   from: "<me>"
   message: "<user's message or empty>"
   created_at: "<ISO 8601 UTC>"
   status: "pending"
   ```
7. Sync push.
8. Confirm: "Friend request sent to {user}!"

---

### /friends requests

**Purpose**: View and handle pending friend requests.

**Steps**:
1. Sync pull.
2. Read `~/.ocfr/config.yaml` to get `$USERNAME`.
3. List all files in `matches/$USERNAME/` directory.
4. Filter for `status: pending`.
5. Display:

```
Pending Friend Requests
──────────────────────────────
1. {display_name} (@{from}) - {time_ago}
   "{message}"
   -> accept {from} / decline {from}

2. ...
```

6. Wait for user input. Accept these formats:
   - `accept <user>`: Update `matches/$USERNAME/from_<user>.yaml` status to `accepted`, set `responded_at`. Also create/update `matches/<user>/from_$USERNAME.yaml` with `status: accepted`. Sync push.
   - `decline <user>`: Update status to `declined`, set `responded_at`. Sync push.

7. On accept, suggest: "You're now friends! Use `/friends msg {user}` to start chatting."

---

### /friends msg inbox

**Purpose**: View message inbox summary.

**Steps**:
1. Sync pull.
2. Read `$USERNAME` from config.
3. List all files in `messages/$USERNAME/` directory.
4. For each message file, decrypt using:
   ```bash
   bash {baseDir}/scripts/crypto.sh decrypt <message_file>
   ```
5. Group by sender, sort each group by timestamp descending.
6. Display:

```
Inbox
──────────────────────────────
{sender_display_name} (@{sender}) - {count} message(s)
  Latest: "{truncated_content}" - {time_ago}
  -> /friends msg {sender}

...
```

---

### /friends msg \<user\> [message]

**Purpose**: Send a message or view conversation history.

#### If message text is provided (SEND mode):

1. Sync pull.
2. **Check friendship**: Verify that a match file exists with `status: accepted` between you and the target user (check both `matches/<user>/from_<me>.yaml` and `matches/<me>/from_<user>.yaml`). If not friends, tell user to send a request first.
3. Read target user's profile to get their `public_key`. Write it to a secure temp file:
   ```bash
   TMPFILE=$(mktemp /tmp/ocfr_pub_XXXXXX.pem)
   # Write the public key PEM content to $TMPFILE
   ```
4. Encrypt the message (plaintext via stdin, NOT as a shell argument):
   ```bash
   echo -n "<message_text>" | bash {baseDir}/scripts/crypto.sh encrypt "$TMPFILE"
   ```
   This outputs YAML fields: `encrypted_key`, `iv`, `encrypted_content`.
5. Save plaintext to local sent cache (never pushed to git):
   ```bash
   mkdir -p ~/.ocfr/sent/<user>/
   echo -n "<message_text>" > ~/.ocfr/sent/<user>/<timestamp>.txt
   ```
6. Create the message file at `messages/<user>/from_<me>_<timestamp>.yaml`:
   ```yaml
   from: "<me>"
   timestamp: "<ISO 8601 UTC>"
   encrypted_key: "<from crypto.sh output>"
   iv: "<from crypto.sh output>"
   encrypted_content: "<from crypto.sh output>"
   ```
7. Clean up temp files: `rm -f "$TMPFILE"`
8. Sync push.
9. Confirm: "Message sent to {user} (encrypted)."

#### If no message text (VIEW mode):

1. Sync pull.
2. Collect messages in both directions:
   - `messages/<me>/from_<user>_*.yaml` (messages they sent to me)
   - `messages/<user>/from_<me>_*.yaml` (messages I sent to them)
3. Decrypt incoming messages:
   ```bash
   bash {baseDir}/scripts/crypto.sh decrypt <file>
   ```
4. For outgoing messages, since they're encrypted with the recipient's key and we can't decrypt them, read the plaintext from local cache if available, or show "[sent message]".
   **Important**: To solve the "can't read own sent messages" problem, when sending a message, also save a plaintext copy to `~/.ocfr/sent/<user>/<timestamp>.txt` (local only, never pushed to git).
5. Merge and sort all messages by timestamp ascending.
6. Render as a conversation:

```
Conversation with {display_name} (@{user})
──────────────────────────────
[You] {date time}
{message_text}

[{display_name}] {date time}
{message_text}

...
Type a message to reply, or /back to return.
```

---

### /friends sync

**Purpose**: Manually sync data with the remote repository.

**Steps**:
1. Run:
   ```bash
   bash {baseDir}/scripts/sync.sh pull
   bash {baseDir}/scripts/sync.sh push
   ```
2. Count changes: new profiles, new messages, new requests.
3. Report:
   ```
   Sync complete.
   - {n} new/updated profiles
   - {m} new messages
   - {k} new friend requests
   ```

---

## Error Handling

| Error | Response |
|-------|----------|
| Not initialized | "Please run `/friends init` first to set up your profile." |
| Network error on sync | "Sync failed. Check your network and try `/friends sync`." |
| User not found | "User '{name}' not found. Use `/friends explore` to browse members." |
| Not friends (msg) | "You need to be friends first. Send a request: `/friends request {user}`" |
| Decryption failure | "Could not decrypt message. Your key may have changed. Messages sent before a rekey cannot be read." |
| Push conflict | Auto-retry with pull-rebase up to 3 times. If still failing, ask user to run `/friends sync`. |
