# cwt

An `fzf`-powered switcher for git worktrees created by Claude Code
(`.claude/worktrees`), Sandcastle (`.sandcastle/worktrees` by default), and
native git (`.worktrees`). Pick a worktree to `cd` into it; preview shows
branch, last commit, uncommitted changes, and merge status against the default
branch (plus any extra bases you configure). `ctrl-x` deletes a worktree from
the picker. Branches, bases, and the sandcastle path are all
[configurable](#configuration).

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
| `CWT_SANDCASTLE_DIR` | Relative path of the "sandcastle" worktree dir; the list label derives from its leading segment | `.sandcastle/worktrees` |
| `CWT_CONFIG` | Path to the config file | `~/.config/cwt/config` |

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
