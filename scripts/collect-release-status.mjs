import { execFileSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { collectAllStatuses } from './lib/status-collector.mjs';
import { parseImageInspection, validateStatusRecord } from './lib/release-status.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const required = ['GITHUB_TOKEN', 'GITHUB_REPOSITORY', 'GITHUB_REF_NAME', 'STATUS_OUTPUT_DIR'];

function requireEnvironment(environment) {
  for (const name of required) {
    if (!environment[name]) throw new Error(`${name} is required`);
  }
}

function outputDirectory(directory) {
  const resolved = path.resolve(directory);
  if (resolved !== '/tmp' && !resolved.startsWith('/tmp/') && resolved !== root && !resolved.startsWith(`${root}/`)) {
    throw new Error('STATUS_OUTPUT_DIR must be inside the repository root or /tmp');
  }
  return resolved;
}

function githubRunAdapter({ token, repository, branch }) {
  return async (workflowFile) => {
    const url = new URL(`https://api.github.com/repos/${repository}/actions/workflows/${workflowFile}/runs`);
    url.search = new URLSearchParams({ branch, per_page: '1' });
    const response = await fetch(url, { headers: {
      Authorization: `Bearer ${token}`,
      Accept: 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    } });
    if (!response.ok) throw new Error(`GitHub workflow lookup failed: ${response.status}`);
    const body = await response.json();
    if (!Array.isArray(body.workflow_runs) || body.workflow_runs.length === 0) throw new Error(`GitHub workflow has no runs: ${workflowFile}`);
    return body.workflow_runs[0];
  };
}

function imageInspectionAdapter() {
  return async (imageRef) => {
    const output = execFileSync('skopeo', [
      'inspect', '--no-tags', '--format', '{{.Digest}}|{{index .Labels "org.opencontainers.image.created"}}|{{index .Labels "org.opencontainers.image.revision"}}',
      `docker://${imageRef}`,
    ], { encoding: 'utf8' });
    return parseImageInspection(imageRef, output.trim());
  };
}

function fallbackAdapter(baseUrl) {
  if (!baseUrl) return async () => undefined;
  return async (name) => {
    const response = await fetch(`${baseUrl.replace(/\/$/, '')}/${name}.json`);
    if (response.status === 404) return undefined;
    if (!response.ok) throw new Error(`Status fallback lookup failed: ${response.status}`);
    return validateStatusRecord(await response.json());
  };
}

async function main(environment = process.env) {
  requireEnvironment(environment);
  const directory = outputDirectory(environment.STATUS_OUTPUT_DIR);
  const streams = await import('../cards/streams.json', { with: { type: 'json' } });
  const records = await collectAllStatuses({
    streams: streams.default,
    getWorkflowRun: githubRunAdapter({ token: environment.GITHUB_TOKEN, repository: environment.GITHUB_REPOSITORY, branch: environment.GITHUB_REF_NAME }),
    inspectImage: imageInspectionAdapter(),
    getPreviousStatus: fallbackAdapter(environment.STATUS_FALLBACK_BASE_URL),
    now: () => new Date(),
  });
  await mkdir(directory, { recursive: true });
  await Promise.all(Object.entries(records).map(([name, record]) => writeFile(path.join(directory, `${name}.json`), `${JSON.stringify(record, null, 2)}\n`)));
}

await main();
