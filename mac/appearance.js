const hex = /^#[0-9A-Fa-f]{6}$/;

export const presets = {
  ocean: {
    backgroundStart: '#061B3A', backgroundEnd: '#0B4D80', surface: '#EAF7FF',
    ink: '#08233F', muted: '#527895', accent: '#1677FF', line: '#A9DDF5'
  },
  midnight: {
    backgroundStart: '#171925', backgroundEnd: '#403042', surface: '#282536',
    ink: '#FFEDE5', muted: '#CCB3B3', accent: '#E9A895', line: '#64505F'
  }
};

export const defaultAppearance = {theme: 'ocean', character: 'default', colors: presets.ocean, revision: 0};

export function normalizeAppearance(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid appearance');
  const theme = ['ocean', 'midnight', 'custom'].includes(value.theme) ? value.theme : 'ocean';
  const character = value.character === 'custom' ? 'custom' : 'default';
  const source = theme === 'custom' ? value.colors : presets[theme];
  if (!source || typeof source !== 'object') throw new Error('Missing colors');
  const colors = {};
  for (const key of Object.keys(presets.ocean)) {
    if (!hex.test(source[key] || '')) throw new Error(`Invalid color ${key}`);
    colors[key] = source[key].toUpperCase();
  }
  const revision = Number.isSafeInteger(value.revision) && value.revision >= 0 ? value.revision : 0;
  return {theme, character, colors, revision};
}
