#!/bin/sh
#
# 抽取器回归测试（不联网，全部用 tests/fixtures 里的固定样本）
#
# 覆盖:
#   1) 正常样本 ⇒ 抽取结果必须与 tests/fixtures/expected 完全一致，且无告警
#   2) 正常样本 ⇒ build.sh 的编译/往返/自测必须通过（需要 sing-box）
#   3) 上游结构被改坏 ⇒ collect.sh 必须失败（绝不静默产出空/半残规则集）
#   4) 条目数低于下限 ⇒ collect.sh 必须失败
#
set -eu

ROOT=$(pwd)
FIX="$ROOT/tests/fixtures"
TD="${TMPDIR:-/tmp}/bili-pcdn-test.$$"
rm -rf "$TD"
mkdir -p "$TD"

pass() { printf '  ✓ %s\n' "$*"; }
fail() { printf '  ✗ %s\n' "$*" >&2; exit 1; }

printf '==> 用例 1: 正常样本 ⇒ 抽取结果与期望一致\n'
mkdir -p "$TD/case1"
if ! ( cd "$TD/case1" && UPSTREAM_DIR="$FIX/normal" sh "$ROOT/scripts/collect.sh" > "$TD/case1.log" 2>&1 ); then
	cat "$TD/case1.log" >&2
	fail "collect.sh 在正常样本上失败"
fi
if ! cmp -s "$TD/case1/src/bili-pcdn.json" "$FIX/expected/bili-pcdn.json"; then
	printf '  --- 实际 ---\n' >&2
	cat "$TD/case1/src/bili-pcdn.json" >&2
	printf '  --- 期望 ---\n' >&2
	cat "$FIX/expected/bili-pcdn.json" >&2
	fail "抽取结果与期望不一致"
fi
if grep -q '\[告警\]' "$TD/case1.log"; then
	cat "$TD/case1.log" >&2
	fail "正常样本不应产生告警"
fi
pass "产物与期望一致，且无告警"

printf '==> 用例 2: 正常样本 ⇒ 编译 + 往返校验 + 实际匹配自测\n'
if command -v "${SING_BOX:-sing-box}" > /dev/null 2>&1; then
	if ! ( cd "$TD/case1" && sh "$ROOT/scripts/build.sh" > "$TD/build.log" 2>&1 ); then
		cat "$TD/build.log" >&2
		fail "build.sh 失败"
	fi
	[ -s "$TD/case1/dist/bili-pcdn.srs" ] || fail "没有产出 dist/bili-pcdn.srs"
	pass "编译/往返/自测全部通过（$(wc -c < "$TD/case1/dist/bili-pcdn.srs" | tr -d ' ') B）"
else
	printf '  - 跳过：本机没有 sing-box（CI 上会执行）\n'
fi

printf '==> 用例 3: 上游结构被改坏 ⇒ 必须失败\n'
mkdir -p "$TD/case3"
if ( cd "$TD/case3" && UPSTREAM_DIR="$FIX/broken" sh "$ROOT/scripts/collect.sh" > "$TD/case3.log" 2>&1 ); then
	cat "$TD/case3.log" >&2
	fail "锚点丢失时竟然成功了（会把空/半残规则集推上线）"
fi
pass "已正确失败：$(grep -m1 '!!!' "$TD/case3.log" || true)"

printf '==> 用例 4: 条目数低于下限 ⇒ 必须失败\n'
mkdir -p "$TD/case4"
if ( cd "$TD/case4" && UPSTREAM_DIR="$FIX/short" sh "$ROOT/scripts/collect.sh" > "$TD/case4.log" 2>&1 ); then
	cat "$TD/case4.log" >&2
	fail "条目过少时竟然成功了"
fi
pass "已正确失败：$(grep -m1 '!!!' "$TD/case4.log" || true)"

rm -rf "$TD"
printf '==> 全部用例通过\n'
