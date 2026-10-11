#!/bin/sh
#
# 编译 src/bili-pcdn.json -> 可直接订阅的产物 + 自测 + 报告
#
# 产物:
#   dist/bili-pcdn.srs            ★ sing-box 订阅用（binary，format: "binary"）
#   dist/bili-pcdn.json           源格式（供 format: "source" 订阅 / 人工阅读）
#   dist/bili-pcdn-domains.txt    纯域名清单（后缀一条一行，供 AdGuard/dnsmasq/脚本用）
#   report/report.md              构建报告（无时间戳 ⇒ 内容不变则不产生提交）
#
# 自测（防止"看起来成功但匹配错了"）:
#   正向：mcdn 随机子域 / 302ppio 主机 / szbdyd  必须是 HIT
#   反向：B站主站 / 正常 bcache 主机              必须是 MISS
#
# 环境变量:
#   SING_BOX     sing-box 可执行文件（默认 sing-box）
#   SRC         源格式规则集（默认 src/bili-pcdn.json）
#   OUT_DIR      产物目录（默认 dist）
#   REPORT_DIR   报告目录（默认 report）
#
set -eu

SING_BOX="${SING_BOX:-sing-box}"
SRC="${SRC:-src/bili-pcdn.json}"
OUT_DIR="${OUT_DIR:-dist}"
REPORT_DIR="${REPORT_DIR:-report}"
NAME=bili-pcdn

log() { printf '==> %s\n' "$*"; }
die() { printf '!!! %s\n' "$*" >&2; exit 1; }

command -v "$SING_BOX" >/dev/null 2>&1 || die "缺少 sing-box（$SING_BOX）"
command -v jq >/dev/null 2>&1 || die "缺少 jq"
[ -s "$SRC" ] || die "缺少 $SRC（先运行 scripts/collect.sh）"

mkdir -p "$OUT_DIR" "$REPORT_DIR"

# ---------- 1) 结构自检（编译前就该拦住的低级错误） ----------
sf_n=$(jq '[.rules[] | select(.domain_suffix) | .domain_suffix | length] | add // 0' "$SRC")
kw_n=$(jq '[.rules[] | select(.domain_keyword) | .domain_keyword | length] | add // 0' "$SRC")
re_n=$(jq '[.rules[] | select(.domain_regex) | .domain_regex | length] | add // 0' "$SRC")
[ "$sf_n" -ge 1 ] || die "domain_suffix 为 0 ⇒ 产物无意义，中止"
[ "$re_n" -ge 1 ] || die "domain_regex 为 0（302 启发式丢了）⇒ 中止"
log "源格式: domain_suffix=$sf_n  domain_keyword=$kw_n  domain_regex=$re_n"

# ---------- 2) 编译 ----------
SRS="$OUT_DIR/$NAME.srs"
"$SING_BOX" rule-set compile "$SRC" -o "$SRS" || die "compile 失败"
size=$(wc -c < "$SRS" | tr -d ' ')
[ "$size" -ge 32 ] || die "产物仅 ${size}B，文件级异常，中止"
log "dist/$NAME.srs  ${size}B"

# ---------- 3) 变体 ----------
cp "$SRC" "$OUT_DIR/$NAME.json"
{
	printf '# B站 PCDN 域名清单（由 scripts/build.sh 生成）\n'
	printf '# 仅含 domain_suffix 条目；domain_keyword(%s 条) 与 domain_regex 见 dist/%s.json\n' "$kw_n" "$NAME"
	printf '# 上游: SukkaW/Make-Bilibili-Great-Than-Ever-Before (MIT)\n'
	jq -r '[.rules[] | select(.domain_suffix) | .domain_suffix[]] | unique | sort | .[]' "$SRC"
} > "$OUT_DIR/$NAME-domains.txt"
log "dist/$NAME.json + dist/$NAME-domains.txt（$(grep -cv '^#' "$OUT_DIR/$NAME-domains.txt" | tr -d ' ') 个后缀）"

# ---------- 4) 往返校验（编译产物能反编译回同样条数） ----------
"$SING_BOX" rule-set decompile "$SRS" -o "$REPORT_DIR/.roundtrip.json" || die "decompile 失败（产物可疑）"
rt_sf=$(jq '[.rules[]? | select(.domain_suffix) | .domain_suffix | length] | add // 0' "$REPORT_DIR/.roundtrip.json")
[ "$rt_sf" = "$sf_n" ] || die "往返不一致: 源 $sf_n 条, 产物 $rt_sf 条"
log "往返校验 OK（$rt_sf 条后缀）"

# ---------- 5) 自测：实际匹配（这是最关键的一步） ----------
check_match() { # check_match <主机名> <期望 HIT|MISS> <说明>
	got=MISS
	if [ -n "$("$SING_BOX" rule-set match "$SRS" "$1" -f binary 2>&1 | tail -n 1 || true)" ]; then
		got=HIT
	fi
	[ "$got" = "$2" ] || die "自测失败: $1 期望 $2 实际 $got（$3）"
	log "  自测 $1 => $got ✓  （$3）"
}
log "自测"
check_match 'xy123x181x114x35xy.mcdn.bilivideo.cn' HIT  '真实观测到的 PCDN 子域'
check_match 'mcdn.bilivideo.com'                  HIT  'mcdn 主域'
check_match 'upos-hz-302ppio.bilivideo.com'       HIT  '302ppio 关键词'
check_match 'szbdyd.com'                          HIT  '已弃用 PCDN'
check_match 'www.bilibili.com'                    MISS 'B站主站（必须放行）'
check_match 'cn-sccd-cu-01-01.bilivideo.com'      MISS '正常 bcache 节点（必须放行）'
check_match 'upos-sz-mirrorcoso1.bilivideo.com'   MISS '正常镜像（必须放行）'

# ---------- 6) 报告（不含时间戳） ----------
prev_lock=''
[ -f src/upstream.lock ] && prev_lock=$(cat src/upstream.lock)
{
	printf '# 构建报告 —— B站 PCDN 规则集\n\n'
	printf '> 由 `scripts/build.sh` 生成。**不含时间戳**：内容不变时不会产生提交。\n\n'
	printf '| 项 | 值 |\n|---|---|\n'
	printf '| 产物 | `dist/%s.srs` — %s B |\n' "$NAME" "$size"
	printf '| 匹配器 | domain_suffix=%s · domain_keyword=%s · domain_regex=%s |\n' "$sf_n" "$kw_n" "$re_n"
	printf '| 自测 | 7 项全过（3 正向 / 3 反向 / +1 主域）|\n'
	printf '\n## 订阅地址\n\n'
	printf '```\n'
	printf 'sing-box（binary）: https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/%s.srs\n' "$NAME"
	printf '源格式（source）   : https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/%s.json\n' "$NAME"
	printf '纯域名清单         : https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/%s-domains.txt\n' "$NAME"
	printf '```\n\n'
	printf '## 上游锁定\n\n```\n%s\n```\n' "$prev_lock"
	printf '\n采集明细见 [`report/collect.md`](collect.md)。\n'
} > "$REPORT_DIR/report.md"
rm -f "$REPORT_DIR/.roundtrip.json"

log "完成: $OUT_DIR/$NAME.srs · $OUT_DIR/$NAME.json · $OUT_DIR/$NAME-domains.txt · $REPORT_DIR/report.md"
