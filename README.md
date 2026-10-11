# bilibili-pcdn-ruleset

自动采集 **B站 PCDN（P2P CDN）** 判定逻辑，并转换成 **sing-box 可直接订阅** 的规则集。
每 **24 小时** 自动重建一次。

- 上游（唯一来源）：[`SukkaW/Make-Bilibili-Great-Than-Ever-Before`](https://github.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before)（MIT）
  - `src/core/player/cdn-classify.ts` —— PCDN 域名/关键词清单 + “首段含 302” 启发式
  - `src/modules/no-p2p/policy.ts` —— 官方代理 `PROXY_TF`（白名单提示）
- 本仓库**不包含上游代码**，只提取其中的“清单/判定条件”，转换成规则集。

## 订阅地址

| 用途 | 地址 |
|---|---|
| ★ **sing-box（binary）** | `https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn.srs` |
| 源格式（source） | `https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn.json` |
| 纯域名清单（人看/AdGuard/dnsmasq） | `https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn-domains.txt` |

> 直连（不走代理前缀）把开头的 `https://gh-proxy.com/` 去掉即可。

## 产物

| 文件 | 说明 |
|---|---|
| `dist/bili-pcdn.srs` | sing-box 二进制规则集（`format: "binary"`） |
| `dist/bili-pcdn.json` | sing-box 源格式（`format: "source"`） |
| `dist/bili-pcdn-domains.txt` | 仅 `domain_suffix` 的纯域名清单（每行一个后缀） |
| `report/report.md` | 构建报告（产物/匹配器统计/上游锁定） |
| `report/collect.md` | 采集报告（**逐条映射** + 告警 + 盲区说明） |
| `src/bili-pcdn.json` | 源格式规则集（产物来源，可读可 diff） |
| `src/upstream.lock` | 上游文件 sha256（漂移检测） |

## 路由器侧引用（sing-box）

```json
{
  "tag": "bili-pcdn",
  "type": "remote",
  "format": "binary",
  "url": "https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn.srs",
  "update_interval": "1d",
  "download_detour": "direct"
}
```

`download_detour: "direct"` 必填（否则规则集下载会走默认出站，可能阻塞启动）。

### 怎么用（建议两步走）

**第一步：DNS 层拦（推荐先做，风险最低）** —— 客户端拿不到 IP，自然会回退到官方 CDN：

```json
{ "rule_set": ["bili-pcdn"], "action": "predefined", "rcode": "NXDOMAIN" }
```

**第二步（可选）：路由层兜底** —— 防止客户端自带 DoH/DoT 绕过你的 DNS：

```json
{ "rule_set": ["bili-pcdn"], "action": "reject" }
```

⚠️ 两条都必须在**任何 `direct` 规则之前**（否则会被“直连”先命中）。

## 采集与映射规则

| 上游内容 | 转成 | 理由 |
|---|---|---|
| `.mcdn.bilivideo`（关键词语义） | `domain_suffix`: `mcdn.bilivideo.cn` / `.com` / `.net` | sing-box 的后缀匹配走字典树，比 `domain_keyword` 线性扫描快得多 |
| `szbdyd.com`、`.nexusedgeio.com`、`.ahdohpiechei.com`、`upos-sz-mirror14b.bilivideo.com` | `domain_suffix` | 去前导点即可；后缀自带子域匹配 |
| `302ppio`、`302kodo` | `domain_keyword` | 上游语义是“含 302ppio/302kodo 的任意主机”，保留通配含义 |
| “主机名首段含 `302`” 启发式 | `domain_regex`: `^[^.]*302[^.]*\.bilivideo\.(com\|cn\|net)$` | 与上游判定等价 |

## ⚠️ 已知盲区（域名层拦不住的部分）

| 盲区 | 说明 |
|---|---|
| **`os=mcdn`** | ★ 同一个**正常镜像主机**（如 `upos-sz-mirrorcoso1.bilivideo.com`）在 URL 带 `os=mcdn` 时**也是 PCDN** —— 域名/IP 层**无法区分**，只有 MBGTEB 那种“改写 URL”的做法能治。本规则集会**放行**这类主机（拦了会伤正常播放）。 |
| **纯 IP / `mcdn /v1/resource` 型** | 上游 `mCdnTfRegex`：URL 里直接写 IP，**DNS 层完全拦不住**。 |
| **客户端自带 DoH/DoT** | 手机/电视若开了“私人 DNS”，DNS 层拦截会被绕过 ⇒ 需要同时上路由层 `reject`。 |
| **白名单** | 上游的 `PROXY_TF`（`proxy-tf-all-ws.bilivideo.com`）是 B站官方代理，**不应屏蔽**（否则会破坏 MBGTEB 自身的回退链路）。本仓库不包含它。 |

## 自动化

- **每 24 小时**重建：`cron: '0 18 * * *'`（UTC）= 北京时间 **02:00**
  （GitHub schedule 是“尽力而为”，可能迟到；可随时在 Actions 页手动触发）
- `push` 到 `main` 与 `workflow_dispatch` 也会触发
- **只在内容变化时提交**：输出经过排序+去重，报告里不含时间戳 ⇒ 没有变化就不会有提交
- 上游逻辑变更会体现在 `src/upstream.lock` + `report/collect.md` 里，便于人工复核

## 失败即中止（不会产出半残规则集）

| 情况 | 行为 |
|---|---|
| 找不到 `knownP2pCdnDomainPattern` 数组（上游重构） | ❌ 构建失败 |
| 抽取条目数 < `MIN_ENTRIES`（默认 5） | ❌ 构建失败 |
| 找不到 `"302"` 启发式 | ❌ 构建失败 |
| 上游出现**未映射**的新条目 | ⚠️ 兜底为 `domain_keyword` + 报告高亮告警 |
| 编译产物体积 < 32B / 往返条数不一致 / 自测不通过 | ❌ 构建失败 |

自测项（每次构建都跑，`scripts/build.sh`）：
`xy123x181x114x35xy.mcdn.bilivideo.cn` / `mcdn.bilivideo.com` / `upos-hz-302ppio.bilivideo.com` / `szbdyd.com` ⇒ **必须命中**；
`www.bilibili.com` / `cn-sccd-cu-01-01.bilivideo.com` / `upos-sz-mirrorcoso1.bilivideo.com` ⇒ **必须不命中**。

## 本地构建

依赖：`curl` `jq` `awk` `sha256sum` `sing-box`（版本与路由器一致，例：1.12.25）。

```sh
# 1) 采集（国内网络建议加代理前缀）
GH_PROXY=https://gh-proxy.com/ sh scripts/collect.sh
# 2) 编译 + 自测 + 报告
sh scripts/build.sh

# 产物：dist/bili-pcdn.srs · dist/bili-pcdn.json · dist/bili-pcdn-domains.txt
```

也可直接在 OpenWrt 路由器上跑（`scripts/` 全部是 POSIX sh）。验证：

```sh
sing-box rule-set match dist/bili-pcdn.srs xy123x181x114x35xy.mcdn.bilivideo.cn -f binary
# 注意：match 的输出走 stderr
```

## 许可与致谢

- 本仓库：**MIT**
- 上游数据来源：[`SukkaW/Make-Bilibili-Great-Than-Ever-Before`](https://github.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before)（**MIT**，作者 SukkaW）—— 感谢其维护的 PCDN 判定逻辑。
- 相关参考：[`fredqin2006-X/bilibili-pcdn-filter`](https://github.com/fredqin2006-X/bilibili-pcdn-filter)（同样是基于上游的实验性屏蔽清单）。

## 免责声明

本规则集只做一件事：**让 B站 客户端不去使用 P2P/PCDN 节点上传/下载**，从而少占家庭宽带的上行。
它**可能**影响 B站 的 P2P 加速效果；若遇到播放异常、直播异常，请先停用本规则集再排查。
本仓库与哔哩哔哩、SukkaW 均无关联。
