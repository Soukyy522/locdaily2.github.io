import { webcrypto } from "node:crypto";

const pair = await webcrypto.subtle.generateKey(
  { name: "ECDSA", namedCurve: "P-256" },
  true,
  ["sign", "verify"],
);
const privateJwk = await webcrypto.subtle.exportKey("jwk", pair.privateKey);
const publicJwk = await webcrypto.subtle.exportKey("jwk", pair.publicKey);

console.log("PRIVATE JWK - simpan hanya sebagai secret Edge Function:");
console.log(JSON.stringify(privateJwk));
console.log("\nPUBLIC JWK - salin ke js/license-config.js:");
console.log(JSON.stringify(publicJwk, null, 2));
