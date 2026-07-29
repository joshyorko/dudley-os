import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { PNG } from 'pngjs';
import { renderCard } from '../scripts/lib/card-template.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const streams = JSON.parse(await readFile(path.join(root, 'cards/streams.json'), 'utf8'));
const hashes = JSON.parse(await readFile(path.join(root, 'static/img/cards/card-hashes.json'), 'utf8'));
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
      'accent', 'description', 'imageRef', 'mascot', 'switchCommand', 'tag', 'title',
    ]);
    assert.equal(streams[key].imageRef, expectedStream.imageRef);
    assert.equal(streams[key].tag, expectedStream.tag);
    assert.equal(streams[key].switchCommand, expectedStream.switchCommand);
  }
});

test('README publishes every stream switch command and card theme', async () => {
  const readme = await readFile(path.join(root, 'README.md'), 'utf8');
  for (const [name, stream] of Object.entries(expected)) {
    assert.ok(readme.includes(stream.switchCommand), `README omits ${name} switch command`);
    for (const theme of ['light', 'dark']) {
      assert.ok(readme.includes(`static/img/cards/${name}-${theme}.png`), `README omits ${name} ${theme} card`);
    }
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
  for (const stream of Object.values(streams)) {
    const pill = elementWithText(renderCard(stream, 'dark', 'data:image/png;base64,AA=='), stream.tag);
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

test('generated cards are present at the requested dimensions', async () => {
  for (const name of Object.keys(streams)) {
    for (const theme of ['light', 'dark']) {
      const image = await decode(`static/img/cards/${name}-${theme}.png`);
      assert.equal(image.width, 1600);
      assert.equal(image.height, 600);
    }
  }
  assert.deepEqual(Object.keys(hashes).sort(), ['dakota', 'nvidia', 'stable']);
});
