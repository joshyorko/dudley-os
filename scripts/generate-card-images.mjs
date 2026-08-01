import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Resvg } from '@resvg/resvg-js';
import satori from 'satori';
import { renderCard, W, H } from './lib/card-template.mjs';
import { formatCardStatus, validateStatusRecord } from './lib/release-status.mjs';

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

function parseArguments(args) {
  const options = { check: false, statusDirectory: null, outputDirectory: cardDirectory };
  for (let index = 0; index < args.length; index += 1) {
    const flag = args[index];
    if (flag === '--check') options.check = true;
    else if (flag === '--status-dir' || flag === '--output-dir') {
      const value = args[++index];
      if (!value || value.startsWith('--')) throw new Error(`Missing value for ${flag}`);
      if (flag === '--status-dir') options.statusDirectory = resolve(root, value);
      else options.outputDirectory = resolve(root, value);
    } else throw new Error(`Unknown argument: ${flag}`);
  }
  const allowedOutput = options.outputDirectory === root
    || options.outputDirectory.startsWith(`${root}/`)
    || options.outputDirectory === '/tmp'
    || options.outputDirectory.startsWith('/tmp/');
  if (!allowedOutput) throw new Error(`Output directory must be inside ${root} or /tmp`);
  if (options.check && options.outputDirectory !== cardDirectory) throw new Error('--check cannot be combined with --output-dir');
  return options;
}

function loadStatuses(streams, statusDirectory) {
  if (!statusDirectory) {
    return Object.fromEntries(Object.entries(streams).map(([name, stream]) => [name, {
      buildLabel: 'Unavailable', buildTone: 'warning', publishedLabel: 'Not published', digestLabel: '—',
      qualificationLabel: stream.status.qualification,
    }]));
  }
  return Object.fromEntries(Object.keys(streams).map((name) => {
    const filename = join(statusDirectory, `${name}.json`);
    if (!existsSync(filename)) throw new Error(`Missing status file: ${filename}`);
    const record = validateStatusRecord(JSON.parse(readFileSync(filename, 'utf8')));
    if (record.stream !== name) throw new Error(`Status stream mismatch for ${name}`);
    return [name, formatCardStatus(record)];
  }));
}

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

async function buildCards(streams, statuses) {
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
    const inputHash = hash(JSON.stringify(canonicalize(stream)), JSON.stringify(canonicalize(statuses[name])), mascot, ...commonHashInputs);
    const mascotDataUri = `data:image/png;base64,${mascot.toString('base64')}`;
    cardHashes[name] = { input: inputHash };

    for (const theme of themes) {
      const svg = await satori(renderCard(stream, theme, mascotDataUri, statuses[name]), {
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
  const options = parseArguments(process.argv.slice(2));
  const streams = loadStreams();
  const statuses = loadStatuses(streams, options.statusDirectory);
  const outputDirectory = options.check ? mkdtempSync(join(tmpdir(), 'dudley-cards-')) : options.outputDirectory;
  try {
    const generated = await buildCards(streams, statuses);
    if (options.check) {
      await writeGenerated(outputDirectory, generated);
      await checkGenerated(outputDirectory, generated);
    }
    else await writeGenerated(outputDirectory, generated);
  } finally {
    if (options.check) rmSync(outputDirectory, { recursive: true, force: true });
  }
}

await main();
