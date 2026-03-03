---
name: bitwarden
description: >
  Manage secrets via Bitwarden CLI (bw). Use when pulling secrets into a shell session,
  creating/updating Secure Notes from .env files, listing vault items, or setting up
  Bitwarden on a new machine. Secrets live in Bitwarden, get loaded into memory on demand,
  and die with the shell session — no files on disk.
homepage: https://bitwarden.com/help/cli/
metadata:
  {
    "openclaw":
      {
        "emoji": "🔐",
        "requires": { "bins": ["bw", "jq"] },
        "install":
          [
            {
              "id": "brew",
              "kind": "brew",
              "formula": "bitwarden-cli",
              "bins": ["bw"],
              "label": "Install Bitwarden CLI (brew)",
            },
            {
              "id": "snap",
              "kind": "shell",
              "command": "sudo snap install bw",
              "bins": ["bw"],
              "label": "Install Bitwarden CLI (snap)",
            },
            {
              "id": "npm",
              "kind": "shell",
              "command": "npm install -g @bitwarden/cli",
              "bins": ["bw"],
              "label": "Install Bitwarden CLI (npm)",
            },
          ],
      },
  }
---

# Bitwarden CLI — Secrets Management

## Core Concept

Secrets are stored as Bitwarden **Secure Notes** with `export KEY=value` lines in the notes field.
One `eval` call loads them into the current shell. No files on disk. Secrets die with the session.

## Shell Functions

These functions are the primary interface. Source them in your shell profile (`.zshrc` / `.bashrc`).

### `bwss` — Unlock vault (session set)

```bash
bwss(){
    eval $(bw unlock | grep export | awk -F"\$" {'print $2'})
}
```

Unlocks the vault and exports `BW_SESSION` into the current shell. Prompts for master password interactively. Must run before any other `bw` command.

### `bwe <item-name>` — Load secrets into env

```bash
bwe(){
    eval $(bw get item $1 | jq -r '.notes')
}
```

Fetches a Secure Note by name and `eval`s its contents. Each line should be `export KEY=value`.

**Example:** `bwe agent-fleet` loads all agent secrets into the current shell.

### `bwe_safe <item-name>` — Load secrets with input validation

```bash
bwe_safe(){
    bw get item $1 | jq -r '.notes' | grep -E '^export [A-Za-z_][A-Za-z0-9_]*=.*$' | while IFS= read -r line; do eval "$line"; done
}
```

Same as `bwe` but only evaluates lines matching `export VAR=value`. Anything else is silently dropped. Use on shared org accounts or untrusted environments.

### `bwc <name> [file]` — Create Secure Note from .env file

```bash
bwc(){
    DEFAULT_FF=".env"
    FF=${2:-$DEFAULT_FF}
    cat ${FF} | awk '{print "export " $0}' >/tmp/.xenv
    bw get template item | jq --arg a "$(cat /tmp/.xenv)" --arg b "$1" \
      '.type = 2 | .secureNote.type = 0 | .notes = $a | .name = $b' \
      | bw encode | bw create item
    rm /tmp/.xenv
}
```

Takes a `.env` file (KEY=value lines), prepends `export` to each line, and creates a Bitwarden Secure Note. The note name is the first argument.

**Example:** `bwc my-project .env.production`

### `bwce <name>` — Create Secure Note from current shell exports

```bash
bwce(){
    export | awk '{print "export " $0}' >/tmp/.env
    bw get template item | jq --arg a "$(cat /tmp/.env)" --arg b "$1" \
      '.type = 2 | .secureNote.type = 0 | .notes = $a | .name = $b' \
      | bw encode | bw create item
    rm /tmp/.env
}
```

Captures all current shell exports and saves them as a Secure Note. Useful for snapshotting a working environment.

### `bwdd <name>` — Delete item by name

```bash
bwdd(){
    bw delete item $(bw get item $1 | jq .id | tr -d '"')
}
```

### Aliases

```bash
alias bwl="bw list items | jq '.[] | .name'"        # List all item names
alias bwll="bw list items | jq '.[] | .name' | grep" # Search item names
alias bwg="bw get item"                               # Get full item JSON
```

## Workflow

### First time on a new machine

1. Install CLI: `brew install bitwarden-cli` (macOS) / `sudo snap install bw` (Ubuntu) / `npm i -g @bitwarden/cli`
2. Verify: `bw --version`
3. Login with API key:
   ```bash
   export BW_CLIENTID="user.xxxxx"
   export BW_CLIENTSECRET="xxxxxx"
   bw login --apikey
   ```
   Or interactively: `bw login <email>`
4. Add shell functions to profile (copy `bwss`, `bwe`, `bwe_safe`, `bwc`, `bwce`, `bwdd` and aliases into `.zshrc` or `.bashrc`)
5. Unlock: `bwss` (enter master password)
6. Verify: `bwl` (should list your vault items)

### Daily use

```bash
bwss                  # Unlock vault (once per terminal session)
bwe agent-fleet       # Load all agent secrets
echo $ANTHROPIC_API_KEY  # Verify — should be set
```

### Creating / updating secrets

```bash
# From a .env file
bwc my-new-project .env

# From current shell
bwce snapshot-2026-03-03

# Update an existing note (delete + recreate)
bwdd old-note
bwc old-note .env.updated

# Or edit in web vault — notes field, one `export KEY=value` per line
```

### Org + Collection pattern (team/fleet use)

For sharing secrets with a machine account (e.g., GCP VM):

1. **Create a Bitwarden Organization** (free tier = 2 users)
2. **Create a Collection** in the org (e.g., `popa-secrets`)
3. **Create a machine account** — separate Bitwarden account, invited to org, assigned to the collection
4. **Add Secure Notes** to the collection with `export KEY=value` format
5. **On the target machine:** login with machine account API key, `bwss`, `bwe <note>`

The machine account sees ONLY items in its assigned collection. Revoke access = remove from org. One click.

### Creating items in a collection (programmatic)

```bash
COLLECTION_ID="<collection-uuid>"
ORG_ID="<org-uuid>"
NOTES=$(cat .env | awk '{print "export " $0}')

bw get template item | jq \
  --arg notes "$NOTES" \
  --arg name "my-item" \
  --arg orgId "$ORG_ID" \
  --argjson colIds "[\"$COLLECTION_ID\"]" \
  '.type = 2 | .secureNote.type = 0 | .notes = $notes | .name = $name | .organizationId = $orgId | .collectionIds = $colIds' \
  | bw encode | bw create item
```

### Listing collections and orgs

```bash
bw list organizations | jq '.[] | {id, name}'
bw list collections | jq '.[] | {id, name}'
bw list items --collectionid <id> | jq '.[] | .name'
```

## Secure Note Format

Each Secure Note's `notes` field contains one secret per line:

```
export ANTHROPIC_API_KEY=sk-ant-...
export OPENAI_API_KEY=sk-proj-...
export DISCORD_TOKEN=MTQ3...
```

**Rules:**

- One `export KEY=value` per line
- No comments, no blank lines (they get eval'd)
- Keys should be `UPPER_SNAKE_CASE`
- Values with special characters don't need quoting (they're on their own line)
- Never put shell commands in values — use `bwe_safe` if you're paranoid

## Guardrails

- **Never paste secrets into chat, logs, or code.** Use `bwe` to load into memory only.
- **Never write secrets to disk** unless absolutely necessary (and chmod 600 if you must).
- **Prefer `bwe` over `~/.secrets/` files.** Secrets in memory > secrets on disk.
- **Use `bwe_safe` on shared/org accounts.** Defence in depth against note tampering.
- **`bwss` once per terminal session.** The session token persists until the shell exits.
- **Sync before pulling:** `bw sync` if you've recently updated secrets in the web vault.
- **Lock when done:** `bw lock` to clear the session token.

## Tmux Considerations

If using `bw` inside tmux (common for agents), the `BW_SESSION` env var must be available in the tmux pane. Either:

- Run `bwss` inside the tmux pane, or
- Export `BW_SESSION` before creating the tmux session

```bash
# Option 1: unlock inside tmux
tmux new-session -d -s work
tmux send-keys -t work 'bwss' Enter
# ... wait for unlock ...
tmux send-keys -t work 'bwe agent-fleet' Enter

# Option 2: pass session token
export BW_SESSION=$(bw unlock "password" --raw)
tmux new-session -d -s work -e "BW_SESSION=$BW_SESSION"
tmux send-keys -t work 'bwe agent-fleet' Enter
```

## Quick Reference

| Command             | What it does                     |
| ------------------- | -------------------------------- |
| `bwss`              | Unlock vault, set BW_SESSION     |
| `bwe <name>`        | Load secrets from note into env  |
| `bwe_safe <name>`   | Same, with input validation      |
| `bwc <name> [file]` | Create note from .env file       |
| `bwce <name>`       | Create note from current exports |
| `bwdd <name>`       | Delete item by name              |
| `bwl`               | List all item names              |
| `bwll <grep>`       | Search item names                |
| `bwg <name>`        | Get full item JSON               |
| `bw sync`           | Pull latest from server          |
| `bw lock`           | Clear session token              |
