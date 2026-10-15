// PDF 정리기 오프라인 캐시
// - 화면(HTML): 인터넷이 되면 항상 최신 버전, 안 되면(또는 3초 넘게 걸리면) 저장해 둔 버전
// - 나머지 파일: 저장해 둔 것을 먼저 쓰고 뒤에서 갱신
const C = 'pdfjr-v9';
const ASSETS = ['./', 'index.html', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png'];
self.addEventListener('install', e => { e.waitUntil(caches.open(C).then(c => c.addAll(ASSETS))); self.skipWaiting(); });
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== C).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
function save(req, r){ if (r && r.ok) { const copy = r.clone(); caches.open(C).then(c => c.put(req, copy)); } return r; }
self.addEventListener('fetch', e => {
  const req = e.request;
  const u = new URL(req.url);
  if (req.method !== 'GET' || u.origin !== location.origin || u.pathname.endsWith('version.json')) return;  // 버전 확인은 항상 인터넷으로
  if (req.mode === 'navigate') {
    e.respondWith((async () => {
      const cached = caches.match('index.html');
      const net = fetch(req.url, {cache: 'no-cache', credentials: 'same-origin'}).then(r => { if (r.ok) caches.open(C).then(c => c.put('index.html', r.clone())); return r; });
      const timeout = new Promise(ok => setTimeout(ok, 4000));
      try {
        const r = await Promise.race([net, timeout.then(() => cached)]);
        if (r) return r;
      } catch {}
      return (await cached) || net;
    })());
    return;
  }
  e.respondWith(caches.match(req, {ignoreSearch: true}).then(hit => {
    const net = fetch(req).then(r => save(req, r)).catch(() => hit);
    return hit || net;
  }));
});
