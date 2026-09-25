import test from 'node:test';
import assert from 'node:assert/strict';
import {builtInSchemes, defaultAppearance, normalizeAppearance, normalizeLibrary, normalizeScheme} from './appearance.js';

test('appearance accepts presets and validated custom colors', () => {
  assert.equal(normalizeAppearance({theme: 'ocean'}).colors.accent, '#1677FF');
  const custom = normalizeAppearance({...defaultAppearance, theme: 'custom', character: 'custom',
    colors: {...defaultAppearance.colors, accent: '#123abc'}, revision: 4});
  assert.equal(custom.colors.accent, '#123ABC');
  assert.equal(custom.character, 'custom');
  assert.throws(() => normalizeAppearance({...custom, colors: {...custom.colors, ink: 'blue'}}));
});

test('appearance library keeps built-ins and validated custom schemes', () => {
  const custom = normalizeScheme({id: 'custom-1', name: 'My sky', note: 'Soft blue',
    appearance: {...defaultAppearance, theme: 'custom'}});
  const library = normalizeLibrary({activeId: 'custom-1', schemes: [custom]});
  assert.equal(library.schemes.length, builtInSchemes.length + 1);
  assert.equal(library.activeId, 'custom-1');
  assert.equal(library.schemes.at(-1).appearance.schemeId, 'custom-1');
  assert.throws(() => normalizeScheme({...custom, id: '../bad'}));
});
