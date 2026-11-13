# AI Limits

A macOS menu bar app that shows your Claude and Codex usage limits.

- **Menu bar**: two small bars, Claude on top (orange), Codex below (teal). Each bar fills with the weekly limit used;
  the color gets deeper as usage grows and turns grey when the numbers are stale. Hover shows the exact numbers.
- **Panel**: rest the pointer on the item to open it; click to keep it open; click outside to close it. It scrolls when
  it is taller than the screen. Tabs (one click switches):
  - **Overview**: plan, monthly price and renewal date, weekly % left for both providers, and the weekly % left for the
    last 7 days (100% at each reset, down to 0%). Dashed lines mark stretches with no data.
  - **Claude** / **Codex**: every limit with a pace marker (even use until reset), this week's line against even use
    and earlier weeks, tokens and estimated API cost per day for 30 days by model, and (Claude) top projects.
- **Settings** (gear in the panel): refresh every 5 / 15 / 30 / 60 min, which bars to show, monthly prices, start at
  login, quit.

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
| Claude limits | `https://api.anthropic.com/api/oauth/usage` with the Claude Code login token from Keychain item `Claude Code-credentials` (read with `/usr/bin/security`) |
| Claude plan, renewal | `https://api.anthropic.com/api/oauth/profile`. It has no renewal date: the app guesses the next one from the subscription start day (shown with `~`) |
| Codex limits, plan | `https://chatgpt.com/backend-api/wham/usage` with the token from `~/.codex/auth.json`; the newest `rate_limits` in `~/.codex/sessions` when that fails |
| Codex renewal | `https://chatgpt.com/backend-api/subscriptions` |
| Prices | Settings. Neither server reports the price |
| Weekly % history | Saved on each refresh in `~/Library/Application Support/AILimits/history.json`; Codex history is also read from its session logs |
| Tokens and estimated cost | `npx ccusage@20.0.50` (`claude daily --instances --breakdown`, `codex daily`) run through a login shell |

- Both usage endpoints are internal, not public APIs. When one fails, the app keeps the last numbers, greys the ring
  and says why in the panel.
- The app never refreshes login tokens. A refresh would replace Claude Code's or Codex's own token. When a token
  expires, open Claude Code or Codex once.
- Token charts only cover usage logged on this Mac.

## Troubleshooting

- **No bar for a provider**: you are not logged in to it on this Mac (`claude` or `codex` login).
- **Grey bar**: the last fetch failed. Open the panel to see the reason.
- **Item not visible**: on a MacBook, menu bar items behind the camera notch are hidden. Quit some other menu bar apps.
- **"Token history not available"**: `npx` was not found or ccusage failed. Check `zsh -lc 'npx -y ccusage@20.0.50 --help'`.
- **Logs**: `log stream --predicate 'subsystem == "local.ailimits"'` shows only failures.
