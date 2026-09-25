const hex = /^#[0-9A-Fa-f]{6}$/;
const schemeId = /^[a-z0-9][a-z0-9-]{0,63}$/;

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

export const defaultAppearance = {
  schemeId: 'ocean', theme: 'ocean', character: 'default', colors: presets.ocean, revision: 0
};

export const builtInSchemes = [
  {id: 'ocean', name: '蓝鲸航线', note: '深海蓝 · 发光青', builtIn: true, appearance: defaultAppearance},
  {id: 'midnight', name: '午夜莓果', note: '柔和夜色 · 暖金星点', builtIn: true,
    appearance: {schemeId: 'midnight', theme: 'midnight', character: 'default', colors: presets.midnight, revision: 0}}
];

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
  const fallback = theme === 'custom' ? 'custom' : theme;
  const id = schemeId.test(value.schemeId || '') ? value.schemeId : fallback;
  return {schemeId: id, theme, character, colors, revision};
}

export function normalizeScheme(value) {
  if (!value || typeof value !== 'object') throw new Error('Invalid scheme');
  if (!schemeId.test(value.id || '')) throw new Error('Invalid scheme id');
  const name = String(value.name || '').trim().slice(0, 40);
  const note = String(value.note || '').trim().slice(0, 80);
  if (!name) throw new Error('Scheme name is required');
  const appearance = normalizeAppearance({...value.appearance, schemeId: value.id});
  return {id: value.id, name, note, builtIn: Boolean(value.builtIn), appearance};
}

export function normalizeLibrary(value) {
  const custom = Array.isArray(value?.schemes) ? value.schemes
    .map(item => { try { return normalizeScheme(item); } catch { return null; } })
    .filter(item => item && !item.builtIn && !builtInSchemes.some(preset => preset.id === item.id)) : [];
  const schemes = [...builtInSchemes.map(normalizeScheme), ...custom];
  const activeId = schemes.some(item => item.id === value?.activeId) ? value.activeId : 'ocean';
  return {activeId, schemes};
}
