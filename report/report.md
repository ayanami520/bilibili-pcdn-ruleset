# 构建报告 —— B站 PCDN 规则集

> 由 `scripts/build.sh` 生成。**不含时间戳**：内容不变时不会产生提交。

| 项 | 值 |
|---|---|
| 产物 | `dist/bili-pcdn.srs` — 217 B |
| 匹配器 | domain_suffix=7 · domain_keyword=2 · domain_regex=1 |
| 自测 | 7 项全过（3 正向 / 3 反向 / +1 主域）|

## 订阅地址

```
sing-box（binary）: https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn.srs
源格式（source）   : https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn.json
纯域名清单         : https://gh-proxy.com/https://raw.githubusercontent.com/ayanami520/bilibili-pcdn-ruleset/main/dist/bili-pcdn-domains.txt
```

## 上游锁定

```
# 上游锁定信息 —— 由 scripts/collect.sh 生成（采集策略：跟随 master 最新）
# 本文件用于检测"上游判定逻辑是否变了"：变了会体现在报告里，便于人工复核。
849a3ae8cf14c0ca13c4e545fcaf4956777b091631743fc84a2e8f41c025db57  src/core/player/cdn-classify.ts
17568e1f61a61bd89b7b9300c519f26c569b8eede7c2f1c9af75414cd5aa1786  src/modules/no-p2p/policy.ts
# 抽取统计: 上游条目=7  domain_suffix=7  domain_keyword=2  domain_regex=1
```

采集明细见 [`report/collect.md`](collect.md)。
