import { webcrypto } from "node:crypto";

const pair=await webcrypto.subtle.generateKey({name:"ECDSA",namedCurve:"P-256"},true,["sign","verify"]);
const privateJwk=await webcrypto.subtle.exportKey("jwk",pair.privateKey);
const publicJwk=await webcrypto.subtle.exportKey("jwk",pair.publicKey);

console.log("PRIVATE_JWK_SECRET (simpan hanya di Supabase Secret):");
console.log(JSON.stringify(privateJwk));
console.log("\nPUBLIC_JWK (tempel ke js/license-config.js):");
console.log(JSON.stringify(publicJwk,null,2));
