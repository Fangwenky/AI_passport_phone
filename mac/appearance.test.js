import test from 'node:test';
import assert from 'node:assert/strict';
import {defaultAppearance, normalizeAppearance} from './appearance.js';

test('appearance accepts presets and validated custom colors', () => {
  assert.equal(normalizeAppearance({theme: 'ocean'}).colors.accent, '#1677FF');
  const custom = normalizeAppearance({...defaultAppearance, theme: 'custom', character: 'custom',
    colors: {...defaultAppearance.colors, accent: '#123abc'}, revision: 4});
  assert.equal(custom.colors.accent, '#123ABC');
  assert.equal(custom.character, 'custom');
  assert.throws(() => normalizeAppearance({...custom, colors: {...custom.colors, ink: 'blue'}}));
});
