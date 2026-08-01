import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, rm, symlink, unlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { validatePagesOutput } from '../scripts/validate-pages-output.mjs';

const repositoryRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const streams = ['stable', 'nvidia', 'dakota'];
const themes = ['light', 'dark'];
const validPng = PNG.sync.write(new PNG({ width: 1600, height: 760 }));
const wrongSizePng = PNG.sync.write(new PNG({ width: 800, height: 380 }));
const changedPngImage = new PNG({ width: 1600, height: 760 });
changedPngImage.data[0] = 255;
const changedPng = PNG.sync.write(changedPngImage);
const records = Object.fromEntries(await Promise.all(streams.map(async (stream) => [
  stream,
  await readFile(path.join(repositoryRoot, 'tests/fixtures/status', `${stream}.json`)),
])));

async function writeStatuses(directory) {
  await mkdir(directory, { recursive: true });
  await Promise.all(streams.map((stream) => writeFile(path.join(directory, `${stream}.json`), records[stream])));
}

function validCardHashes() {
  const pngHash = createHash('sha256').update(validPng).digest('hex');
  return Object.fromEntries(streams.map((stream, index) => [stream, {
    input: String(index + 1).repeat(64),
    light: pngHash,
    dark: pngHash,
  }]));
}

async function writeCardHashes(root, hashes = validCardHashes()) {
  await writeFile(path.join(root, 'cards', 'card-hashes.json'), `${JSON.stringify(hashes)}\n`);
}

async function createArtifact(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'dudley-pages-output-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'cards'));
  await writeStatuses(path.join(root, 'status'));
  await Promise.all(streams.flatMap((stream) => themes.map((theme) => (
    writeFile(path.join(root, 'cards', `${stream}-${theme}.png`), validPng)
  ))));
  await writeCardHashes(root);
  return root;
}

test('accepts exactly six card images and three matching status records', async (t) => {
  const root = await createArtifact(t);

  await assert.doesNotReject(validatePagesOutput(root));
});

test('rejects a missing card image', async (t) => {
  const root = await createArtifact(t);
  await unlink(path.join(root, 'cards', 'stable-light.png'));

  await assert.rejects(validatePagesOutput(root), /Missing card image: stable-light\.png/);
});

test('rejects a missing status record', async (t) => {
  const root = await createArtifact(t);
  await unlink(path.join(root, 'status', 'nvidia.json'));

  await assert.rejects(validatePagesOutput(root), /Missing status record: nvidia\.json/);
});

test('rejects a status record whose stream differs from its filename', async (t) => {
  const root = await createArtifact(t);
  const stable = JSON.parse(records.stable);
  stable.stream = 'nvidia';
  await writeFile(path.join(root, 'status', 'stable.json'), `${JSON.stringify(stable)}\n`);

  await assert.rejects(validatePagesOutput(root), /Status stream mismatch for stable/);
});

test('rejects a card image with the wrong dimensions', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'cards', 'dakota-dark.png'), wrongSizePng);

  await assert.rejects(validatePagesOutput(root), /dakota-dark\.png must be 1600x760/);
});

test('rejects an unexpected stream status record', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'status', 'preview.json'), records.stable);

  await assert.rejects(validatePagesOutput(root), /Unexpected status record: preview\.json/);
});

test('rejects a required file symlink even when its target stays inside the artifact', async (t) => {
  const root = await createArtifact(t);
  const linkedCard = path.join(root, 'cards', 'stable-light.png');
  await unlink(linkedCard);
  await symlink('stable-dark.png', linkedCard);

  await assert.rejects(validatePagesOutput(root), /Symlinks are not allowed: cards\/stable-light\.png/);
});

test('rejects an artifact directory symlink that escapes the supplied root', async (t) => {
  const root = await createArtifact(t);
  const outside = await mkdtemp('/var/tmp/dudley-pages-status-');
  t.after(() => rm(outside, { recursive: true, force: true }));
  await writeStatuses(outside);
  await rm(path.join(root, 'status'), { recursive: true });
  await symlink(outside, path.join(root, 'status'), 'dir');

  await assert.rejects(validatePagesOutput(root), /Symlinks are not allowed: status/);
});

test('rejects a symlink supplied as the artifact root', async (t) => {
  const root = await createArtifact(t);
  const parent = await mkdtemp(path.join(os.tmpdir(), 'dudley-pages-root-link-'));
  const link = path.join(parent, 'public');
  t.after(() => rm(parent, { recursive: true, force: true }));
  await symlink(root, link, 'dir');

  await assert.rejects(validatePagesOutput(link), /Artifact root must not be a symlink/);
});

test('rejects a missing renderer hash manifest', async (t) => {
  const root = await createArtifact(t);
  await unlink(path.join(root, 'cards', 'card-hashes.json'));

  await assert.rejects(validatePagesOutput(root), /Missing card image: card-hashes\.json/);
});

test('rejects malformed renderer hash JSON', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'cards', 'card-hashes.json'), '{');

  await assert.rejects(validatePagesOutput(root), /Invalid card hash manifest JSON/);
});

test('rejects an empty renderer hash manifest', async (t) => {
  const root = await createArtifact(t);
  await writeCardHashes(root, {});

  await assert.rejects(validatePagesOutput(root), /card hash manifest streams/);
});

test('rejects a missing renderer hash stream', async (t) => {
  const root = await createArtifact(t);
  const hashes = validCardHashes();
  delete hashes.nvidia;
  await writeCardHashes(root, hashes);

  await assert.rejects(validatePagesOutput(root), /card hash manifest streams/);
});

test('rejects an extra renderer hash stream', async (t) => {
  const root = await createArtifact(t);
  const hashes = validCardHashes();
  hashes.preview = hashes.stable;
  await writeCardHashes(root, hashes);

  await assert.rejects(validatePagesOutput(root), /card hash manifest streams/);
});

test('rejects a missing renderer hash field', async (t) => {
  const root = await createArtifact(t);
  const hashes = validCardHashes();
  delete hashes.dakota.dark;
  await writeCardHashes(root, hashes);

  await assert.rejects(validatePagesOutput(root), /dakota card hash fields/);
});

test('rejects an extra renderer hash field', async (t) => {
  const root = await createArtifact(t);
  const hashes = validCardHashes();
  hashes.stable.preview = 'a'.repeat(64);
  await writeCardHashes(root, hashes);

  await assert.rejects(validatePagesOutput(root), /stable card hash fields/);
});

test('rejects a renderer hash that is not lowercase 64-hex', async (t) => {
  const root = await createArtifact(t);
  const hashes = validCardHashes();
  hashes.nvidia.input = 'A'.repeat(64);
  await writeCardHashes(root, hashes);

  await assert.rejects(validatePagesOutput(root), /nvidia\.input must be lowercase 64-hex/);
});

test('rejects a PNG whose digest differs from the renderer hash manifest', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'cards', 'stable-light.png'), changedPng);

  await assert.rejects(validatePagesOutput(root), /stable-light\.png digest does not match/);
});

test('rejects an unexpected card image', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'cards', 'preview-light.png'), validPng);

  await assert.rejects(validatePagesOutput(root), /Unexpected card image: preview-light\.png/);
});
