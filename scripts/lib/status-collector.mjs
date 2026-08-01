import { buildStatusRecord } from './release-status.mjs';

function checkedAt(now) {
  return now().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export async function collectAllStatuses({ streams, getWorkflowRun, inspectImage, getPreviousStatus, now }) {
  const records = {};
  for (const [name, stream] of Object.entries(streams)) {
    const run = await getWorkflowRun(stream.status.workflowFile);
    const images = [];
    for (const imageRef of stream.status.imageRefs) images.push(await inspectImage(imageRef));
    const previous = getPreviousStatus ? await getPreviousStatus(name) : undefined;
    records[name] = buildStatusRecord({ name, stream, run, images, previous, checkedAt: checkedAt(now) });
  }
  return records;
}
