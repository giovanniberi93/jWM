#!/usr/bin/env bash
set -euo pipefail

# Usage: release.sh <tag> [<notes>]
#   <tag>   e.g. v0.2 — must match vX.Y (the version script treats the
#           third dotted component as a commit count, not a patch number)
#   <notes> release notes body. If omitted, gh --generate-notes builds
#           them from commits/PRs since the previous tag.

TAG="${1:?usage: release.sh <tag> [<notes>], e.g. release.sh v0.2}"
NOTES="${2:-}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    echo "Tag must match vX.Y (got: $TAG)." >&2
    exit 1
fi

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO_ROOT"

TAP_ROOT="$REPO_ROOT/../homebrew-janzowm"
TAP_TEMPLATE="$TAP_ROOT/Casks/janzowm.rb.template"
TAP_CASK="$TAP_ROOT/Casks/janzowm.rb"
if [[ ! -d "$TAP_ROOT/.git" ]] || [[ ! -f "$TAP_TEMPLATE" ]]; then
    echo "Tap repo not found at $TAP_ROOT (need a clone of homebrew-janzowm with Casks/janzowm.rb.template)." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is not clean. Commit or stash before releasing." >&2
    exit 1
fi

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    if [[ "$(git rev-list -n1 "$TAG")" != "$(git rev-parse HEAD)" ]]; then
        echo "Tag $TAG already exists and does NOT point at HEAD." >&2
        exit 1
    fi
else
    git tag "$TAG"
fi

git push origin "$TAG"

./scripts/prepare_release_package.sh

VERSION="${TAG#v}"
ZIP="build/janzoWM-${VERSION}.zip"

if [[ -n "$NOTES" ]]; then
    gh release create "$TAG" "$ZIP" --title "$TAG" --notes "$NOTES"
else
    gh release create "$TAG" "$ZIP" --title "$TAG" --generate-notes
fi

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__SHA256__/$SHA256/g" "$TAP_TEMPLATE" > "$TAP_CASK"
(cd "$TAP_ROOT" && git add Casks/janzowm.rb && git commit -m "Update cask to $TAG")

echo
echo "Tap cask updated locally and committed in $TAP_ROOT."
echo "Push it from there: (cd $TAP_ROOT && git push)"
