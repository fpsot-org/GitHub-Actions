#!/usr/bin/env bash
# Tests notify-site.sh: without the App credentials it fails and says what is
# missing; with them it sends one spec-released dispatch to the site repo.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
fail=0
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$GH_CALL"
GH
chmod +x "$work/bin/gh"
export PATH="$work/bin:$PATH" GH_CALL="$work/call"

if FPSOT_APP_CLIENT_ID="" GH_TOKEN=t REPO=fpsot-org/fpsot-spec-x TAG=v1.2.3 bash "$here/notify-site.sh" >"$work/out" 2>&1; then
  echo "FAIL: ran without FPSOT_APP_CLIENT_ID"; fail=1
fi
grep -q 'FPSOT_APP_CLIENT_ID is not set' "$work/out" || { echo "FAIL: message missing:"; cat "$work/out"; fail=1; }
[ ! -e "$work/call" ] || { echo "FAIL: gh was called without credentials"; fail=1; }

if ! FPSOT_APP_CLIENT_ID=Iv1.x GH_TOKEN=t REPO=fpsot-org/fpsot-spec-x TAG=v1.2.3 bash "$here/notify-site.sh" >"$work/out" 2>&1; then
  echo "FAIL: notify-site.sh failed:"; cat "$work/out"; fail=1
fi
for want in api repos/fpsot-org/fpsot-org.github.io/dispatches event_type=spec-released 'client_payload[repo]=fpsot-org/fpsot-spec-x' 'client_payload[tag]=v1.2.3'; do
  grep -qxF -- "$want" "$work/call" 2>/dev/null || { echo "FAIL: gh call lacks $want"; cat "$work/call" 2>/dev/null; fail=1; }
done
rm -f "$work/call"
FPSOT_APP_CLIENT_ID=Iv1.x bash "$here/notify-site.sh" --check >"$work/out" 2>&1 || { echo "FAIL: --check failed with credentials"; fail=1; }
[ ! -e "$work/call" ] || { echo "FAIL: --check called gh"; fail=1; }
FPSOT_APP_CLIENT_ID="" bash "$here/notify-site.sh" --check >"$work/out" 2>&1 && { echo "FAIL: --check passed without credentials"; fail=1; }
[ $fail -eq 0 ] && echo "PASS"
exit $fail
