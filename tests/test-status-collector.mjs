import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { collectAllStatuses } from '../scripts/lib/status-collector.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const streams = JSON.parse(await readFile(path.join(root, 'cards/streams.json'), 'utf8'));
const digest = `sha256:${'a'.repeat(64)}`;
const revision = '9dea5f79a23d18691de954da7fdd7e502ba31e02';
const at = '2026-08-01T16:30:00Z';

function workflowRun(workflowFile) {
  return { status: 'completed', conclusion: 'success', html_url: `https://github.test/${workflowFile}` };
}

function inspection(imageRef) {
  return { imageRef, digest, at, revision };
}

test('collects every configured workflow and image in stream order', async () => {
  const workflowFiles = [];
  const imageRefs = [];
  const records = await collectAllStatuses({
    streams,
    getWorkflowRun: async (workflowFile) => {
      workflowFiles.push(workflowFile);
      return workflowRun(workflowFile);
    },
    inspectImage: async (imageRef) => {
      imageRefs.push(imageRef);
      return inspection(imageRef);
    },
    getPreviousStatus: async () => undefined,
    now: () => new Date('2026-08-01T16:35:00Z'),
  });

  assert.deepEqual(Object.keys(records).sort(), ['dakota', 'nvidia', 'stable']);
  assert.deepEqual(workflowFiles, ['build.yml', 'build-nvidia.yml', 'build-dakota.yml']);
  assert.deepEqual(imageRefs, [
    'ghcr.io/joshyorko/dudley-os:stable',
    'ghcr.io/joshyorko/dudley-os:nvidia',
    'ghcr.io/joshyorko/dudley-os:dakota',
    'ghcr.io/joshyorko/dudley-os:dakota-nvidia',
  ]);
  assert.equal(records.dakota.published.images.length, 2);
});

test('rejects the collection when a workflow adapter fails', async () => {
  await assert.rejects(
    collectAllStatuses({
      streams,
      getWorkflowRun: async () => { throw new Error('GitHub unavailable'); },
      inspectImage: async (imageRef) => inspection(imageRef),
      getPreviousStatus: async () => undefined,
      now: () => new Date('2026-08-01T16:35:00Z'),
    }),
    /GitHub unavailable/,
  );
});

test('rejects the collection when an image adapter fails', async () => {
  await assert.rejects(
    collectAllStatuses({
      streams,
      getWorkflowRun: async (workflowFile) => workflowRun(workflowFile),
      inspectImage: async () => { throw new Error('skopeo unavailable'); },
      getPreviousStatus: async () => undefined,
      now: () => new Date('2026-08-01T16:35:00Z'),
    }),
    /skopeo unavailable/,
  );
});
