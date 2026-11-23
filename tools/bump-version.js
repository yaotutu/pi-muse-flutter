#!/usr/bin/env node
const fs = require('node:fs');

const file = 'pubspec.yaml';
const [mode] = process.argv.slice(2);
if (process.argv.length > 3 || ![undefined, '--current', '--check'].includes(mode)) {
  throw new Error('Usage: node tools/bump-version.js [--current|--check]');
}

const text = fs.readFileSync(file, 'utf8');
const versionLines = [...text.matchAll(/^version[ \t]*:[^\r\n]*/gm)];
const versionLine = versionLines[0];
const component = '(0|[1-9][0-9]{0,8})';
const pattern = new RegExp(`^version:[ \\t]*${component}\\.${component}\\.${component}\\+([1-9][0-9]{0,9})[ \\t]*$`);
const match = versionLine && pattern.exec(versionLine[0]);
if (versionLines.length !== 1 || !match) {
  throw new Error('pubspec.yaml must contain one version in the format x.y.z+n');
}

const [, major, minor, patchText, codeText] = match;
const increment = mode === '--current' ? 0 : 1;
const patch = Number(patchText) + increment;
const code = Number(codeText) + increment;
if (patch > 999_999_999 || code > 2_100_000_000) {
  throw new Error('Android release version exceeds the supported range');
}
const version = `${major}.${minor}.${patch}`;
if (!mode) {
  const end = versionLine.index + versionLine[0].length;
  fs.writeFileSync(file, `${text.slice(0, versionLine.index)}version: ${version}+${code}${text.slice(end)}`);
}
process.stdout.write(`version=${version}\nversionCode=${code}\n`);
