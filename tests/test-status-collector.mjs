import assert from 'node:assert/strict';
import { chmod, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { collectAllStatuses } from '../scripts/lib/status-collector.mjs';
import { imageInspectionAdapter, outputDirectory } from '../scripts/collect-release-status.mjs';

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

test('inspects public GHCR images with an explicit anonymous auth file', async (t) => {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'status-skopeo-'));
  const trace = path.join(directory, 'registry-auth-file');
  const skopeo = path.join(directory, 'skopeo');
  await writeFile(skopeo, `#!/bin/sh\nprintf '%s\\n' "$REGISTRY_AUTH_FILE" > "$TRACE_FILE"\ncat "$REGISTRY_AUTH_FILE" >> "$TRACE_FILE"\nprintf 'sha256:${'a'.repeat(64)}|2026-08-01T16:30:00Z|${revision}\\n'\n`);
  await chmod(skopeo, 0o755);
  const previousPath = process.env.PATH;
  const previousAuth = process.env.REGISTRY_AUTH_FILE;
  const previousTrace = process.env.TRACE_FILE;
  process.env.PATH = `${directory}:${previousPath}`;
  process.env.REGISTRY_AUTH_FILE = '/unreadable/inherited-auth.json';
  process.env.TRACE_FILE = trace;
  t.after(async () => {
    process.env.PATH = previousPath;
    if (previousAuth === undefined) delete process.env.REGISTRY_AUTH_FILE;
    else process.env.REGISTRY_AUTH_FILE = previousAuth;
    if (previousTrace === undefined) delete process.env.TRACE_FILE;
    else process.env.TRACE_FILE = previousTrace;
    await rm(directory, { recursive: true, force: true });
  });

  const image = await imageInspectionAdapter()('ghcr.io/joshyorko/dudley-os:stable');
  assert.equal(image.digest, digest);
  const [authFile, authJson] = (await readFile(trace, 'utf8')).split('\n', 2);
  assert.notEqual(authFile, '/unreadable/inherited-auth.json');
  assert.equal(authJson, '{"auths":{}}');
});

test('rejects an output directory that escapes an allowed root through a symlink', async (t) => {
  const outside = await mkdtemp(path.join(os.tmpdir(), 'status-outside-'));
  const link = path.join(root, 'status-output-escape');
  await symlink(outside, link);
  t.after(async () => {
    await rm(link, { force: true });
    await rm(outside, { recursive: true, force: true });
  });

  await assert.rejects(outputDirectory(link), /STATUS_OUTPUT_DIR must be inside/);
});
