# AI Limits

A macOS menu bar app that shows your Claude and Codex usage limits.

- **Menu bar**: one ring per provider (Claude orange, Codex teal). The ring fills with the weekly limit used; the text
  next to it is the time until that limit resets (`2d`, `15h`, `40m`). The ring color gets deeper as usage grows and
  turns grey when the numbers are stale.
- **Panel**: rest the pointer on the item to open it; click to keep it open. Tabs:
  - **Overview**: weekly % left for both providers, and both weekly lines for the last 7 days.
  - **Claude** / **Codex**: every limit with a pace marker (even use until reset), this week's line against even use
    and earlier weeks, tokens and estimated API cost per day for 30 days by model, and (Claude) top projects.
- **Settings** (gear in the panel): refresh every 5 / 15 / 30 / 60 min, which rings to show, start at login, quit.

## Install

Needs macOS 15+, the Xcode Command Line Tools (`xcode-select --install`), [Task](https://taskfile.dev) and Node
(for `npx ccusage`).

```sh
task install
```

This builds `AI Limits.app`, copies it to `~/Applications` and starts it.

## Develop

```sh
task run        # build and start from build/
task snapshot   # render every panel tab with real data to build/snapshots/*.png
task test       # unit tests
```

`task snapshot` is the way to check the UI without clicking: it fetches real data, renders each tab in dark and light
mode, and exits. Native controls (tab switch, buttons, checkboxes) show as yellow placeholders there.

## Where the numbers come from

| Data | Source |
| --- | --- |
| Claude limits, plan | `https://api.anthropic.com/api/oauth/usage` with the Claude Code login token from Keychain item `Claude Code-credentials` (read with `/usr/bin/security`) |
| Codex limits, plan | `https://chatgpt.com/backend-api/wham/usage` with the token from `~/.codex/auth.json`; the newest `rate_limits` in `~/.codex/sessions` when that fails |
| Weekly % history | Saved on each refresh in `~/Library/Application Support/AILimits/history.json`; Codex history is also read from its session logs |
| Tokens and estimated cost | `npx ccusage@20.0.50` (`claude daily --instances --breakdown`, `codex daily`) run through a login shell |

- Both usage endpoints are internal, not public APIs. When one fails, the app keeps the last numbers, greys the ring
  and says why in the panel.
- The app never refreshes login tokens. A refresh would replace Claude Code's or Codex's own token. When a token
  expires, open Claude Code or Codex once.
- Token charts only cover usage logged on this Mac.

## Troubleshooting

- **No ring for a provider**: you are not logged in to it on this Mac (`claude` or `codex` login).
- **Grey ring**: the last fetch failed. Open the panel to see the reason.
- **"Token history not available"**: `npx` was not found or ccusage failed. Check `zsh -lc 'npx -y ccusage@20.0.50 --help'`.
- **Logs**: `log stream --predicate 'subsystem == "local.ailimits"'` shows only failures.
