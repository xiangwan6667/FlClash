#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
root="$(pwd)"

group() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::group::$1"; else echo "==> $1"; fi
}

endgroup() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then echo "::endgroup::"; fi
}

has_tests() {
  [[ -d "$1/test" && -n "$(find "$1/test" -name '*_test.dart' -print -quit)" ]]
}

test_prism_ui() (
  local host="$root/.dart_tool/prism_ui_test_host"
  mkdir -p "$host"
  cat >"$host/pubspec.yaml" <<'YAML'
name: prism_ui_test_host
publish_to: none
environment:
  sdk: '>=3.10.0 <4.0.0'
dependencies:
  flutter:
    sdk: flutter
  prism_ui:
    path: ../../plugins/prism_ui
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_localizations:
    sdk: flutter
YAML
  cd "$host"
  flutter pub get
  flutter test --reporter expanded "$root/plugins/prism_ui/test"
)

shopt -s nullglob
manifests=(plugins/*/pubspec.yaml)
shopt -u nullglob

if [[ ${#manifests[@]} -eq 0 ]]; then
  echo "no plugin packages found under plugins/" >&2
  exit 1
fi

analyzed=0
tested=0

for manifest in "${manifests[@]}"; do
  package="$(dirname "$manifest")"
  group "$package"
  (
    cd "$package"
    flutter pub get
    flutter analyze --no-fatal-infos
    if has_tests .; then
      if [[ "$package" == plugins/prism_ui ]]; then
        # Its shaders use package asset keys, which need a consuming app bundle.
        test_prism_ui
      else
        flutter test --reporter expanded
      fi
    else
      echo "no tests in $package"
    fi
  )
  analyzed=$((analyzed + 1))
  if has_tests "$package"; then
    tested=$((tested + 1))
  fi
  endgroup
done

echo "analyzed $analyzed plugin package(s), $tested with tests"
