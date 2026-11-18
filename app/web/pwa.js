if ('serviceWorker' in navigator && window.isSecureContext) {
  const report = message => {
    const banner = document.createElement('div');
    banner.setAttribute('role', 'status');
    banner.style.cssText = 'position:fixed;bottom:8px;left:8px;right:8px;z-index:9999;padding:12px;background:#f0f2e8;color:#263725;border:1px solid #526c49;border-radius:8px;font:14px system-ui;display:flex;gap:12px;align-items:center';
    const label = document.createElement('span');
    label.style.flex = '1'; label.textContent = message;
    const close = document.createElement('button'); close.textContent = 'Sluiten';
    close.onclick = () => banner.remove();
    banner.append(label, close); document.body.append(banner);
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
            else report('Mosterdzaad is klaar voor offline gebruik.');
          }
        });
      });
    }).catch(() => report('Offline gebruik is nog niet beschikbaar. Open de app opnieuw met internet.'));
}
