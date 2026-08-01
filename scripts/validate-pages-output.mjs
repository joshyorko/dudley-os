import { lstat, readFile, readdir, realpath } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { validateStatusRecord } from './lib/release-status.mjs';

const streams = ['stable', 'nvidia', 'dakota'];
const themes = ['light', 'dark'];
const cardNames = streams.flatMap((stream) => themes.map((theme) => `${stream}-${theme}.png`));
const statusNames = streams.map((stream) => `${stream}.json`);

function isInside(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${path.sep}`);
}

async function validatePath(root, candidate, displayName, kind) {
  const metadata = await lstat(candidate);
  if (metadata.isSymbolicLink()) throw new Error(`Symlinks are not allowed: ${displayName}`);
  if (kind === 'directory' ? !metadata.isDirectory() : !metadata.isFile()) {
    throw new Error(`${displayName} must be a ${kind}`);
  }
  const actual = await realpath(candidate);
  if (!isInside(root, actual)) throw new Error(`Artifact path resolves outside its root: ${displayName}`);
  return actual;
}

function validateEntries(actual, expected, label) {
  const expectedSet = new Set(expected);
  for (const name of actual) {
    if (!expectedSet.has(name)) throw new Error(`Unexpected ${label}: ${name}`);
  }
  for (const name of expected) {
    if (!actual.includes(name)) throw new Error(`Missing ${label}: ${name}`);
  }
}

export async function validatePagesOutput(artifactRoot) {
  if (typeof artifactRoot !== 'string' || artifactRoot.length === 0) throw new TypeError('Artifact root is required');
  const resolvedRoot = path.resolve(artifactRoot);
  const rootMetadata = await lstat(resolvedRoot);
  if (rootMetadata.isSymbolicLink()) throw new Error('Artifact root must not be a symlink');
  if (!rootMetadata.isDirectory()) throw new Error('Artifact root must be a directory');
  const root = await realpath(resolvedRoot);

  const rootEntries = (await readdir(root)).sort();
  validateEntries(rootEntries, ['cards', 'status'], 'artifact entry');

  const cardsDirectory = await validatePath(root, path.join(root, 'cards'), 'cards', 'directory');
  const statusDirectory = await validatePath(root, path.join(root, 'status'), 'status', 'directory');
  const cardEntries = (await readdir(cardsDirectory)).sort();
  const hasHashSidecar = cardEntries.includes('card-hashes.json');
  validateEntries(cardEntries, hasHashSidecar ? [...cardNames, 'card-hashes.json'] : cardNames, 'card image');
  const statusEntries = (await readdir(statusDirectory)).sort();
  validateEntries(statusEntries, statusNames, 'status record');

  await Promise.all(cardNames.map(async (name) => {
    const filename = await validatePath(root, path.join(cardsDirectory, name), `cards/${name}`, 'file');
    const image = PNG.sync.read(await readFile(filename));
    if (image.width !== 1600 || image.height !== 760) throw new Error(`${name} must be 1600x760`);
  }));
  if (hasHashSidecar) {
    await validatePath(root, path.join(cardsDirectory, 'card-hashes.json'), 'cards/card-hashes.json', 'file');
  }

  await Promise.all(streams.map(async (stream) => {
    const name = `${stream}.json`;
    const filename = await validatePath(root, path.join(statusDirectory, name), `status/${name}`, 'file');
    const record = validateStatusRecord(JSON.parse(await readFile(filename, 'utf8')));
    if (record.stream !== stream) throw new Error(`Status stream mismatch for ${stream}`);
  }));
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const [artifactRoot, ...extra] = process.argv.slice(2);
  if (!artifactRoot || extra.length > 0) throw new Error('Usage: node scripts/validate-pages-output.mjs <artifact-root>');
  await validatePagesOutput(artifactRoot);
}
