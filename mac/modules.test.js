import test from 'node:test';
import assert from 'node:assert/strict';
import {defaultModules, moduleCatalog, normalizeModules} from './modules.js';

test('module settings preserve selected entries and profile text while rejecting unknown modules', () => {
  const saved = normalizeModules({...defaultModules, enabled: ['profile'],
    profile: {...defaultModules.profile, name: '小明', bio: '设计师\n开发者'}});
  assert.deepEqual(saved.enabled, ['profile']);
  assert.equal(saved.profile.bio, '设计师\n开发者');
  assert.throws(() => normalizeModules({...defaultModules, enabled: ['shell']}));
  assert.throws(() => normalizeModules({...defaultModules, profile: {...defaultModules.profile, bio: 'x'.repeat(4001)}}));
});

test('module catalog uses unique settings IDs accepted by module settings', () => {
  assert.deepEqual(moduleCatalog.map(module => module.id), ['codex', 'profile']);
  assert.equal(new Set(moduleCatalog.map(module => module.id)).size, moduleCatalog.length);
  assert.ok(moduleCatalog.every(module => module.name && module.summary && module.settings && module.features.length));
  assert.doesNotThrow(() => normalizeModules({...defaultModules, enabled: moduleCatalog.map(module => module.id)}));
});
