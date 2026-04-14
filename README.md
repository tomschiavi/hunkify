# hunkify

Split your staged changes into atomic, well-scoped commits — powered by Claude.

Instead of cramming everything into a single `git commit -m "wip"`, `hunkify` parses your staged diff hunk by hunk, asks Claude to group them by intent, and produces conventional commits (with gitmojis) ready to apply.

## Features

- **Hunk-level analysis** — each change block is treated independently, so one file can span multiple commits if needed.
- **AI-powered grouping** via Claude Haiku 4.5 — fast, cheap, accurate.
- **Gitmoji + conventional commits** — `:sparkles: feat(scope): …`, `:bug: fix(scope): …`, etc.
- **Interactive review** — confirm, edit, or skip each proposed commit before it's created.
- **Free-form context argument** — pass a ticket ID, feature name, or any directive to steer the output.
- **Safe rollback** — if anything fails mid-run, your original staged state is restored.

## Requirements

- Ruby ≥ 2.7
- An [Anthropic API key](https://console.anthropic.com/)

## Installation

```bash
gem install hunkify
```

Or add to your `Gemfile`:

```ruby
gem "hunkify"
```

## Setup

Export your Anthropic API key (add to your `~/.zshrc` or `~/.bashrc`):

```bash
export ANTHROPIC_API_KEY=sk-ant-...
```

## Usage

```bash
git add .
hunkify
```

With a context hint (ticket ID, feature name, or any free-form directive):

```bash
hunkify my_ticket_id
hunkify "user onboarding"
hunkify "focus on refactoring"
```

### Workflow

1. `hunkify` parses your staged diff into hunks.
2. Claude proposes a grouping into logical commits.
3. For each proposed commit, you can **confirm**, **edit the message**, **skip**, or **quit**.
4. After a final confirmation, the plan is applied — each commit is created via `git apply --cached`.

If anything goes wrong during apply, the original staged state is restored.

## Debug

Set `HUNKIFY_DEBUG=1` to print the raw AI response and the patches being applied:

```bash
HUNKIFY_DEBUG=1 hunkify
```

## License

MIT
