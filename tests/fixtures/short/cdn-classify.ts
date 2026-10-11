// 测试样本：数组结构正常，但条目只有 1 条（低于 MIN_ENTRIES=5）。
// 期望：collect.sh 必须失败 —— 这通常意味着"抽取只匹配到了半个数组"。

import { createRetrieKeywordFilter } from 'foxts/retrie';

const knownP2pCdnDomainPattern = createRetrieKeywordFilter([
  'szbdyd.com'
]);

export function isP2PCDNDomain(hostname: string): boolean {
  if (knownP2pCdnDomainPattern(hostname)) {
    return true;
  }
  const subdomain = hostname.split('.')[0];
  return subdomain.includes('302');
}
