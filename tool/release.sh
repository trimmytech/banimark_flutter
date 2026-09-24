#!/usr/bin/env bash
# Release in one go: check, commit, tag, push to GitHub, publish to pub.dev.
#
#   ./tool/release.sh            # releases the version in pubspec.yaml
#   ./tool/release.sh "message"  # same, with your own commit message
#
# Bump `version:` in pubspec.yaml and add a CHANGELOG entry first.
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
tag="v$version"
message="${1:-banimark_flutter $version}"

echo "==> Releasing $version"

# Refuse to re-release a version that is already tagged.
if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "Tag $tag already exists. Bump version in pubspec.yaml first." >&2
  exit 1
fi

if ! grep -qE "^## $version\b" CHANGELOG.md; then
  echo "CHANGELOG.md has no '## $version' entry." >&2
  exit 1
fi

echo "==> Checking"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test

echo "==> Committing"
git add -A
git diff --cached --quiet || git commit -m "$message"

# Needs a clean tree (pub warns otherwise), so it runs after the commit.
# Catches pub.dev problems before anything is pushed.
flutter pub publish --dry-run

echo "==> Pushing to GitHub"
git tag -a "$tag" -m "$message"
git push origin HEAD
git push origin "$tag"

echo "==> Publishing to pub.dev"
flutter pub publish --force

echo "==> Done: $tag is on GitHub and pub.dev"
