# cwt

An `fzf`-powered switcher for git worktrees. Out of the box it scans Claude
Code worktrees (`.claude/worktrees`) and native git worktrees (`.worktrees`).
Pick one to `cd` into it; the preview shows branch, last commit, uncommitted
changes, and merge status against the default branch. `ctrl-x` deletes a
worktree from the picker.

Everything Zendesk- or user-specific is opt-in via env vars: point
`CWT_EXTRA_DIRS` at extra worktree dirs (e.g. Sandcastle's
`.sandcastle/worktrees`), add `CWT_EXTRA_BASES` for extra merge targets, or
override the default branch. See [Configuration](#configuration).

## Requirements

- `fzf`
- `git`
- zsh or bash

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/oreid-zd/cwt/main/install.sh | sh
```

This drops `cwt.sh` into `~/.local/share/cwt/` and adds a `source` line to your
`~/.zshrc` (or `~/.bashrc`). Open a new shell, then run `cwt`.

Pin a version (any tag/branch/SHA):

```sh
CWT_REF=v1.2.0 curl -fsSL https://raw.githubusercontent.com/oreid-zd/cwt/v1.2.0/install.sh | sh
```

See the [releases](https://github.com/oreid-zd/cwt/releases) for available
versions and their changelogs.

## Configuration

Everything works with zero config — the default branch is auto-detected from
`origin/HEAD`. To customise, set env vars in your shell or drop them in a
config file at `~/.config/cwt/config` (or point `CWT_CONFIG` elsewhere). Env
vars take precedence over the file. See [`config.example`](config.example).

| Variable | Purpose | Default |
|---|---|---|
| `CWT_DEFAULT_BRANCH` | Override the default branch (e.g. `master`) | auto-detected |
| `CWT_EXTRA_BASES` | Extra base branches to fetch + check merge status against, space-separated (e.g. `"mvp develop"`) | none |
| `CWT_EXTRA_DIRS` | Extra worktree dirs to scan on top of the defaults, space-separated, repo-relative (e.g. `".sandcastle/worktrees"`); each label derives from its leading segment | none |
| `CWT_CONFIG` | Path to the config file | `~/.config/cwt/config` |

The default worktree dirs (`.claude/worktrees`, `.worktrees`) are always
scanned; `CWT_EXTRA_DIRS` only adds to them.

```sh
mkdir -p ~/.config/cwt
curl -fsSL https://raw.githubusercontent.com/oreid-zd/cwt/main/config.example -o ~/.config/cwt/config
# then edit ~/.config/cwt/config
```

## Update

```sh
cwt --update
```

## Uninstall

Remove the `# cwt` line from your rc and `rm -rf ~/.local/share/cwt`.

## Releasing (maintainer)

A published version is just a git tag:

```sh
git tag v1.2.0 && git push --tags
```

Pushing a `v*` tag triggers `.github/workflows/release.yml`, which cuts a
GitHub Release with auto-generated notes (changelog) from the commits/PRs since
the previous tag. Colleagues get a version with `CWT_REF=v1.2.0`, or the latest
`main` by default.
