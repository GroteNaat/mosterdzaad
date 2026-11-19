'use strict';
// Local, pinned libsodium; never a CDN or a network request containing secrets.
importScripts('sodium.js');
self.onmessage = async ({data}) => {
  let password, key;
  try {
    await sodium.ready;
    password = sodium.from_string(data.password);
    key = sodium.crypto_pwhash(32, password, sodium.from_base64(data.salt, sodium.base64_variants.ORIGINAL),
      3, 64 * 1024 * 1024, sodium.crypto_pwhash_ALG_ARGON2ID13);
    self.postMessage({key: sodium.to_base64(key, sodium.base64_variants.ORIGINAL)});
  } catch (_) { self.postMessage({error: true}); }
  finally {
    if (password) sodium.memzero(password);
    if (key) sodium.memzero(key);
    self.close();
  }
};
