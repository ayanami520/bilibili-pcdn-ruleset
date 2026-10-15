# 采集报告 —— B站 PCDN

> 上游：`SukkaW/Make-Bilibili-Great-Than-Ever-Before`（MIT）
> 采集：`src/core/player/cdn-classify.ts` + `src/modules/no-p2p/policy.ts`

| 项 | 值 |
|---|---|
| 上游 master | `https://raw.githubusercontent.com/SukkaW/Make-Bilibili-Great-Than-Ever-Before/master` |
| cdn-classify.ts | 115 行 · sha256 `849a3ae8cf14c0ca13c4e545fcaf4956777b091631743fc84a2e8f41c025db57` |
| no-p2p/policy.ts | 59 行 · sha256 `8973fd0464ff88e66186f8699448a1df9e4cfec992efae97b3da3dd864fa3415` |
| 抽取条目 | 上游 7 条 |
| 产出 | `domain_suffix` 7 · `domain_keyword` 2 · `domain_regex` 1 |

## 逐条映射

| 上游条目 | 转成 |
|---|---|
| `302ppio` | domain_keyword: 302ppio |
| `302kodo` | domain_keyword: 302kodo |
| `.mcdn.bilivideo` | domain_suffix ×3: mcdn.bilivideo.cn/.com/.net |
| `szbdyd.com` | domain_suffix: szbdyd.com |
| `.nexusedgeio.com` | domain_suffix: nexusedgeio.com |
| `.ahdohpiechei.com` | domain_suffix: ahdohpiechei.com |
| `upos-sz-mirror14b.bilivideo.com` | domain_suffix: upos-sz-mirror14b.bilivideo.com |

## 盲区（域名层拦不住的部分）

- ⚠️ **`os=mcdn`**：同一个正常镜像主机（例如 `upos-sz-mirrorcoso1.bilivideo.com`）在带 `os=mcdn` 参数时也是 PCDN —— **域名/IP 层无法区分**，只有 MBGTEB 那种改写 URL 的做法能治。
- ⚠️ **纯 IP / `mcdn /v1/resource` 型**（上游 `mCdnTfRegex`）：URL 里直接是 IP，**DNS 层完全拦不住**。
- ℹ️ **白名单**：上游的 `PROXY_TF` = `proxy-tf-all-ws.bilivideo.com`（B站官方代理，用来取 PCDN 内容）**不应屏蔽**，否则会破坏 MBGTEB 自身的回退链路。

## 告警

无
