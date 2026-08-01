import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { access, mkdtemp, readFile, rm, symlink } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { promisify } from 'node:util';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { renderCard } from '../scripts/lib/card-template.mjs';
import { formatCardStatus } from '../scripts/lib/release-status.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const execFileAsync = promisify(execFile);
const streams = JSON.parse(await readFile(path.join(root, 'cards/streams.json'), 'utf8'));
const hashes = JSON.parse(await readFile(path.join(root, 'static/img/cards/card-hashes.json'), 'utf8'));
const statuses = Object.fromEntries(await Promise.all(['stable', 'nvidia', 'dakota'].map(async (name) => [
  name, JSON.parse(await readFile(path.join(root, 'tests/fixtures/status', `${name}.json`), 'utf8')),
])));
const expected = {
  stable: {
    imageRef: 'ghcr.io/joshyorko/dudley-os:stable',
    tag: 'stable',
    switchCommand: 'sudo bootc switch ghcr.io/joshyorko/dudley-os:stable --enforce-container-sigpolicy',
  },
  nvidia: {
    imageRef: 'ghcr.io/joshyorko/dudley-os:nvidia',
    tag: 'nvidia',
    switchCommand: 'sudo bootc switch ghcr.io/joshyorko/dudley-os:nvidia --enforce-container-sigpolicy',
  },
  dakota: {
    imageRef: 'ghcr.io/joshyorko/dudley-os:dakota',
    tag: 'dakota',
    switchCommand: 'sudo bootc switch ghcr.io/joshyorko/dudley-os:dakota --enforce-container-sigpolicy',
  },
};

async function decode(relativePath) {
  return PNG.sync.read(await readFile(path.join(root, relativePath)));
}

function nonRailBackgroundPixels(image, { left, top, width, height }) {
  let pixels = 0;
  for (let y = top; y < top + height; y += 1) {
    for (let x = left; x < left + width; x += 1) {
      const offset = (y * image.width + x) * 4;
      if (image.data[offset] !== 16 || image.data[offset + 1] !== 25 || image.data[offset + 2] !== 29) pixels += 1;
    }
  }
  return pixels;
}

function elementWithText(element, text) {
  if (!element || typeof element !== 'object') return undefined;
  if (element.props?.children === text) return element;
  const children = element.props?.children;
  for (const child of Array.isArray(children) ? children : [children]) {
    const match = elementWithText(child, text);
    if (match) return match;
  }
  return undefined;
}

test('stream manifest has the approved public streams', () => {
  assert.deepEqual(Object.keys(streams).sort(), ['dakota', 'nvidia', 'stable']);
  for (const [key, expectedStream] of Object.entries(expected)) {
    assert.deepEqual(Object.keys(streams[key]).sort(), [
      'accent', 'description', 'imageRef', 'mascot', 'status', 'switchCommand', 'tag', 'title',
    ]);
    assert.equal(streams[key].imageRef, expectedStream.imageRef);
    assert.equal(streams[key].tag, expectedStream.tag);
    assert.equal(streams[key].switchCommand, expectedStream.switchCommand);
  }
  assert.deepEqual(streams.stable.status, {
    qualification: 'Daily driver', workflowFile: 'build.yml', imageRefs: ['ghcr.io/joshyorko/dudley-os:stable'],
  });
  assert.deepEqual(streams.nvidia.status, {
    qualification: 'Daily driver', workflowFile: 'build-nvidia.yml', imageRefs: ['ghcr.io/joshyorko/dudley-os:nvidia'],
  });
  assert.deepEqual(streams.dakota.status, {
    qualification: 'Experimental', workflowFile: 'build-dakota.yml', imageRefs: [
      'ghcr.io/joshyorko/dudley-os:dakota', 'ghcr.io/joshyorko/dudley-os:dakota-nvidia',
    ],
  });
});

test('README publishes every stream as a linked live card', async () => {
  const readme = await readFile(path.join(root, 'README.md'), 'utf8');
  const liveCards = {
    stable: 'build.yml',
    nvidia: 'build-nvidia.yml',
    dakota: 'build-dakota.yml',
  };
  for (const [name, stream] of Object.entries(expected)) {
    assert.ok(readme.includes(stream.switchCommand), `README omits ${name} switch command`);
    for (const theme of ['light', 'dark']) {
      assert.ok(
        readme.includes(`https://joshyorko.github.io/dudley-os/cards/${name}-${theme}.png`),
        `README omits ${name} ${theme} live card`,
      );
    }
    assert.ok(
      readme.includes(`https://github.com/joshyorko/dudley-os/actions/workflows/${liveCards[name]}`),
      `README omits ${name} card workflow link`,
    );
  }
});

test('character PNGs are transparent RGBA assets', async () => {
  for (const stream of Object.values(streams)) {
    const image = await decode(stream.mascot);
    assert.ok(image.width > 0 && image.height > 0);
    assert.equal(image.colorType, 6);
    for (const [x, y] of [[0, 0], [image.width - 1, 0], [0, image.height - 1], [image.width - 1, image.height - 1]]) {
      assert.equal(image.data[(image.width * y + x) * 4 + 3], 0, `${stream.mascot} corner ${x},${y} is opaque`);
    }
  }
});

test('stream tag pills use an explicit non-clipping Satori layout', () => {
  for (const [name, stream] of Object.entries(streams)) {
    const pill = elementWithText(renderCard(stream, 'dark', 'data:image/png;base64,AA==', formatCardStatus(statuses[name])), stream.tag);
    assert.ok(pill, `missing ${stream.tag} tag pill`);
    assert.deepEqual(pill.props.style, {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      flexShrink: 0,
      minWidth: '72px',
      height: '30px',
      background: stream.accent,
      color: '#ffffff',
      borderRadius: '999px',
      padding: '0 12px',
      fontSize: '13px',
      fontWeight: 700,
    });
  }
});

test('rendered cards retain the art body and append formatted telemetry', () => {
  for (const [name, stream] of Object.entries(streams)) {
    const card = renderCard(stream, 'dark', 'data:image/png;base64,AA==', formatCardStatus(statuses[name]));
    for (const text of [stream.title, stream.description, stream.tag, stream.imageRef]) {
      assert.ok(elementWithText(card, text), `${name} card omits ${text}`);
    }
    assert.ok(JSON.stringify(card).includes('data:image/png;base64,AA=='), `${name} card omits mascot`);
    for (const label of ['BUILD', 'PUBLISHED', 'DIGEST', 'QUALIFICATION']) {
      assert.ok(elementWithText(card, label), `${name} card omits ${label}`);
    }
  }
  assert.ok(elementWithText(renderCard(streams.nvidia, 'light', 'data:image/png;base64,AA==', formatCardStatus(statuses.nvidia)), 'Failed'));
  assert.ok(elementWithText(renderCard(streams.stable, 'light', 'data:image/png;base64,AA==', formatCardStatus(statuses.stable)), 'Daily driver'));
});

test('generated cards are present at the requested dimensions', async () => {
  for (const name of Object.keys(streams)) {
    for (const theme of ['light', 'dark']) {
      const image = await decode(`static/img/cards/${name}-${theme}.png`);
      assert.equal(image.width, 1600);
      assert.equal(image.height, 760);
    }
  }
  assert.deepEqual(Object.keys(hashes).sort(), ['dakota', 'nvidia', 'stable']);
});

test('generated card rasters contain a label and value in every telemetry cell', async () => {
  for (const name of Object.keys(streams)) {
    for (const theme of ['light', 'dark']) {
      const image = await decode(`static/img/cards/${name}-${theme}.png`);
      for (let cell = 0; cell < 4; cell += 1) {
        const left = 40 + cell * 394;
        const labelPixels = nonRailBackgroundPixels(image, { left, top: 630, width: 340, height: 50 });
        const valuePixels = nonRailBackgroundPixels(image, { left, top: 680, width: 340, height: 50 });
        assert.ok(labelPixels > 400, `${name}-${theme} cell ${cell + 1} omits its rasterized label`);
        assert.ok(valuePixels > 80, `${name}-${theme} cell ${cell + 1} omits its rasterized value`);
      }
    }
  }
});

test('generator accepts live status and output directories and rejects unsafe arguments', async () => {
  const outputDirectory = await mkdtemp('/tmp/dudley-card-test-');
  const fallbackDirectory = await mkdtemp('/tmp/dudley-card-fallback-test-');
  try {
    await execFileAsync(process.execPath, ['scripts/generate-card-images.mjs', '--status-dir', 'tests/fixtures/status', '--output-dir', outputDirectory], { cwd: root });
    await execFileAsync(process.execPath, ['scripts/generate-card-images.mjs', '--output-dir', fallbackDirectory], { cwd: root });
    const image = PNG.sync.read(await readFile(path.join(outputDirectory, 'stable-light.png')));
    assert.deepEqual([image.width, image.height], [1600, 760]);
    const liveHashes = JSON.parse(await readFile(path.join(outputDirectory, 'card-hashes.json'), 'utf8'));
    const fallbackHashes = JSON.parse(await readFile(path.join(fallbackDirectory, 'card-hashes.json'), 'utf8'));
    assert.notEqual(liveHashes.stable.input, fallbackHashes.stable.input);
    for (const args of [
      ['--wat'],
      ['--status-dir'],
      ['--output-dir', '/var/dudley-cards'],
      ['--status-dir', path.join(outputDirectory, 'missing')],
    ]) {
      await assert.rejects(execFileAsync(process.execPath, ['scripts/generate-card-images.mjs', ...args], { cwd: root }));
    }
  } finally {
    await rm(outputDirectory, { recursive: true, force: true });
    await rm(fallbackDirectory, { recursive: true, force: true });
  }
});

test('generator rejects an output symlink that escapes the approved roots', async () => {
  const linkParent = await mkdtemp('/tmp/dudley-card-link-test-');
  const outsideDirectory = await mkdtemp('/var/tmp/dudley-card-outside-test-');
  const outputLink = path.join(linkParent, 'escape');
  try {
    await symlink(outsideDirectory, outputLink, 'dir');
    await assert.rejects(
      execFileAsync(process.execPath, ['scripts/generate-card-images.mjs', '--output-dir', outputLink], { cwd: root }),
      /outside the repository or \/tmp/,
    );
  } finally {
    await rm(linkParent, { recursive: true, force: true });
    await rm(outsideDirectory, { recursive: true, force: true });
  }
});

test('README is operator-first and credits its upstream foundation', async () => {
  const readme = await readFile(path.join(root, 'README.md'), 'utf8');
  const headings = readme.match(/^#{1,2} .+$/gm);
  assert.deepEqual(headings, [
    '# dudley-os',
    '## Choose a stream',
    '## Daily operation',
    '## What Dudley adds',
    '## Architecture',
    '## Build, trust, and release',
    '## Local verification',
    '## Repository map',
    '## Upstream and supporting projects',
  ]);

  for (const upstreamLink of [
    'https://projectbluefin.io',
    'https://docs.projectbluefin.io',
    'https://github.com/projectbluefin/actions',
    'https://universal-blue.org',
    'https://containers.github.io/bootc/',
  ]) {
    assert.ok(readme.includes(upstreamLink), `README omits ${upstreamLink}`);
  }

  for (const required of [
    'Dakota is experimental.',
    'still requires boot, update, and rollback qualification',
    'CI SBOM publication is disabled.',
    'bootc status',
    'sudo bootc upgrade',
    'sudo bootc rollback --apply',
  ]) {
    assert.ok(readme.includes(required), `README omits ${required}`);
  }

  for (const removed of [
    'Create Your Repository',
    'Rename the Project',
    "Love Your Image? Let's Go to Production",
    'Adding Image Rechunking',
  ]) {
    assert.ok(!readme.includes(removed), `README retains stale section: ${removed}`);
  }

  for (const supportDoc of [
    'docs/operations.md',
    'docs/maintenance.md',
    'docs/history/dudleys-second-bedroom-migration.md',
  ]) {
    assert.ok(readme.includes(`](${supportDoc})`), `README omits linked support document: ${supportDoc}`);
    await access(path.join(root, supportDoc));
  }
});
