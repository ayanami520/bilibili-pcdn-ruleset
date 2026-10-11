#!/bin/sh
#
# 采集 B站 PCDN 判定规则 -> sing-box 源格式规则集
#
# 上游 (SukkaW/Make-Bilibili-Great-Than-Ever-Before, MIT):
#   src/core/player/cdn-classify.ts
#     * knownP2pCdnDomainPattern   ← PCDN 域名/关键词清单（核心）
#     * isP2PCDNDomain() 中 "首段含 302" 的启发式
#     * mCdnTfRegex                ← 「纯 IP / mcdn /v1/resource」型 PCDN，域名层拦不住，只写进报告
#   src/modules/no-p2p/policy.ts
#     * PROXY_TF = proxy-tf-all-ws.bilivideo.com  ← 官方代理（白名单，不屏蔽）
#
# 输出:
#   src/bili-pcdn.json    源格式规则集（确定性：排序 + 去重，不含时间戳）
#   src/upstream.lock     上游 sha256 + 抽取统计（漂移检测用）
#   report/collect.md     采集报告（逐条映射 + 告警 + 盲区提示）
#
# 原则:
#   1) 上游结构变了（锚点找不到 / 条目数低于下限）⇒ 直接失败，绝不产出空或半残规则集
#   2) 上游出现"未映射"的新条目 ⇒ 兜底处理，但报告里告警（不静默）
#   3) 输出保持确定性 ⇒ 内容没变就不会产生多余提交
#
# 环境变量:
#   UP_BASE        上游 raw 前缀（默认 master 分支）
#   UPSTREAM_DIR   本地目录（测试用）：设置后从本地取上游文件，不联网
#   GH_PROXY       上游代理前缀，例如 https://gh-proxy.com/
#   WORK_DIR       临时目录（默认 .build）
#   REPORT_DIR     报告目录（默认 report）
#   MIN_ENTRIES    条目数下限，低于则失败（默认 5）
#
set -eu

UP_BASE="${UP_BASE:-https://raw.githubusercontent.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before/master}"
UPSTREAM_DIR="${UPSTREAM_DIR:-}"
WORK_DIR="${WORK_DIR:-.build}"
REPORT_DIR="${REPORT_DIR:-report}"
GH_PROXY="${GH_PROXY:-}"
MIN_ENTRIES="${MIN_ENTRIES:-5}"

RAW="$WORK_DIR/upstream"
WARNS="$WORK_DIR/collect.warns"
mkdir -p "$RAW" "$REPORT_DIR" src
: > "$WARNS"
warn_count=0

log() { printf '==> %s\n' "$*"; }
warn() {
	printf '!!! [告警] %s\n' "$*" >&2
	printf -- '- ⚠️ %s\n' "$*" >> "$WARNS"
	warn_count=$((warn_count + 1))
}
die() { printf '!!! %s\n' "$*" >&2; exit 1; }

command -v jq  >/dev/null 2>&1 || die "缺少 jq"
command -v awk >/dev/null 2>&1 || die "缺少 awk"
if [ -z "$UPSTREAM_DIR" ]; then
	command -v curl >/dev/null 2>&1 || die "缺少 curl"
fi

get() { # get <上游相对路径> <落地文件>
	# 本地测试模式：按【落地文件名】在 $UPSTREAM_DIR 里找同名文件
	# （不用上游路径的 basename —— 上游可能有两个同名 policy.ts，落地名才是唯一的）
	if [ -n "$UPSTREAM_DIR" ]; then
		src="$UPSTREAM_DIR/$(basename "$2")"
		[ -f "$src" ] || die "本地上游缺失: $src"
		cp "$src" "$2"
	else
		if [ -n "$GH_PROXY" ]; then
			curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$GH_PROXY$UP_BASE/$1"
		else
			curl -fsSL --retry 3 --retry-delay 2 -o "$2" "$UP_BASE/$1"
		fi || die "下载失败: $1"
	fi
	[ -s "$2" ] || die "上游文件为空: $1"
}

sha() { sha256sum "$1" | cut -d' ' -f1; }

# ---------- 1) 取上游 ----------
log "取上游"
get 'src/core/player/cdn-classify.ts' "$RAW/cdn-classify.ts"
get 'src/modules/no-p2p/policy.ts'    "$RAW/no-p2p-policy.ts"
CDN="$RAW/cdn-classify.ts"
P2P="$RAW/no-p2p-policy.ts"
log "  cdn-classify.ts  $(wc -l < "$CDN" | tr -d ' ') 行  sha256=$(sha "$CDN")"
log "  no-p2p/policy.ts $(wc -l < "$P2P" | tr -d ' ') 行  sha256=$(sha "$P2P")"

# ---------- 2) 抽取 knownP2pCdnDomainPattern 数组 ----------
log "抽取 knownP2pCdnDomainPattern"
awk '/knownP2pCdnDomainPattern[[:space:]]*=[[:space:]]*createRetrieKeywordFilter\(\[/,/\]\);/' "$CDN" > "$RAW/array.txt"
grep -q 'createRetrieKeywordFilter' "$RAW/array.txt" ||
	die "找不到 knownP2pCdnDomainPattern 数组（上游结构可能已变）⇒ 中止，请人工核对"
grep -o "'[^']*'" "$RAW/array.txt" | tr -d "'" > "$RAW/entries.txt"
entry_n=$(wc -l < "$RAW/entries.txt" | tr -d ' ')
[ "$entry_n" -ge "$MIN_ENTRIES" ] ||
	die "只抽到 $entry_n 条（下限 $MIN_ENTRIES）⇒ 中止，不产出半残规则集"
log "  抽到 $entry_n 条"

# ---------- 3) 映射: 上游条目 -> sing-box 匹配器 ----------
# 上游是"关键词包含"语义（createRetrieKeywordFilter 用的是 includes），
# 但 sing-box 里 domain_suffix 走字典树、比 domain_keyword 快得多，
# 所以能表达成后缀的一律转后缀；只有带前缀通配含义的才留关键词。
SUF="$RAW/suffix.txt"; KW="$RAW/keyword.txt"; MAP="$RAW/mapping.txt"
: > "$SUF"; : > "$KW"; : > "$MAP"
while IFS= read -r e || [ -n "$e" ]; do
	[ -n "$e" ] || continue
	case "$e" in
		.mcdn.bilivideo)
			# 上游语义 = "主机名含 .mcdn.bilivideo" ⇒ 展开成三个后缀（覆盖 .cn/.com/.net）
			printf '%s\n' mcdn.bilivideo.cn mcdn.bilivideo.com mcdn.bilivideo.net >> "$SUF"
			printf '%s\t%s\n' "$e" 'domain_suffix ×3: mcdn.bilivideo.cn/.com/.net' >> "$MAP"
			;;
		.*)
			# 其它前导点条目 = 后缀（去掉点即可，sing-box 的 suffix 自带子域匹配）
			printf '%s\n' "${e#.}" >> "$SUF"
			printf '%s\t%s\n' "$e" "domain_suffix: ${e#.}" >> "$MAP"
			;;
		302*)
			# 302ppio / 302kodo = 机房前缀的通配模式 ⇒ 保留关键词
			printf '%s\n' "$e" >> "$KW"
			printf '%s\t%s\n' "$e" "domain_keyword: $e" >> "$MAP"
			;;
		*.*)
			# 普通域名条目 = 后缀
			printf '%s\n' "$e" >> "$SUF"
			printf '%s\t%s\n' "$e" "domain_suffix: $e" >> "$MAP"
			;;
		*)
			# 单标签（既没有前导点也不以 302 开头）：上游可能新增了通配模式
			printf '%s\n' "$e" >> "$KW"
			printf '%s\t%s\n' "$e" "domain_keyword: $e（兜底，请人工确认）" >> "$MAP"
			warn "上游新增了未映射条目 '$e'，已按 domain_keyword 兜底处理，请人工确认是否合适"
			;;
	esac
done < "$RAW/entries.txt"

# ---------- 4) 抽取 "首段含 302" 启发式 ----------
if grep -q "includes('302')" "$CDN"; then
	HEURISTIC_OK=1
else
	die "找不到 '302' 启发式（isP2PCDNDomain 可能被改写）⇒ 中止，请人工核对上游逻辑"
fi
# 与上游等价的 sing-box 表达: 主机名第一段含 "302" 的 bilivideo 主机
REGEX='^[^.]*302[^.]*\.bilivideo\.(com|cn|net)$'
log "  启发式 OK: $REGEX"

# ---------- 5) 盲区探测（写进报告，不影响产物） ----------
grep -q 'mCdnTfRegex' "$CDN" && BLIND_MCDN_TF=1 || BLIND_MCDN_TF=0
grep -q "searchParams.get('os')" "$CDN" && BLIND_OS_MCDN=1 || BLIND_OS_MCDN=0
grep -o "PROXY_TF[[:space:]]*=[[:space:]]*'[^']*'" "$P2P" | head -n 1 | sed "s/.*'\(.*\)'/\1/" > "$RAW/proxy_tf.txt" || true
PROXY_TF=$(cat "$RAW/proxy_tf.txt" 2>/dev/null || true)

# ---------- 6) 生成源格式规则集 ----------
log "生成 src/bili-pcdn.json"
arr() { jq -R -s 'split("\n") | map(select(length > 0)) | unique | sort' "$1"; }
SF=$(arr "$SUF")
KWA=$(arr "$KW")
jq -n --argjson sf "$SF" --argjson kw "$KWA" --arg re "$REGEX" --arg up "$UP_BASE" \
	'{ version: 1, rules:
		[ (select(($sf | length) > 0) | { domain_suffix: $sf }),
		  (select(($kw | length) > 0) | { domain_keyword: $kw }),
		  { domain_regex: [ $re ] } ] }' > "$WORK_DIR/bili-pcdn.json" ||
	die "jq 生成源格式失败"

# 确定性输出：字段排序 + 数组去重排序（与主仓库 build.sh 的风格保持一致）
jq -S '.rules = [ .rules[] | with_entries(if (.value | type) == "array" then .value |= (unique | sort) else . end) ]' \
	"$WORK_DIR/bili-pcdn.json" > src/bili-pcdn.json || die "jq 规范化失败"

sf_n=$(jq '.rules[0].domain_suffix | length' src/bili-pcdn.json)
kw_n=$(jq '[.rules[] | select(.domain_keyword) | .domain_keyword | length] | add // 0' src/bili-pcdn.json)
[ "$sf_n" -ge 1 ] || die "domain_suffix 为空 ⇒ 中止"
log "  domain_suffix=$sf_n  domain_keyword=$kw_n  domain_regex=1"

# ---------- 7) 上游锁定信息（漂移检测） ----------
{
	printf '# 上游锁定信息 —— 由 scripts/collect.sh 生成（采集策略：跟随 master 最新）\n'
	printf '# 本文件用于检测"上游判定逻辑是否变了"：变了会体现在报告里，便于人工复核。\n'
	printf '%s  %s\n' "$(sha "$CDN")" 'src/core/player/cdn-classify.ts'
	printf '%s  %s\n' "$(sha "$P2P")" 'src/modules/no-p2p/policy.ts'
	printf '# 抽取统计: 上游条目=%s  domain_suffix=%s  domain_keyword=%s  domain_regex=1\n' "$entry_n" "$sf_n" "$kw_n"
} > src/upstream.lock

# ---------- 8) 采集报告 ----------
{
	printf '# 采集报告 —— B站 PCDN\n\n'
	printf '> 上游：`SukkaW/Make-Bilibili-Great-Than-Ever-Before`（MIT）\n'
	printf '> 采集：`src/core/player/cdn-classify.ts` + `src/modules/no-p2p/policy.ts`\n\n'
	printf '| 项 | 值 |\n|---|---|\n'
	printf '| 上游 master | `%s` |\n' "$UP_BASE"
	printf '| cdn-classify.ts | %s 行 · sha256 `%s` |\n' "$(wc -l < "$CDN" | tr -d ' ')" "$(sha "$CDN")"
	printf '| no-p2p/policy.ts | %s 行 · sha256 `%s` |\n' "$(wc -l < "$P2P" | tr -d ' ')" "$(sha "$P2P")"
	printf '| 抽取条目 | 上游 %s 条 |\n' "$entry_n"
	printf '| 产出 | `domain_suffix` %s · `domain_keyword` %s · `domain_regex` 1 |\n' "$sf_n" "$kw_n"
	printf '\n## 逐条映射\n\n| 上游条目 | 转成 |\n|---|---|\n'
	while IFS='	' read -r a b || [ -n "$a" ]; do
		printf '| `%s` | %s |\n' "$a" "$b"
	done < "$MAP"
	printf '\n## 盲区（域名层拦不住的部分）\n\n'
	printf '%s\n' '- ⚠️ **`os=mcdn`**：同一个正常镜像主机（例如 `upos-sz-mirrorcoso1.bilivideo.com`）在带 `os=mcdn` 参数时也是 PCDN —— **域名/IP 层无法区分**，只有 MBGTEB 那种改写 URL 的做法能治。'
	if [ "$BLIND_MCDN_TF" -eq 1 ]; then
		printf '%s\n' '- ⚠️ **纯 IP / `mcdn /v1/resource` 型**（上游 `mCdnTfRegex`）：URL 里直接是 IP，**DNS 层完全拦不住**。'
	fi
	if [ -n "$PROXY_TF" ]; then
		printf '%s\n' "- ℹ️ **白名单**：上游的 \`PROXY_TF\` = \`$PROXY_TF\`（B站官方代理，用来取 PCDN 内容）**不应屏蔽**，否则会破坏 MBGTEB 自身的回退链路。"
	fi
	printf '\n## 告警\n\n'
	if [ "$warn_count" -eq 0 ]; then printf '无\n'; else cat "$WARNS"; fi
} > "$REPORT_DIR/collect.md"

log "完成: src/bili-pcdn.json / src/upstream.lock / $REPORT_DIR/collect.md（告警 $warn_count 条）"
