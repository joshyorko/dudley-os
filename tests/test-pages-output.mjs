import assert from 'node:assert/strict';
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
const records = Object.fromEntries(await Promise.all(streams.map(async (stream) => [
  stream,
  await readFile(path.join(repositoryRoot, 'tests/fixtures/status', `${stream}.json`)),
])));

async function writeStatuses(directory) {
  await mkdir(directory, { recursive: true });
  await Promise.all(streams.map((stream) => writeFile(path.join(directory, `${stream}.json`), records[stream])));
}

async function createArtifact(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'dudley-pages-output-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(path.join(root, 'cards'));
  await writeStatuses(path.join(root, 'status'));
  await Promise.all(streams.flatMap((stream) => themes.map((theme) => (
    writeFile(path.join(root, 'cards', `${stream}-${theme}.png`), validPng)
  ))));
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

test('accepts the renderer hash sidecar but rejects an unexpected card image', async (t) => {
  const root = await createArtifact(t);
  await writeFile(path.join(root, 'cards', 'card-hashes.json'), '{}\n');
  await assert.doesNotReject(validatePagesOutput(root));
  await writeFile(path.join(root, 'cards', 'preview-light.png'), validPng);

  await assert.rejects(validatePagesOutput(root), /Unexpected card image: preview-light\.png/);
});
