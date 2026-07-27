# Rysh

An agentic terminal multiplexer, written in Go. One binary, no daemon zoo.

Rysh looks like a terminal multiplexer — tabs, panes, splits, `vim` and `htop` work
exactly as you expect. The difference is that **every pane is also an agent**. The
same pane where you run `git status` can answer a prompt, call tools, and keep
working while you move on to the next pane.

```
┌─ tab: api ──────────────────────┬──────────────────────────────┐
│ $ go test ./...                 │ > why is the auth test flaky?│
│ ok  api/handlers    0.42s       │                              │
│ FAIL api/auth       1.10s       │ It shares a fixture with ... │
│ _                               │ _                            │
└─ shell mode ────────────────────┴─ prompt mode ────────────────┘
```

This repository is the **build workspace**. The code lives in two submodules:

| Module | What it is |
| --- | --- |
| [`rysh-cli-code`](https://github.com/rysh-ai/rysh-cli-code) | the CLI, the TUI, the actors, the terminal emulator |
| [`rysh-cli-shared`](https://github.com/rysh-ai/rysh-cli-shared) | agentic orchestration, provider adapters, message types, secret redaction |
| [`rysh-cli-app-code`](https://github.com/rysh-ai/rysh-cli-app-code) | Rysh Desktop (Electron) and the web renderer the CLI serves |

## Install

### From source (recommended)

```sh
git clone --recursive https://github.com/rysh-ai/rysh-cli-parent
cd rysh-cli-parent
make install          # builds, then installs to ~/.local/bin/rysh
```

If you cloned without `--recursive`, run `make bootstrap` first. Installing
somewhere else: `make install PREFIX=/usr/local`. Make sure the target `bin`
directory is on your `PATH`:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

### With `go install`

```sh
go install github.com/rysh-ai/rysh-cli-code/cmd/rysh@latest
```

This drops a binary named `rysh` in `$(go env GOPATH)/bin`.

**Requirements:** Go 1.25.3 or newer, and a POSIX terminal. Linux and macOS are
what we build and test on.

## First run

Rysh talks to an LLM provider. `rysh onboard` sets that up and drops you into a
session:

```sh
export ANTHROPIC_API_KEY=sk-ant-...
rysh onboard --provider anthropic --key-env ANTHROPIC_API_KEY
```

It validates the key, writes `rysh.config.yaml` **in the current directory**, and
opens your session. Config is project-local by design — a different repo gets a
different setup, and there is no global state root. Rysh looks for
`./rysh.config.yaml`, then `./.rysh/rysh.config.yaml`, and stops there;
`--config <path>` overrides both.

No key? Rysh falls back to the `claude` CLI if it is installed. Set
`provider.api_key` in the config to use the API directly instead.

Check everything is wired up:

```sh
rysh doctor          # provider, channels, daemon/NATS, config — each PASS/WARN/FAIL
```

## The one thing to learn

Each pane has an **input mode**. `Esc Esc` cycles it:

```
shell  ->  prompt  ->  rysh  ->  chat  ->  shell
```

- **shell** — a real PTY. Your `$SHELL`, your `~/.bashrc`, your prompt, your
  aliases, tab-completion, `Ctrl+R` history search.
- **prompt** — what you type goes to the LLM, with the pane's output as context.
- **rysh** — multiplexer commands (the `##` commands, without the `##`).
- **chat** — conversation with the pane's agent, no tool execution.

That is the whole model. Everything else is a keybinding.

## Getting around

| Key | Action |
| --- | --- |
| `Enter` | Submit input |
| `Esc Esc` | Cycle input mode |
| `Ctrl+N` | New pane in the active tab |
| `Tab` | Next pane |
| `[` / `]` | Previous / next tab |
| `Alt+←` / `Alt+→` | Switch tabs |
| `Alt+↑` / `Alt+↓` | Switch panes |
| `Ctrl+T` | Tab mode (`n` new, `1`–`9` jump) |
| `Ctrl+P` | Pane mode (`r` rename) |
| `Ctrl+L` | Layout mode |
| `Ctrl+Space` | Navigate mode — arrow keys traverse panes |
| `PageUp` / `PageDown` | Scroll the active pane |
| `Alt+P f` | Fullscreen the active pane |
| `Ctrl+P d` | Detach |

When you launch an interactive program — `vim`, `htop`, `less` — the pane switches
to **raw mode** automatically and every keystroke goes straight to the PTY.
`Ctrl+O` is the escape hatch back out.

## Sessions

A session is a daemon. Detach from it, close your laptop, come back later.

```sh
rysh create work            # create and attach
rysh create work -d         # create detached, stay in your shell
rysh attach work
rysh detach work
rysh list-sessions
rysh stop work
```

After rebuilding the binary, `rysh attach work --upgrade` restarts the session's
daemon on the new build. Live PTY processes are lost; session state is restored.

## Agents

A pane is an agent. You can also spawn headless ones — no PTY, no terminal —
and address them from any pane, in any mode:

```
##agent spawn reviewer          # create a headless agent
@reviewer check internal/auth for races
@@reviewer stop                 # control command
```

`@name` prompts an agent, `@@name` controls it (`stop`, `activate`,
`deactivate`). **Humanoids** are agents with an external channel attached —
Slack, Telegram, Discord, WhatsApp, Signal, iMessage — so you can drive a
session from your phone:

```sh
rysh assistant --channel telegram
```

Fail-closed by default: an assistant will not act on messages from someone who
is not paired with you.

## Beyond the terminal

Rysh Desktop is a native window around the same session, with the `rysh` binary
bundled inside it — see
[`rysh-cli-app-code`](https://github.com/rysh-ai/rysh-cli-app-code) to build it.
The same renderer, minus Electron, is what `rysh web start` serves to a browser
or a phone.

```sh
rysh web start work              # browser viewer, prints a tokenised URL
rysh run "fix the failing test"  # headless CI mode; exit 0/1/2/3, --json for a result line
rysh search <query>              # find packages in the registry
rysh install @ns/name            # install one
```

`rysh --help` lists the full surface — entity management (tabs, lanes, panes,
pane groups, stacks, pipelines), upstream collaboration, governance and cost
controls, session recording.

## Development

```sh
make bootstrap    # fetch submodules
make build        # -> bin/rysh
make test         # both modules
make vet
make ci           # vet + test + build
make help         # list targets
```

`go.work` points `rysh-cli-code` at the sibling `rysh-cli-shared` checkout, so a
change in the shared module is picked up immediately — no release round-trip.
Build through this repo, not from inside a submodule, or you will silently
compile against the published shared module instead of your local edits.

Submodules track `main`. To pull both forward:

```sh
git submodule update --remote --merge
```

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
