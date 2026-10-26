#!/bin/sh
# Test for .githooks/pre-commit: each case stages a crafted file and asserts
# whether the hook refuses it. Run after any change to the hook:
#
#     sh .githooks/test-pre-commit.sh
#
# The index must be clean first, because the cases stage files and reset
# between them.
#
# A case passes only if the hook actually ran: the exit status must be exactly
# 1 (refused) or exactly 0 (allowed). 127 means the hook was not found, which
# is a broken test rather than a passing one.
set -u
repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo" || exit 1
[ -d .git ] || { echo "not at the repository root: $repo" >&2; exit 1; }
[ -x ./.githooks/pre-commit ] || { echo "hook is not executable" >&2; exit 1; }

if ! git diff --cached --quiet; then
	echo "refusing to run with staged changes; commit or reset them first" >&2
	exit 2
fi

pass=0
fail=0

cleanup_case() {
	git reset -q
	rm -f schemes/zz.key schemes/vless-xtls-vision-reality/zz-probe.json \
		schemes/vless-xtls-vision-reality/zz.local.json
}

run_case() {
	desc=$1
	expect=$2
	out=$(./.githooks/pre-commit 2>&1)
	rc=$?
	ok=no
	if [ "$expect" = refuse ] && [ "$rc" -eq 1 ]; then ok=yes; fi
	if [ "$expect" = allow ] && [ "$rc" -eq 0 ]; then ok=yes; fi
	if [ "$ok" = yes ]; then
		printf 'PASS  %-48s %s\n' "$desc" "$expect"
		pass=$((pass + 1))
	else
		printf 'FAIL  %-48s expected %s, rc=%s\n' "$desc" "$expect" "$rc"
		printf '%s\n' "$out" | sed 's/^/        /'
		fail=$((fail + 1))
	fi
	cleanup_case
}

T=schemes/vless-xtls-vision-reality/zz-probe.json
SRC=schemes/vless-xtls-vision-reality/client.json
REALIP=212.50.249.175

# 0. control: nothing staged
git reset -q
run_case "empty index" allow

# 1. host-specific filename
cp "$SRC" schemes/vless-xtls-vision-reality/zz.local.json
git add -f schemes/vless-xtls-vision-reality/zz.local.json
run_case "staged *.local.json" refuse

# 2. certificate material
printf -- '-----BEGIN PRIVATE KEY-----\n' > schemes/zz.key
git add -f schemes/zz.key
run_case "staged *.key" refuse

# 3. a real address pasted where a placeholder was
sed "s|<SERVER_IP:203.0.113.10>|$REALIP|" "$SRC" > "$T"
git add -f "$T"
run_case "literal routable IP" refuse

# 4. a real address inside a placeholder
sed "s|<SERVER_IP:203.0.113.10>|<SERVER_IP:$REALIP>|" "$SRC" > "$T"
git add -f "$T"
run_case "routable IP inside placeholder" refuse

# 5. a real UUID inside a placeholder
sed 's|<UUID:a1b2c3d4-e5f6-7890-abcd-ef1234567890>|<UUID:9f8e7d6c-5b4a-3210-fedc-ba9876543210>|' "$SRC" > "$T"
git add -f "$T"
run_case "real-looking UUID inside placeholder" refuse

# 6. a real 43-char REALITY key inside a placeholder: the historical incident
sed 's|<PUBLIC_KEY:REDACTED_PUBLIC_KEY>|<PUBLIC_KEY:SGuVHaAwREi_8KKTRxM8u3jEV3Ite0KLgqIYLuBIKno>|' "$SRC" > "$T"
git add -f "$T"
run_case "real-looking key inside placeholder" refuse

# 7. a literal UUID outside any placeholder
sed 's|<UUID:a1b2c3d4-e5f6-7890-abcd-ef1234567890>|9f8e7d6c-5b4a-3210-fedc-ba9876543210|' "$SRC" > "$T"
git add -f "$T"
run_case "literal UUID in config" refuse

# 8. the real host config renamed to a template name: the silent leak path.
#    An operator file is the most faithful input, but the cases must not depend
#    on one existing — a clone with no local config still has to exercise the
#    path, so synthesize a filled-in config when none is present.
HOSTCFG=$(ls schemes/vless-xtls-vision-reality/*.local.json 2>/dev/null | head -n 1)
if [ -n "${HOSTCFG:-}" ]; then
	cp "$HOSTCFG" "$T"
else
	sed -e "s|<SERVER_IP:203.0.113.10>|$REALIP|" \
		-e 's|<UUID:a1b2c3d4-e5f6-7890-abcd-ef1234567890>|9f8e7d6c-5b4a-3210-fedc-ba9876543210|' \
		-e 's|<PUBLIC_KEY:REDACTED_PUBLIC_KEY>|SGuVHaAwREi_8KKTRxM8u3jEV3Ite0KLgqIYLuBIKno|' \
		"$SRC" > "$T"
fi
git add -f "$T"
run_case "real host config under a template name" refuse

# 9. control: an untouched template stays committable
git add "$SRC"
run_case "unmodified client template" allow

# 10. control: likewise on the server side
git add schemes/vless-xtls-vision-tls/server.json
run_case "unmodified server template" allow

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
