import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import {
  buildStatusRecord,
  formatCardStatus,
  normalizeWorkflowRun,
  parseImageInspection,
  validateStatusRecord,
  validateStreamConfig,
} from '../scripts/lib/release-status.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const streams = JSON.parse(await readFile(path.join(root, 'cards/streams.json'), 'utf8'));
const digest = `sha256:${'a'.repeat(64)}`;
const revision = '9dea5f79a23d18691de954da7fdd7e502ba31e02';
const at = '2026-08-01T16:30:00Z';

function image(imageRef, overrides = {}) {
  return { imageRef, digest, at, revision, ...overrides };
}

function run(overrides = {}) {
  return { status: 'completed', conclusion: 'success', html_url: 'https://github.test/runs/10', ...overrides };
}

function dakotaFallback() {
  const complete = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: streams.dakota.status.imageRefs.map((imageRef) => image(imageRef)),
    checkedAt: '2026-08-01T16:35:00Z',
  });
  return buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: [image(streams.dakota.status.imageRefs[0])], previous: complete,
    checkedAt: '2026-08-02T16:35:00Z',
  });
}

test('rejects invalid stream and inspection configuration', () => {
  assert.throws(() => validateStreamConfig('stable', { ...streams.stable, status: { ...streams.stable.status, qualification: 'Certified' } }));
  assert.throws(() => validateStreamConfig('stable', { ...streams.stable, status: { ...streams.stable.status, workflowFile: 'build.yaml' } }));
  assert.throws(() => parseImageInspection('ghcr.io/joshyorko/dudley-os:stable', `sha256:${'z'.repeat(64)}|${at}|${revision}`));
  assert.throws(() => parseImageInspection('ghcr.io/joshyorko/dudley-os:stable', `${digest}|yesterday|${revision}`));
  assert.throws(() => parseImageInspection('docker.io/library/alpine:latest', `${digest}|${at}|${revision}`));
});

test('normalizes queued and in-progress workflows as running', () => {
  for (const status of ['queued', 'in_progress']) {
    assert.deepEqual(normalizeWorkflowRun(run({ status, conclusion: null })), {
      state: status,
      conclusion: null,
      runUrl: 'https://github.test/runs/10',
    });
    const record = buildStatusRecord({ name: 'stable', stream: streams.stable, run: run({ status, conclusion: null }), images: [image(streams.stable.imageRef)], checkedAt: '2026-08-01T16:35:00Z' });
    assert.equal(formatCardStatus(record).buildLabel, 'Running');
  }
});

test('formats every completed workflow conclusion as terminal', () => {
  const cases = [
    ['success', 'Passing', 'success'],
    ['failure', 'Failed', 'danger'],
    ['timed_out', 'Failed', 'danger'],
    ['action_required', 'Failed', 'danger'],
    ['startup_failure', 'Failed', 'danger'],
    ['stale', 'Failed', 'danger'],
    ['cancelled', 'Cancelled', 'warning'],
    ['neutral', 'Neutral', 'warning'],
    ['skipped', 'Skipped', 'warning'],
  ];
  for (const [conclusion, label, tone] of cases) {
    const record = buildStatusRecord({ name: 'stable', stream: streams.stable, run: run({ conclusion }), images: [image(streams.stable.imageRef)], checkedAt: '2026-08-01T16:35:00Z' });
    assert.equal(formatCardStatus(record).buildLabel, label);
    assert.equal(formatCardStatus(record).buildTone, tone);
  }
});

test('rejects unknown completed workflow conclusions', () => {
  assert.throws(() => normalizeWorkflowRun(run({ conclusion: 'mystery' })), /invalid workflow conclusion/);
  const record = buildStatusRecord({ name: 'stable', stream: streams.stable, run: run(), images: [image(streams.stable.imageRef)], checkedAt: '2026-08-01T16:35:00Z' });
  assert.throws(() => formatCardStatus({ ...record, build: { ...record.build, conclusion: 'mystery' } }), /invalid workflow conclusion/);
});

test('failed workflow retains the current successful image metadata', () => {
  const record = buildStatusRecord({
    name: 'stable',
    stream: streams.stable,
    run: { status: 'completed', conclusion: 'failure', html_url: 'https://github.test/runs/10' },
    images: [image('ghcr.io/joshyorko/dudley-os:stable')],
    previous: undefined,
    checkedAt: '2026-08-01T16:35:00Z',
  });

  assert.equal(record.build.conclusion, 'failure');
  assert.equal(record.published.digest, digest);
  assert.equal(formatCardStatus(record).buildLabel, 'Failed');
});

test('requires Dakota images to share a revision before publishing a complete pair', () => {
  const record = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: [image(streams.dakota.status.imageRefs[0]), image(streams.dakota.status.imageRefs[1], { revision: 'a'.repeat(40) })],
    checkedAt: '2026-08-01T16:35:00Z',
  });

  assert.equal(record.published.state, 'pair_incomplete');
  assert.equal(formatCardStatus(record).buildLabel, 'Pair incomplete');
});

test('uses the previous complete Dakota pair when the current pair is incomplete', () => {
  const previous = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: streams.dakota.status.imageRefs.map((imageRef) => image(imageRef)),
    checkedAt: '2026-08-01T16:35:00Z',
  });
  const record = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: [image(streams.dakota.status.imageRefs[0])], previous,
    checkedAt: '2026-08-02T16:35:00Z',
  });

  assert.equal(record.published.state, 'pair_incomplete');
  assert.deepEqual(record.published.images, previous.published.images);
  assert.equal(formatCardStatus(record).buildLabel, 'Pair incomplete');
});

test('preserves the last complete Dakota pair across repeated incomplete refreshes', () => {
  const complete = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: streams.dakota.status.imageRefs.map((imageRef) => image(imageRef)),
    checkedAt: '2026-08-01T16:35:00Z',
  });
  const firstIncomplete = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: [image(streams.dakota.status.imageRefs[0])], previous: complete,
    checkedAt: '2026-08-02T16:35:00Z',
  });
  const secondIncomplete = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(),
    images: [image(streams.dakota.status.imageRefs[1])], previous: firstIncomplete,
    checkedAt: '2026-08-03T16:35:00Z',
  });

  assert.equal(secondIncomplete.published.state, 'pair_incomplete');
  assert.equal(secondIncomplete.published.at, '2026-08-01T16:30:00Z');
  assert.equal(secondIncomplete.published.digest, digest);
  assert.equal(secondIncomplete.published.imageRef, 'ghcr.io/joshyorko/dudley-os:dakota');
  assert.deepEqual(secondIncomplete.published.images, complete.published.images);
});

for (const [name, mutate] of [
  ['one image', (published) => ({ ...published, images: [published.images[0]] })],
  ['extra image', (published) => ({ ...published, images: [...published.images, image('ghcr.io/joshyorko/dudley-os:nvidia')] })],
  ['mismatched revisions', (published) => ({ ...published, images: [published.images[0], { ...published.images[1], revision: 'b'.repeat(40) }] })],
  ['primary image reference', (published) => ({ ...published, imageRef: 'ghcr.io/joshyorko/dudley-os:dakota-nvidia' })],
  ['primary digest', (published) => ({ ...published, digest: `sha256:${'b'.repeat(64)}` })],
  ['primary timestamp', (published) => ({ ...published, at: '2026-08-01T16:31:00Z' })],
]) {
  test(`rejects incomplete-pair fallback with inconsistent ${name}`, () => {
    const fallback = dakotaFallback();
    assert.throws(
      () => validateStatusRecord({ ...fallback, published: mutate(fallback.published) }),
    );
  });
}

for (const [name, selectImages] of [
  ['wrong reference', ([primary]) => [primary, image('ghcr.io/joshyorko/dudley-os:nvidia')]],
  ['missing reference', ([primary]) => [primary]],
  ['extra reference', ([primary, secondary]) => [primary, secondary, image('ghcr.io/joshyorko/dudley-os:nvidia')]],
  ['reordered references', ([primary, secondary]) => [secondary, primary]],
]) {
  test(`rejects fallback with ${name}`, () => {
    const fallback = dakotaFallback();
    const images = selectImages(fallback.published.images);
    const previous = { ...fallback, published: { ...fallback.published, imageRef: images[0].imageRef, digest: images[0].digest, at: images[0].at, images } };
    assert.throws(() => buildStatusRecord({
      name: 'dakota', stream: streams.dakota, run: run(),
      images: [image(streams.dakota.status.imageRefs[0])], previous,
      checkedAt: '2026-08-03T16:35:00Z',
    }));
  });
}

test('marks a first incomplete Dakota pair as unpublished', () => {
  const record = buildStatusRecord({
    name: 'dakota', stream: streams.dakota, run: run(), images: [image(streams.dakota.status.imageRefs[0])],
    checkedAt: '2026-08-01T16:35:00Z',
  });

  assert.equal(record.published.at, null);
  assert.equal(record.published.digest, null);
  assert.equal(formatCardStatus(record).publishedLabel, 'Not published');
  assert.equal(formatCardStatus(record).digestLabel, '—');
});

test('formats the primary digest and validates the complete record contract', () => {
  const record = buildStatusRecord({ name: 'stable', stream: streams.stable, run: run(), images: [image(streams.stable.imageRef)], checkedAt: '2026-08-01T16:35:00Z' });
  assert.equal(formatCardStatus(record).digestLabel, 'aaaaaaaa');
  assert.deepEqual(validateStatusRecord(record), record);
});

test('rejects a missing configured image', () => {
  assert.throws(() => buildStatusRecord({
    name: 'stable', stream: streams.stable, run: run(), images: [], checkedAt: '2026-08-01T16:35:00Z',
  }), /missing configured image/);
});
