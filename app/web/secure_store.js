'use strict';
// Keys are non-exportable CryptoKey objects, not raw key strings in localStorage.
// Scripts executing on this origin can still request decryption. Serve the PWA
// from a dedicated HTTPS origin and never load third-party application scripts.
window.mosterdzaadSecrets = (() => {
  const dbPromise = new Promise((resolve, reject) => {
    const request = indexedDB.open('mosterdzaad-secrets-v2', 1);
    request.onupgradeneeded = () => request.result.createObjectStore('secrets');
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(new Error('Veilige browseropslag niet beschikbaar.'));
  });
  const request = r => new Promise((resolve, reject) => {r.onsuccess = () => resolve(r.result); r.onerror = () => reject(r.error);});
  async function transaction(mode, fn) {
    const db = await dbPromise, tx = db.transaction('secrets', mode);
    const done = new Promise((resolve, reject) => {tx.oncomplete = resolve; tx.onabort = tx.onerror = () => reject(tx.error);});
    const value = await fn(tx.objectStore('secrets')); await done; return value;
  }
  let pendingKey;
  const key = () => pendingKey ??= (async () => {
    const candidate = await crypto.subtle.generateKey({name:'AES-GCM', length:256}, false, ['encrypt','decrypt']);
    // Serialize compare-and-create across tabs with an IndexedDB transaction.
    return transaction('readwrite', async store => {
      const existing = await request(store.get('$key'));
      if (existing) return existing;
      await request(store.add(candidate, '$key')); return candidate;
    });
  })();
  return {
    async read(name) {
      const record = await transaction('readonly', store => request(store.get('value/'+name)));
      if (!record) return null;
      const plain = await crypto.subtle.decrypt({name:'AES-GCM',iv:record.iv,additionalData:new TextEncoder().encode(name)},await key(),record.bytes);
      return new TextDecoder().decode(plain);
    },
    async write(name, value) {
      const iv = crypto.getRandomValues(new Uint8Array(12));
      const bytes = await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:new TextEncoder().encode(name)},await key(),new TextEncoder().encode(value));
      await transaction('readwrite', store => request(store.put({iv,bytes},'value/'+name)));
    },
    async remove(name) { await transaction('readwrite', store => request(store.delete('value/'+name))); }
  };
})();
