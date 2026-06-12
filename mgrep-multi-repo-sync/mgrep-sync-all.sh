#!/bin/zsh
# mgrep-sync-all [dir] — sync every git repo under (or enclosing) dir to the mgrep index.
#
# Why: mgrep enumerates files via `git ls-files`, which never descends into
# nested git repositories. A parent directory holding multiple repos therefore
# indexes 0 files. This script finds each repo and syncs it individually.
# Search still works from the parent afterwards: mgrep filters its store with a
# `path starts_with` prefix, so results from all subrepos match.
set -u
root="${1:-$PWD}"
root="${root:A}"

# mgrep refuses to sync at or above $HOME; mirror that guard.
case "$HOME" in
  "$root"|"$root"/*) echo "mgrep-sync-all: refusing to sync at or above \$HOME" >&2; exit 1 ;;
esac

# Always sync root itself first: mgrep handles both the in-repo case (git
# ls-files scoped to this directory) and the no-git case (recursive walk).
repos=("$root")

# Nested repos under root. -name .git matches both dirs and worktree files.
while IFS= read -r g; do
  repos+=("${g:h}")
done < <(find "$root" -maxdepth 5 \( -name node_modules -prune \) -o -name .git -prune -print 2>/dev/null)

typeset -U repos  # dedup (covers root being a repo toplevel itself)

for r in "${repos[@]}"; do
  echo "mgrep-sync-all: syncing $r"
  (cd "$r" && mgrep search -s -m 1 "sync" . >/dev/null) \
    || echo "mgrep-sync-all: sync failed for $r" >&2
done
