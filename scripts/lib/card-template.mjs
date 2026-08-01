export const W = 800;
export const ART_H = 300;
export const STATUS_H = 80;
export const H = ART_H + STATUS_H;

const palettes = {
  light: {
    background: '#f7f8f8',
    border: '#d9e0e2',
    text: '#172126',
    muted: '#526168',
    subtle: '#e9edef',
    role: '#5d6c72',
  },
  dark: {
    background: '#172126',
    border: '#34434a',
    text: '#f1f5f5',
    muted: '#c2cbce',
    subtle: '#26343a',
    role: '#b7c4c8',
  },
};

const box = (style, children) => ({ type: 'div', props: { style, children } });
const label = (style, children) => ({ type: 'div', props: { style, children } });

function telemetryCell(name, value, color, last = false) {
  return box(
    {
      display: 'flex', flexDirection: 'column', justifyContent: 'center', width: '197px',
      padding: '0 18px', borderRight: last ? 'none' : '1px solid #34434a',
    },
    [
      label({ fontSize: '11px', fontWeight: 700, letterSpacing: '1.3px', color: '#91a0a6' }, name),
      label({ fontSize: '13px', fontWeight: 700, color: color ?? '#f1f5f5', marginTop: '7px' }, value),
    ],
  );
}

const toneColors = {
  success: '#7ddc94',
  danger: '#ff8a8a',
  warning: '#f1c75b',
};

export function renderCard(stream, theme, mascotDataUri, status) {
  const palette = palettes[theme];
  if (!palette) throw new Error(`Unsupported card theme: ${theme}`);

  return box(
    {
      width: `${W}px`,
      height: `${H}px`,
      display: 'flex',
      flexDirection: 'column',
      position: 'relative',
      overflow: 'hidden',
      background: palette.background,
      border: `1px solid ${palette.border}`,
      borderRadius: '20px',
      color: palette.text,
      fontFamily: 'Inter',
    },
    [
      box(
        { display: 'flex', width: '100%', height: `${ART_H}px`, flexShrink: 0 },
        [
          box({ width: '12px', height: '100%', background: stream.accent }),
          box(
            { display: 'flex', flexDirection: 'column', padding: '30px 30px 26px 32px', width: '565px' },
            [
              label({ fontSize: '12px', fontWeight: 700, letterSpacing: '1.8px', color: palette.role }, 'DUDLEY OS STREAM'),
              label({ fontSize: '34px', fontWeight: 700, lineHeight: 1.1, marginTop: '12px' }, stream.title),
              label({ fontSize: '17px', lineHeight: 1.35, color: palette.muted, marginTop: '8px' }, stream.description),
              box({ display: 'flex', alignItems: 'center', marginTop: '22px' }, [
                label({ display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, minWidth: '72px', height: '30px', background: stream.accent, color: '#ffffff', borderRadius: '999px', padding: '0 12px', fontSize: '13px', fontWeight: 700 }, stream.tag),
                label({ color: palette.muted, fontSize: '13px', marginLeft: '12px' }, 'bootc image'),
              ]),
              label({ fontSize: '13px', color: palette.text, background: palette.subtle, borderRadius: '8px', padding: '10px 12px', marginTop: '18px' }, stream.imageRef),
            ],
          ),
          box(
            { display: 'flex', width: '211px', alignItems: 'center', justifyContent: 'center', padding: '20px 20px 20px 0' },
            { type: 'img', props: { src: mascotDataUri, width: 210, height: 210, style: { objectFit: 'contain' } } },
          ),
        ],
      ),
      box(
        { display: 'flex', width: '100%', height: `${STATUS_H}px`, background: '#10191d', color: '#f1f5f5', paddingLeft: '12px' },
        [
          telemetryCell('BUILD', status.buildLabel, toneColors[status.buildTone]),
          telemetryCell('PUBLISHED', status.publishedLabel),
          telemetryCell('DIGEST', status.digestLabel),
          telemetryCell('QUALIFICATION', status.qualificationLabel, undefined, true),
        ],
        ),
    ],
  );
}
