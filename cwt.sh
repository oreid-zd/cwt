# Claude worktree command
cwt() {
  if [[ "$1" == "--update" ]]; then
    curl -fsSL "https://raw.githubusercontent.com/oreid-zd/cwt/${CWT_REF:-main}/install.sh" | sh
    return
  fi

  # Optional config file. Shell env vars take precedence, so only apply the
  # file's values for anything not already set in the environment.
  local config_file="${CWT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cwt/config}"
  if [[ -f "$config_file" ]]; then
    local _cwt_db="${CWT_DEFAULT_BRANCH:-}" _cwt_xb="${CWT_EXTRA_BASES:-}" _cwt_ed="${CWT_EXTRA_DIRS:-}"
    source "$config_file"
    [[ -n "$_cwt_db" ]] && CWT_DEFAULT_BRANCH="$_cwt_db"
    [[ -n "$_cwt_xb" ]] && CWT_EXTRA_BASES="$_cwt_xb"
    [[ -n "$_cwt_ed" ]] && CWT_EXTRA_DIRS="$_cwt_ed"
  fi

  # Worktree dirs to scan (relative to the repo root), in precedence order.
  # Defaults are .claude/worktrees and .worktrees; add more (space-separated)
  # via CWT_EXTRA_DIRS, e.g. ".sandcastle/worktrees .wt". Each list label is
  # derived from the dir's leading path segment (.worktrees stays "native").
  local wt_rels=".claude/worktrees .worktrees"
  local _ed
  for _ed in $(echo ${CWT_EXTRA_DIRS:-}); do
    wt_rels="$wt_rels $_ed"
  done

  local cwd=$(pwd)
  local repo_root="" _rel
  for _rel in $(echo $wt_rels); do
    if [[ "$cwd" == *"/$_rel/"* ]]; then
      repo_root="${cwd%%/$_rel/*}"
      break
    fi
  done
  if [[ -z "$repo_root" ]]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Not in a git repo"; return 1; }
  fi

  local default_branch="${CWT_DEFAULT_BRANCH:-}"
  if [[ -z "$default_branch" ]]; then
    default_branch=$(git -C "$repo_root" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    default_branch=${default_branch:-$(git -C "$repo_root" branch --show-current 2>/dev/null)}
    default_branch=${default_branch:-main}
  fi

  # Bases to compare worktrees against: the default branch plus any extras
  # (space-separated) from CWT_EXTRA_BASES, e.g. "mvp develop".
  local origin_bases="origin/$default_branch"
  local extra
  for extra in $(echo ${CWT_EXTRA_BASES:-}); do
    origin_bases="$origin_bases origin/$extra"
  done

  local root_branch
  root_branch=$(git -C "$repo_root" branch --show-current 2>/dev/null)
  root_branch=${root_branch:-$default_branch}

  local any_dir=0
  for _rel in $(echo $wt_rels); do
    [[ -d "$repo_root/$_rel" ]] && any_dir=1
  done
  if [[ $any_dir -eq 0 ]]; then
    echo "No worktrees found under: ${wt_rels// /, } (in $repo_root)"
    return 1
  fi

  # Kick off a background fetch (throttled to once every 5 min via a stamp file)
  # so the merged/ahead status in the preview reflects the latest origin state.
  local git_dir=$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null)
  [[ "$git_dir" != /* ]] && git_dir="$repo_root/$git_dir"
  local fetch_stamp="$git_dir/.cwt-fetch-stamp"
  local fetch_lock="$git_dir/.cwt-fetch-lock"
  if [[ -z "$(find "$fetch_stamp" -mmin -5 2>/dev/null)" ]] && [[ ! -f "$fetch_lock" ]]; then
    touch "$fetch_lock"
    (
      git -C "$repo_root" fetch -q --prune origin "$default_branch" $(echo ${CWT_EXTRA_BASES:-}) 2>/dev/null
      touch "$fetch_stamp"
      rm -f "$fetch_lock"
    ) &
    disown 2>/dev/null
  fi

  # Build the per-dir fzf snippets (list rows, preview + delete dir-resolution)
  # from the dir list. These run inside fzf's shell, so absolute paths are
  # spliced in now while $item/$wt/$branch stay literal for runtime expansion.
  local list_body="" preview_chain="" del_chain="" guard="" this_term
  local absdir lbl color
  for _rel in $(echo $wt_rels); do
    absdir="$repo_root/$_rel"
    lbl="${_rel%%/*}"; lbl="${lbl#.}"
    [[ "$_rel" == ".worktrees" ]] && lbl="native"
    case "$lbl" in
      claude) color=36 ;;   # cyan
      native) color=33 ;;   # yellow
      *)      color=35 ;;   # magenta (all extra dirs)
    esac

    local block='
    for wt in $(ls -1 "'"$absdir"'" 2>/dev/null); do'
    if [[ -n "$guard" ]]; then
      block="$block"'
      { '"$guard"'; } && continue'
    fi
    block="$block"'
      branch=$(git -C "'"$absdir"'/$wt" branch --show-current 2>/dev/null)
      printf "%s \033['"$color"'m['"$lbl"']\033[0m \033[2m%s\033[0m\n" "$wt" "${branch:-detached}"
    done'
    list_body="$list_body$block"

    this_term='[ -d "'"$absdir"'/$wt" ]'
    if [[ -n "$guard" ]]; then guard="$guard || $this_term"; else guard="$this_term"; fi

    preview_chain="$preview_chain"'
    elif [[ -d "'"$absdir"'/$item" ]]; then
      dir="'"$absdir"'/$item"
      echo "📁 $item"
      echo "───────────────────────────────"'

    del_chain="$del_chain"'
    elif [ -d "'"$absdir"'/$item" ]; then dir="'"$absdir"'/$item"'
  done

  local preview_cmd='
    item={1}
    if [[ "$item" == "  '"$root_branch"'" ]]; then
      echo "📁 '"$root_branch"'"
      echo "───────────────────────────────"
      dir="'"$repo_root"'"'"$preview_chain"'
    else
      dir=""
    fi

    if [[ -n "$dir" ]] && git -C "$dir" rev-parse --git-dir &>/dev/null; then
      branch=$(git -C "$dir" branch --show-current 2>/dev/null)
      echo "🌿 branch: ${branch:-detached}"
      echo ""

      echo "📝 last commit:"
      git -C "$dir" log -1 --format="  %C(yellow)%h%Creset  %s  %C(dim)(%ar)%Creset" --color=always 2>/dev/null
      echo ""

      wt_status=$(git -C "$dir" status --short 2>/dev/null)
      if [[ -n "$wt_status" ]]; then
        echo "⚡ uncommitted changes:"
        echo "$wt_status" | head -20 | sed "s/^/  /"
      else
        echo "✅ clean"
      fi
      echo ""

      [[ -f "'"$fetch_lock"'" ]] && echo "⏳ fetching latest from origin…"
      for base in '"$origin_bases"'; do
        git -C "$dir" rev-parse --verify -q "$base" >/dev/null || continue
        if [[ -z "$branch" ]]; then
          :
        elif git -C "$dir" merge-base --is-ancestor HEAD "$base" 2>/dev/null; then
          echo "🔀 merged into $base"
        elif [[ -z "$(git -C "$dir" diff "$base" HEAD 2>/dev/null)" ]]; then
          echo "🔀 merged into $base (squash)"
        else
          ahead=$(git -C "$dir" rev-list --count "$base"..HEAD 2>/dev/null)
          echo "⚠️  NOT merged into $base (${ahead:-?} commits ahead)"
        fi
      done
    else
      echo "  (no git repo)"
    fi

    echo ""
    echo "🕐 last modified:"
    [[ -n "$dir" ]] && { stat -f "  %Sm" -t "%Y-%m-%d %H:%M" "$dir" 2>/dev/null || stat --format="  %y" "$dir" 2>/dev/null | cut -d. -f1; }
  '

  local list_cmd='
    echo "  '"$root_branch"'"'"$list_body"'
  '

  local delete_cmd='
    item={1}
    dir=""
    if [ "$item" = "'"$root_branch"'" ]; then exit 0'"$del_chain"'
    fi
    [ -d "$dir" ] || exit 0
    branch=$(git -C "$dir" branch --show-current 2>/dev/null)
    merged=""
    for base in '"$origin_bases"'; do
      git -C "$dir" rev-parse --verify -q "$base" >/dev/null || continue
      [ -z "$branch" ] && continue
      if git -C "$dir" merge-base --is-ancestor HEAD "$base" 2>/dev/null; then
        merged="$merged✅ merged into $base
"
      elif [ -z "$(git -C "$dir" diff "$base" HEAD 2>/dev/null)" ]; then
        merged="$merged✅ merged into $base (squash)
"
      else
        ahead=$(git -C "$dir" rev-list --count "$base"..HEAD 2>/dev/null)
        merged="$merged⚠️  NOT merged into $base (${ahead:-?} commits ahead)
"
      fi
    done
    printf "%sDelete worktree %s? [y/N] " "$merged" "$item"
    read ans
    [ "$ans" = y ] || [ "$ans" = Y ] || exit 0
    git -C "'"$repo_root"'" worktree remove --force "$dir" 2>/dev/null || rm -rf "$dir"
    git -C "'"$repo_root"'" worktree prune 2>/dev/null
  '

  local selection
  selection=$(eval "$list_cmd" | fzf \
    --ansi \
    --prompt="worktree> " \
    --height=80% \
    --reverse \
    --preview="$preview_cmd" \
    --preview-window="right:55%:wrap" \
    --border=rounded \
    --color="header:italic,label:blue" \
    --bind="ctrl-x:execute($delete_cmd)+reload($list_cmd)" \
    --header="  ctrl+c to cancel · ctrl+x to delete") || return 0

  selection="${selection%% *}"

  if [[ -z "$selection" || "$selection" == " " ]]; then
    cd "$repo_root"
  else
    local target="$repo_root"
    for _rel in $(echo $wt_rels); do
      if [[ -d "$repo_root/$_rel/$selection" ]]; then
        target="$repo_root/$_rel/$selection"
        break
      fi
    done
    cd "$target"
  fi
}
