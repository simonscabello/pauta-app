// Service worker dos avisos no navegador (Web Push).
//
// Só faz duas coisas: desenhar o aviso que o servidor manda e levar o toque
// até a tela certa do app. Não guarda cache nem intercepta requisição -- o
// app continua sendo servido como sempre.
//
// Registrado com escopo `push/` (ver `pauta-web.js`): o escopo não controla
// nenhuma página do app, e é isso que garante que ele nunca interfira no
// carregamento. Para receber aviso o escopo não importa.

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('push', (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_) {
    payload = { title: event.data ? event.data.text() : '' };
  }
  const title = payload.title || 'Pauta';
  const data = payload.data || {};
  event.waitUntil(
    self.registration.showNotification(title, {
      body: payload.body || '',
      icon: '../icons/Icon-192.png',
      badge: '../icons/Icon-192.png',
      data,
      // Avisos da mesma escala substituem o anterior em vez de empilhar.
      tag: data.route || undefined,
    }),
  );
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const data = event.notification.data || {};
  const root = new URL('../', self.registration.scope).href;

  event.waitUntil(
    (async () => {
      const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
      for (const client of windows) {
        if (!client.url.startsWith(root)) continue;
        // O app aberto troca de equipe e navega sozinho (PushCoordinator).
        await client.focus();
        client.postMessage({ type: 'pauta-push-tap', data });
        return;
      }
      // Nenhuma aba aberta: abre o app já na rota, e o toque vai na consulta
      // para o app trocar a equipe ativa assim que a sessão carregar.
      const url = new URL(root);
      url.searchParams.set('pushTap', JSON.stringify(data));
      url.hash = data.route ? `#${data.route}` : '';
      await self.clients.openWindow(url.href);
    })(),
  );
});
