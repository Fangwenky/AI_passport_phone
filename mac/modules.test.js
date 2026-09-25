import test from 'node:test';
import assert from 'node:assert/strict';
import {defaultModules, normalizeModules} from './modules.js';

test('module settings preserve selected entries and profile text while rejecting unknown modules', () => {
  const saved = normalizeModules({...defaultModules, enabled: ['profile'],
    profile: {...defaultModules.profile, name: '小明', bio: '设计师\n开发者'}});
  assert.deepEqual(saved.enabled, ['profile']);
  assert.equal(saved.profile.bio, '设计师\n开发者');
  assert.throws(() => normalizeModules({...defaultModules, enabled: ['shell']}));
  assert.throws(() => normalizeModules({...defaultModules, profile: {...defaultModules.profile, bio: 'x'.repeat(4001)}}));
});
