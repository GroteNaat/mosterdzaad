if ('serviceWorker' in navigator && window.isSecureContext) {
  const report = (message, transient = false) => {
    const banner = document.createElement('div');
    banner.setAttribute('role', 'status');
    banner.style.cssText = 'position:fixed;bottom:max(12px,env(safe-area-inset-bottom));right:12px;max-width:440px;box-sizing:border-box;width:calc(100% - 24px);z-index:9999;padding:12px;background:#f0f2e8;color:#263725;border:1px solid #526c49;border-radius:8px;font:14px system-ui;display:flex;gap:12px;align-items:center';
    const label = document.createElement('span');
    label.style.flex = '1'; label.textContent = message;
    const close = document.createElement('button'); close.textContent = 'Sluiten';
    close.onclick = () => banner.remove();
    banner.append(label, close); document.body.append(banner);
    if (transient) setTimeout(() => banner.remove(), 6000);
  };
  navigator.serviceWorker.register('service_worker.js', {updateViaCache: 'none'})
    .then(registration => {
      const ready = () => report('Nieuwe versie beschikbaar. Sla je werk op en sluit alle vensters van Mosterdzaad om bij de volgende start bij te werken.');
      if (registration.waiting) ready();
      registration.addEventListener('updatefound', () => {
        const worker = registration.installing;
        worker.addEventListener('statechange', () => {
          if (worker.state === 'installed') {
            if (navigator.serviceWorker.controller) ready();
            else report('Mosterdzaad is klaar voor offline gebruik.', true);
          }
        });
      });
    }).catch(() => report('Offline gebruik is nog niet beschikbaar. Open de app opnieuw met internet.'));
}
