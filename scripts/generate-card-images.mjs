import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';
import satori from 'satori';
import { renderCard, W, H } from './lib/card-template.mjs';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const cardDirectory = join(root, 'static/img/cards');
const manifestPath = join(root, 'cards/streams.json');
const generatorPath = fileURLToPath(import.meta.url);
const templatePath = join(root, 'scripts/lib/card-template.mjs');
const fontDirectory = join(root, 'node_modules/@fontsource/inter/files');
const fonts = [
  { name: 'Inter', data: readFileSync(join(fontDirectory, 'inter-latin-400-normal.woff')), weight: 400, style: 'normal' },
  { name: 'Inter', data: readFileSync(join(fontDirectory, 'inter-latin-700-normal.woff')), weight: 700, style: 'normal' },
];
const themes = ['light', 'dark'];
const requiredFields = ['title', 'description', 'imageRef', 'tag', 'accent', 'mascot', 'switchCommand'];

function canonicalize(value) {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, canonicalize(value[key])]));
  }
  return value;
}

function hash(...values) {
  const digest = createHash('sha256');
  for (const value of values) digest.update(value);
  return digest.digest('hex');
}

function loadStreams() {
  const streams = JSON.parse(readFileSync(manifestPath, 'utf8'));
  const names = Object.keys(streams).sort();
  if (names.join(',') !== 'dakota,nvidia,stable') throw new Error(`Unexpected stream keys: ${names.join(', ')}`);

  for (const [name, stream] of Object.entries(streams)) {
    for (const field of requiredFields) {
      if (typeof stream[field] !== 'string' || stream[field].length === 0) {
        throw new Error(`${name} is missing required ${field}`);
      }
    }
    if (!/^#[0-9a-f]{6}$/i.test(stream.accent)) throw new Error(`${name} has invalid accent: ${stream.accent}`);
    const mascotPath = resolve(root, stream.mascot);
    if (!mascotPath.startsWith(`${root}/`) || !existsSync(mascotPath)) {
      throw new Error(`${name} mascot is missing: ${stream.mascot}`);
    }
  }
  return streams;
}

async function buildCards(streams) {
  const commonHashInputs = [
    readFileSync(join(fontDirectory, 'inter-latin-400-normal.woff')),
    readFileSync(join(fontDirectory, 'inter-latin-700-normal.woff')),
    readFileSync(generatorPath),
    readFileSync(templatePath),
  ];
  const output = new Map();
  const cardHashes = {};

  for (const name of Object.keys(streams).sort()) {
    const stream = streams[name];
    const mascot = readFileSync(resolve(root, stream.mascot));
    const inputHash = hash(JSON.stringify(canonicalize(stream)), mascot, ...commonHashInputs);
    const mascotDataUri = `data:image/png;base64,${mascot.toString('base64')}`;
    cardHashes[name] = { input: inputHash };

    for (const theme of themes) {
      const svg = await satori(renderCard(stream, theme, mascotDataUri), {
        width: W,
        height: H,
        fonts,
      });
      const png = new Resvg(svg, {
        fitTo: { mode: 'zoom', value: 2 },
        font: { loadSystemFonts: false },
      }).render().asPng();
      const filename = `${name}-${theme}.png`;
      output.set(filename, png);
      cardHashes[name][theme] = hash(png);
    }
  }
  output.set('card-hashes.json', Buffer.from(`${JSON.stringify(cardHashes, null, 2)}\n`));
  return output;
}

async function writeGenerated(outputDirectory, generated) {
  await mkdir(outputDirectory, { recursive: true });
  await Promise.all([...generated].map(([filename, contents]) => writeFile(join(outputDirectory, filename), contents)));
}

async function checkGenerated(generatedDirectory, generated) {
  const stale = [];
  for (const [filename] of generated) {
    const generatedPath = join(generatedDirectory, filename);
    const destination = join(cardDirectory, filename);
    if (!existsSync(destination) || !(await readFile(generatedPath)).equals(await readFile(destination))) {
      stale.push(`static/img/cards/${filename}`);
    }
  }
  if (stale.length) {
    console.error(`Stale or missing card assets:\n${stale.map((item) => `- ${item}`).join('\n')}`);
    process.exitCode = 1;
  }
}

async function main() {
  const streams = loadStreams();
  const check = process.argv.slice(2).join(' ') === '--check';
  const outputDirectory = check ? mkdtempSync(join(tmpdir(), 'dudley-cards-')) : cardDirectory;
  try {
    const generated = await buildCards(streams);
    if (check) {
      await writeGenerated(outputDirectory, generated);
      await checkGenerated(outputDirectory, generated);
    }
    else await writeGenerated(outputDirectory, generated);
  } finally {
    if (check) rmSync(outputDirectory, { recursive: true, force: true });
  }
}

await main();
