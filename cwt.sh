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
    local _cwt_db="${CWT_DEFAULT_BRANCH:-}" _cwt_xb="${CWT_EXTRA_BASES:-}" _cwt_sc="${CWT_SANDCASTLE_DIR:-}"
    source "$config_file"
    [[ -n "$_cwt_db" ]] && CWT_DEFAULT_BRANCH="$_cwt_db"
    [[ -n "$_cwt_xb" ]] && CWT_EXTRA_BASES="$_cwt_xb"
    [[ -n "$_cwt_sc" ]] && CWT_SANDCASTLE_DIR="$_cwt_sc"
  fi

  # Relative path of the "sandcastle" worktree dir; the label shown in the list
  # is derived from its leading path segment (".sandcastle/worktrees" -> "sandcastle").
  local sandcastle_rel="${CWT_SANDCASTLE_DIR:-.sandcastle/worktrees}"
  local sandcastle_label="${sandcastle_rel%%/*}"
  sandcastle_label="${sandcastle_label#.}"

  local cwd=$(pwd)
  local repo_root

  if [[ "$cwd" == *"/.claude/worktrees/"* ]]; then
    repo_root="${cwd%%/.claude/worktrees/*}"
  elif [[ "$cwd" == *"/$sandcastle_rel/"* ]]; then
    repo_root="${cwd%%/$sandcastle_rel/*}"
  elif [[ "$cwd" == *"/.worktrees/"* ]]; then
    repo_root="${cwd%%/.worktrees/*}"
  else
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

  local claude_wt_dir="$repo_root/.claude/worktrees"
  local sandcastle_wt_dir="$repo_root/$sandcastle_rel"
  local root_wt_dir="$repo_root/.worktrees"

  if [[ ! -d "$claude_wt_dir" ]] && [[ ! -d "$sandcastle_wt_dir" ]] && [[ ! -d "$root_wt_dir" ]]; then
    echo "No worktrees found at $claude_wt_dir, $sandcastle_wt_dir, or $root_wt_dir"
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

  local preview_cmd='
    item={1}
    if [[ "$item" == "  '"$root_branch"'" ]]; then
      echo "📁 '"$root_branch"'"
      echo "───────────────────────────────"
      dir="'"$repo_root"'"
    elif [[ -d "'"$claude_wt_dir"'/$item" ]]; then
      dir="'"$claude_wt_dir"'/$item"
      echo "📁 $item"
      echo "───────────────────────────────"
    elif [[ -d "'"$sandcastle_wt_dir"'/$item" ]]; then
      dir="'"$sandcastle_wt_dir"'/$item"
      echo "📁 $item"
      echo "───────────────────────────────"
    else
      dir="'"$root_wt_dir"'/$item"
      echo "📁 $item"
      echo "───────────────────────────────"
    fi

    if git -C "$dir" rev-parse --git-dir &>/dev/null; then
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
    stat -f "  %Sm" -t "%Y-%m-%d %H:%M" "$dir" 2>/dev/null || stat --format="  %y" "$dir" 2>/dev/null | cut -d. -f1
  '

  local list_cmd='
    echo "  '"$root_branch"'"
    for wt in $(ls -1 "'"$claude_wt_dir"'" 2>/dev/null); do
      branch=$(git -C "'"$claude_wt_dir"'/$wt" branch --show-current 2>/dev/null)
      printf "%s \033[36m[claude]\033[0m \033[2m%s\033[0m\n" "$wt" "${branch:-detached}"
    done
    for wt in $(ls -1 "'"$sandcastle_wt_dir"'" 2>/dev/null); do
      [ -d "'"$claude_wt_dir"'/$wt" ] && continue
      branch=$(git -C "'"$sandcastle_wt_dir"'/$wt" branch --show-current 2>/dev/null)
      printf "%s \033[35m['"$sandcastle_label"']\033[0m \033[2m%s\033[0m\n" "$wt" "${branch:-detached}"
    done
    for wt in $(ls -1 "'"$root_wt_dir"'" 2>/dev/null); do
      { [ -d "'"$claude_wt_dir"'/$wt" ] || [ -d "'"$sandcastle_wt_dir"'/$wt" ]; } && continue
      branch=$(git -C "'"$root_wt_dir"'/$wt" branch --show-current 2>/dev/null)
      printf "%s \033[33m[native]\033[0m \033[2m%s\033[0m\n" "$wt" "${branch:-detached}"
    done
  '

  local delete_cmd='
    item={1}
    [ "$item" = "'"$root_branch"'" ] && exit 0
    if [ -d "'"$claude_wt_dir"'/$item" ]; then dir="'"$claude_wt_dir"'/$item"
    elif [ -d "'"$sandcastle_wt_dir"'/$item" ]; then dir="'"$sandcastle_wt_dir"'/$item"
    else dir="'"$root_wt_dir"'/$item"; fi
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

  if [[ "$selection" == "" || "$selection" == " " ]]; then
    cd "$repo_root"
  elif [[ -d "$claude_wt_dir/$selection" ]]; then
    cd "$claude_wt_dir/$selection"
  elif [[ -d "$sandcastle_wt_dir/$selection" ]]; then
    cd "$sandcastle_wt_dir/$selection"
  else
    cd "$root_wt_dir/$selection"
  fi
}
