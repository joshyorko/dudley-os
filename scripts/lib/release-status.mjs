const DIGEST = /^sha256:[0-9a-f]{64}$/;
const REVISION = /^[0-9a-f]{40}$/;
const IMAGE_REF = /^ghcr\.io\/joshyorko\/dudley-os:[a-z0-9][a-z0-9-]*$/;
const WORKFLOW_FILE = /^[a-z0-9][a-z0-9-]*\.yml$/;
const TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const QUALIFICATIONS = new Set(['Daily driver', 'Experimental']);
const COMPLETED_CONCLUSIONS = new Set([
  'success',
  'failure',
  'timed_out',
  'action_required',
  'startup_failure',
  'stale',
  'cancelled',
  'neutral',
  'skipped',
]);
const FAILURE_CONCLUSIONS = new Set(['failure', 'timed_out', 'action_required', 'startup_failure', 'stale']);
const DATE_FORMAT = new Intl.DateTimeFormat('en-US', {
  month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC',
});

function assert(condition, message) {
  if (!condition) throw new TypeError(message);
}

function validTimestamp(value) {
  return typeof value === 'string' && TIMESTAMP.test(value) && !Number.isNaN(Date.parse(value));
}

function validateImage(image) {
  assert(image && typeof image === 'object', 'image metadata is required');
  assert(IMAGE_REF.test(image.imageRef), 'invalid image reference');
  assert(DIGEST.test(image.digest), 'invalid image digest');
  assert(validTimestamp(image.at), 'invalid image timestamp');
  assert(REVISION.test(image.revision), 'invalid image revision');
}

export function validateStreamConfig(name, stream) {
  assert(typeof name === 'string' && name.length > 0, 'invalid stream name');
  assert(stream && typeof stream === 'object' && stream.status, 'stream status configuration is required');
  const { qualification, workflowFile, imageRefs } = stream.status;
  assert(QUALIFICATIONS.has(qualification), 'invalid qualification');
  assert(typeof workflowFile === 'string' && WORKFLOW_FILE.test(workflowFile), 'invalid workflow filename');
  assert(Array.isArray(imageRefs) && imageRefs.length > 0 && imageRefs.every((imageRef) => IMAGE_REF.test(imageRef)), 'invalid image reference');
  assert(new Set(imageRefs).size === imageRefs.length, 'image references must be unique');
  return stream;
}

export function normalizeWorkflowRun(run) {
  assert(run && typeof run === 'object', 'workflow run is required');
  assert(['queued', 'in_progress', 'completed'].includes(run.status), 'invalid workflow state');
  assert(typeof run.html_url === 'string' && run.html_url.length > 0, 'invalid workflow run URL');
  if (run.status === 'completed') assert(COMPLETED_CONCLUSIONS.has(run.conclusion), 'invalid workflow conclusion');
  return { state: run.status, conclusion: run.conclusion ?? null, runUrl: run.html_url };
}

export function parseImageInspection(imageRef, line) {
  assert(typeof line === 'string', 'inspection output is required');
  const [digest, at, revision, ...extra] = line.trim().split('|');
  assert(extra.length === 0, 'invalid inspection output');
  const image = { imageRef, digest, at, revision };
  validateImage(image);
  return image;
}

function completePublication(images) {
  const primary = images[0];
  return {
    state: 'complete',
    at: primary.at,
    digest: primary.digest,
    imageRef: primary.imageRef,
    images,
  };
}

function incompletePublication(imageRef, previous) {
  if (
    ['complete', 'pair_incomplete'].includes(previous?.published?.state)
    && previous.published.at !== null
    && previous.published.digest !== null
    && previous.published.images.length > 0
  ) {
    return { ...previous.published, state: 'pair_incomplete' };
  }
  return { state: 'pair_incomplete', at: null, digest: null, imageRef, images: [] };
}

export function buildStatusRecord({ name, stream, run, images, previous, checkedAt }) {
  validateStreamConfig(name, stream);
  assert(Array.isArray(images), 'images are required');
  images.forEach(validateImage);
  if (previous !== undefined) validateStatusRecord(previous);
  assert(validTimestamp(checkedAt), 'invalid checked timestamp');
  const build = normalizeWorkflowRun(run);
  const { imageRefs } = stream.status;
  const imageByRef = new Map(images.map((image) => [image.imageRef, image]));
  const configuredImages = imageRefs.map((imageRef) => imageByRef.get(imageRef)).filter(Boolean);
  const isPair = imageRefs.length === 2;
  if (!isPair) assert(configuredImages.length === 1, 'missing configured image');
  const completePair = !isPair || (
    configuredImages.length === 2
    && configuredImages[0].revision === configuredImages[1].revision
  );
  const published = completePair
    ? completePublication(configuredImages)
    : incompletePublication(imageRefs[0], previous);
  const record = {
    schemaVersion: 1,
    stream: name,
    build,
    published,
    qualification: stream.status.qualification,
    checkedAt,
  };
  return validateStatusRecord(record);
}

export function validateStatusRecord(record) {
  assert(record && typeof record === 'object', 'status record is required');
  assert(record.schemaVersion === 1, 'invalid schema version');
  assert(typeof record.stream === 'string' && record.stream.length > 0, 'invalid stream');
  assert(record.build && ['queued', 'in_progress', 'completed'].includes(record.build.state), 'invalid build state');
  if (record.build.state === 'completed') {
    assert(COMPLETED_CONCLUSIONS.has(record.build.conclusion), 'invalid workflow conclusion');
  } else {
    assert(record.build.conclusion === null, 'unfinished workflow cannot have a conclusion');
  }
  assert(typeof record.build.runUrl === 'string' && record.build.runUrl.length > 0, 'invalid build run URL');
  assert(record.published && ['complete', 'pair_incomplete'].includes(record.published.state), 'invalid publication state');
  assert(QUALIFICATIONS.has(record.qualification), 'invalid qualification');
  assert(validTimestamp(record.checkedAt), 'invalid checked timestamp');
  if (record.published.state === 'complete') {
    assert(validTimestamp(record.published.at), 'invalid published timestamp');
    assert(DIGEST.test(record.published.digest), 'invalid published digest');
    assert(IMAGE_REF.test(record.published.imageRef), 'invalid published image reference');
    assert(Array.isArray(record.published.images) && record.published.images.length > 0, 'published images are required');
    record.published.images.forEach(validateImage);
  } else {
    assert(record.published.at === null || validTimestamp(record.published.at), 'invalid incomplete published timestamp');
    assert(record.published.digest === null || DIGEST.test(record.published.digest), 'invalid incomplete published digest');
    assert(IMAGE_REF.test(record.published.imageRef), 'invalid incomplete image reference');
    assert(Array.isArray(record.published.images), 'invalid incomplete images');
    record.published.images.forEach(validateImage);
  }
  return record;
}

export function formatCardStatus(record) {
  validateStatusRecord(record);
  const pairIncomplete = record.published.state === 'pair_incomplete';
  let label = 'Running';
  let tone = 'warning';
  if (pairIncomplete) {
    label = 'Pair incomplete';
  } else if (record.build.conclusion === 'success') {
    label = 'Passing';
    tone = 'success';
  } else if (FAILURE_CONCLUSIONS.has(record.build.conclusion)) {
    label = 'Failed';
    tone = 'danger';
  } else if (record.build.conclusion === 'cancelled') {
    label = 'Cancelled';
  } else if (record.build.conclusion === 'neutral') {
    label = 'Neutral';
  } else if (record.build.conclusion === 'skipped') {
    label = 'Skipped';
  }
  return {
    buildLabel: label,
    buildTone: tone,
    publishedLabel: record.published.at ? DATE_FORMAT.format(new Date(record.published.at)) : 'Not published',
    digestLabel: record.published.digest ? record.published.digest.slice('sha256:'.length, 'sha256:'.length + 8) : '—',
    qualificationLabel: record.qualification,
  };
}
