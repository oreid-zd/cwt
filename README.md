# cwt

An `fzf`-powered switcher for git worktrees created by Claude Code
(`.claude/worktrees`), Sandcastle (`.sandcastle/worktrees`), and native git
(`.worktrees`). Pick a worktree to `cd` into it; preview shows branch, last
commit, uncommitted changes, and merge status against `origin/<default>` and
`origin/mvp`. `ctrl-x` deletes a worktree from the picker.

## Requirements

- `fzf`
- `git`
- zsh or bash

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/main/install.sh | sh
```

This drops `cwt.sh` into `~/.local/share/cwt/` and adds a `source` line to your
`~/.zshrc` (or `~/.bashrc`). Open a new shell, then run `cwt`.

Pin a version (any tag/branch/SHA):

```sh
CWT_REF=v1.0.0 curl -fsSL https://raw.githubusercontent.com/OWNER/REPO/v1.0.0/install.sh | sh
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
git tag v1.1.0 && git push --tags
```

Colleagues get it with `CWT_REF=v1.1.0`, or the latest `main` by default.
