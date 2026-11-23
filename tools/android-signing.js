#!/usr/bin/env node
const fs = require('node:fs');

for (const name of [
  'ANDROID_KEYSTORE_PATH',
  'ANDROID_KEYSTORE_BASE64',
  'ANDROID_KEYSTORE_PASSWORD',
  'ANDROID_KEY_ALIAS',
  'ANDROID_KEY_PASSWORD',
]) {
  if (!process.env[name]) throw new Error(`Missing ${name}`);
}

const encoded = process.env.ANDROID_KEYSTORE_BASE64.replace(/\s/g, '');
const keystore = Buffer.from(encoded, 'base64');
if (keystore.length === 0 || keystore.toString('base64') !== encoded) {
  throw new Error('ANDROID_KEYSTORE_BASE64 must contain a base64-encoded keystore');
}
fs.writeFileSync(process.env.ANDROID_KEYSTORE_PATH, keystore, { mode: 0o600, flag: 'wx' });
