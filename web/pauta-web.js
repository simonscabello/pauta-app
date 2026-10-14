// A ponte entre o app (Dart) e o que só o navegador sabe fazer: os avisos
// (Web Push) e baixar um arquivo. O Dart chama `window.pautaWeb` por
// `dart:js_interop` (lib/core/platform/web_bridge_web.dart).
//
// Em JavaScript, e não em Dart, porque registrar o service worker e esperar
// ele ficar ativo é uma sequência de promessas e eventos que fica curta aqui
// e longa e frágil do outro lado.
(function () {
  const SW_URL = 'push-sw.js';
  const SW_SCOPE = 'push/';

  const pending = [];
  let tapListener = null;

  function supported() {
    return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
  }

  function isIos() {
    return /iPhone|iPad|iPod/.test(navigator.userAgent) ||
      (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  }

  function standalone() {
    return window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
  }

  function permission() {
    return 'Notification' in window ? Notification.permission : 'unsupported';
  }

  async function requestPermission() {
    if (!('Notification' in window)) return 'unsupported';
    try {
      return await Notification.requestPermission();
    } catch (_) {
      return Notification.permission;
    }
  }

  function base64UrlToBytes(value) {
    const padded = (value + '='.repeat((4 - (value.length % 4)) % 4))
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    const raw = atob(padded);
    const bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
    return bytes;
  }

  function sameKey(buffer, bytes) {
    if (!buffer) return false;
    const current = new Uint8Array(buffer);
    if (current.length !== bytes.length) return false;
    return current.every((byte, index) => byte === bytes[index]);
  }

  async function registration() {
    let reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
    if (!reg) reg = await navigator.serviceWorker.register(SW_URL, { scope: SW_SCOPE });
    if (reg.active) return reg;
    const worker = reg.installing || reg.waiting;
    if (worker) {
      await new Promise((resolve) => {
        if (worker.state === 'activated') return resolve();
        worker.addEventListener('statechange', () => {
          if (worker.state === 'activated') resolve();
        });
      });
    }
    return reg;
  }

  // A assinatura deste navegador, em JSON, ou null sem permissão. Assina na
  // primeira vez e reaproveita depois; se a chave do servidor mudou, troca.
  async function subscribe(publicKey) {
    if (!supported() || Notification.permission !== 'granted' || !publicKey) return null;
    try {
      const reg = await registration();
      const key = base64UrlToBytes(publicKey);
      let sub = await reg.pushManager.getSubscription();
      if (sub && !sameKey(sub.options && sub.options.applicationServerKey, key)) {
        await sub.unsubscribe();
        sub = null;
      }
      if (!sub) {
        sub = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
      }
      return JSON.stringify(sub);
    } catch (error) {
      console.warn('Pauta: aviso no navegador indisponível', error);
      return null;
    }
  }

  // A assinatura que já existe, sem criar outra -- é o que a saída da conta
  // manda o servidor esquecer.
  async function currentSubscription() {
    if (!supported()) return null;
    try {
      const reg = await navigator.serviceWorker.getRegistration(SW_SCOPE);
      const sub = reg ? await reg.pushManager.getSubscription() : null;
      return sub ? JSON.stringify(sub) : null;
    } catch (_) {
      return null;
    }
  }

  function deliver(json) {
    if (tapListener) tapListener(json);
    else pending.push(json);
  }

  function onTap(callback) {
    tapListener = callback;
    while (pending.length) callback(pending.shift());
  }

  // O toque que abriu o app (o service worker o põe na consulta). Lido uma
  // vez e tirado do endereço, para um F5 não repetir a navegação.
  function initialTap() {
    const params = new URLSearchParams(window.location.search);
    const value = params.get('pushTap');
    if (!value) return null;
    params.delete('pushTap');
    const query = params.toString();
    window.history.replaceState(
      window.history.state,
      '',
      window.location.pathname + (query ? `?${query}` : '') + window.location.hash,
    );
    return value;
  }

  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.addEventListener('message', (event) => {
      if (event.data && event.data.type === 'pauta-push-tap') {
        deliver(JSON.stringify(event.data.data || {}));
      }
    });
    navigator.serviceWorker.startMessages();
  }

  function download(name, mime, content) {
    const blob = new Blob([content], { type: mime });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  window.pautaWeb = {
    pushSupported: supported,
    // iPhone e iPad só recebem aviso com o Pauta adicionado à tela de início.
    pushNeedsInstall: () => isIos() && !standalone() && !supported(),
    pushPermission: permission,
    pushRequestPermission: requestPermission,
    pushSubscribe: subscribe,
    pushCurrentSubscription: currentSubscription,
    pushOnTap: onTap,
    pushInitialTap: initialTap,
    download,
  };
})();
