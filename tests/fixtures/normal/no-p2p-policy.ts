// 测试样本：形状与上游 src/modules/no-p2p/policy.ts 的关键部分一致
// collect.sh 只从里面取 PROXY_TF（白名单提示）与 szbdyd / mcdn-tf 的处理方式

import { CandidateTier } from '../../core/player/candidates';
import type { MediaCandidate } from '../../core/player/candidates';
import { classifyCdnUrl } from '../../core/player/cdn-classify';

const PROXY_TF = 'proxy-tf-all-ws.bilivideo.com';

export function noP2PPolicy(candidates: readonly MediaCandidate[]): MediaCandidate[] {
  const acceptable: MediaCandidate[] = [];
  for (let i = 0, len = candidates.length; i < len; i++) {
    const candidate = candidates[i];
    if (!candidate.p2p) {
      acceptable.push(candidate);
      continue;
    }
    const url = new URL(candidate.href);
    switch (classifyCdnUrl(url)) {
      case 'szbdyd': {
        // 已弃用的 PCDN：真实主机在 xy_usource 参数里
        const source = url.searchParams.get('xy_usource');
        if (source) {
          url.hostname = source;
          acceptable.push({ ...candidate, href: url.href });
        }
        break;
      }
      case 'mcdn-tf': {
        // 纯 IP / mcdn /v1/resource：只有官方代理能取
        const proxy = new URL(`https://${PROXY_TF}`);
        proxy.searchParams.set('url', candidate.href);
        acceptable.push({ ...candidate, href: proxy.href });
        break;
      }
      default:
        break;
    }
  }
  return acceptable;
}
