#!/usr/bin/env bash
# Release in one go: check, commit, tag, push to GitHub, publish to pub.dev,
# then move the test app onto the new version, build its release APK and push it.
#
#   ./tool/release.sh 0.4.1                  # release 0.4.1
#   ./tool/release.sh 0.4.1 "Fix the header" # same, with your own commit message
#   ./tool/release.sh 0.4.1 --app-only       # only the test app part (the package is already out)
#
# Write the CHANGELOG entry (## 0.4.1) first; the version in pubspec.yaml is set for you.
# Test app location: BANIMARK_TEST_APP=/path/to/app ./tool/release.sh ...
set -euo pipefail
cd "$(dirname "$0")/.."

TEST_APP="${BANIMARK_TEST_APP:-/Users/agbenigabanji/Documents/android_flutter_app/banimark_test}"
RETRY_EVERY=120   # seconds between pub.dev checks
MAX_TRIES=30      # 30 x 2 min = give up after an hour

usage() {
  echo "Usage: ./tool/release.sh <version> [\"commit message\" | --app-only]" >&2
  exit 1
}

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.+-]+)?$ ]] || usage
app_only=false
message="banimark_flutter $version"
if [[ "${2:-}" == "--app-only" ]]; then
  app_only=true
elif [[ -n "${2:-}" ]]; then
  message="$2"
fi
tag="v$version"

release_package() {
  echo "==> Releasing banimark_flutter $version"

  # Refuse to re-release a version that is already tagged.
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    echo "Tag $tag already exists - pick a new version (or use --app-only)." >&2
    exit 1
  fi

  if ! grep -qE "^## $version\b" CHANGELOG.md; then
    echo "CHANGELOG.md has no '## $version' entry. Write it first." >&2
    exit 1
  fi

  sed -i '' -E "s/^version: .*/version: $version/" pubspec.yaml

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
}

update_test_app() {
  if [[ ! -f "$TEST_APP/pubspec.yaml" ]]; then
    echo "No test app at $TEST_APP - skipping it." >&2
    return
  fi
  cd "$TEST_APP"
  echo "==> Test app: banimark_flutter ^$version"

  # a local path override would build the local copy, not what customers get
  if grep -A5 '^dependency_overrides:' pubspec.yaml | grep -q 'banimark_flutter'; then
    echo "The test app overrides banimark_flutter (dependency_overrides) - remove that first." >&2
    exit 1
  fi
  sed -i '' -E "s/^  banimark_flutter: .*/  banimark_flutter: ^$version/" pubspec.yaml

  # pub.dev can take a few minutes to serve a new version
  local try=1
  until flutter pub get >/tmp/banimark_pub_get.log 2>&1 &&
        grep -A8 '^  banimark_flutter:' pubspec.lock | grep -q "version: \"$version\""; do
    if (( try >= MAX_TRIES )); then
      echo "pub.dev still does not serve $version after $MAX_TRIES tries. Last output:" >&2
      cat /tmp/banimark_pub_get.log >&2
      echo "Run again later: ./tool/release.sh $version --app-only" >&2
      exit 1
    fi
    echo "    $version is not on pub.dev yet (try $try/$MAX_TRIES) - checking again in $((RETRY_EVERY / 60)) min"
    sleep "$RETRY_EVERY"
    try=$((try + 1))
  done
  echo "    got banimark_flutter $version"

  echo "==> Building the release APK"
  flutter build apk --release
  mkdir -p apk
  rm -f apk/*.apk   # keep only the latest, so the repo does not fill up with old builds
  cp build/app/outputs/flutter-apk/app-release.apk "apk/banimark_test-$version.apk"
  echo "    apk/banimark_test-$version.apk"

  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "The test app is not a git repository yet - APK built, nothing pushed." >&2
    return
  fi
  echo "==> Pushing the test app"
  git add -A
  git diff --cached --quiet || git commit -m "banimark_flutter $version + sample APK"
  git push origin HEAD
}

$app_only || release_package
update_test_app

echo "==> Done: banimark_flutter $version is on GitHub and pub.dev, and the test app runs it"
