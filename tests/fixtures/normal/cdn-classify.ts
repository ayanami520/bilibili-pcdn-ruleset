// 测试样本：形状与上游 src/core/player/cdn-classify.ts 的关键部分一致
// （不包含上游全部逻辑，只保留 collect.sh 需要抽取的锚点）

import { createRetrieKeywordFilter } from 'foxts/retrie';
import { split0th } from 'foxts/split-nth';

export const mirrorRegex = /^https?:\/\/(?:upos-\w+-(?!302)\w+|(?:upos|proxy)-tf-[^/]+)\.(?:bilivideo|akamaized)\.(?:com|net)\/upgcxcode/;

export const mCdnTfRegex = /^https?:\/\/(?:(?:\d{1,3}\.){3}\d{1,3}|[^/]+\.mcdn\.bilivideo\.(?:com|cn|net))(?::\d{1,5})?\/v\d\/resource/;

const knownP2pCdnDomainPattern = createRetrieKeywordFilter([
  '302ppio',
  '302kodo',
  '.mcdn.bilivideo',
  'szbdyd.com',
  '.nexusedgeio.com',
  '.ahdohpiechei.com', // 七牛云 PCDN

  'upos-sz-mirror14b.bilivideo.com' // mirror type, upgcxcode, but it has no valid SSL cert
]);

export function isP2PCDNDomain(hostname: string): boolean {
  if (knownP2pCdnDomainPattern(hostname)) {
    return true;
  }
  // pattern: *-*302*.*
  const subdomain = split0th(hostname, '.');
  return subdomain.includes('302');
}

export function classifyCdnUrl(url: ReadonlyURL): CdnUrlClass {
  const href = url.href;
  if (href.includes('/upgcxcode/')) {
    // upos-sz-mirrorcoso1.bilivideo.com os=mcdn  ← 盲区来源：同主机带 os=mcdn 也是 PCDN
    return url.searchParams.get('os') !== 'mcdn' && !isP2PCDNDomain(url.hostname)
      ? 'mirror'
      : 'mcdn-upgcxcode';
  }
  return 'unknown';
}
