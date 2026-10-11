// 测试样本：故意"改坏"上游结构 —— 变量被重命名、302 启发式被删掉。
// 期望：collect.sh 必须失败（宁可构建红，也不能静默产出空/半残规则集）

import { createRetrieKeywordFilter } from 'foxts/retrie';

export const mCdnTfRegex = /^https?:\/\/(?:[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))\/v\d\/resource/;

// 变量名变了：不再是 knownP2pCdnDomainPattern
const p2pDomainList = createRetrieKeywordFilter([
  '302ppio',
  'szbdyd.com'
]);

export function isP2PCDNDomain(hostname: string): boolean {
  // 302 启发式也没了
  return p2pDomainList(hostname);
}
