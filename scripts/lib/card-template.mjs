export const W = 800;
export const H = 300;

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

export function renderCard(stream, theme, mascotDataUri) {
  const palette = palettes[theme];
  if (!palette) throw new Error(`Unsupported card theme: ${theme}`);

  return box(
    {
      width: `${W}px`,
      height: `${H}px`,
      display: 'flex',
      position: 'relative',
      overflow: 'hidden',
      background: palette.background,
      border: `1px solid ${palette.border}`,
      borderRadius: '20px',
      color: palette.text,
      fontFamily: 'Inter',
    },
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
  );
}
