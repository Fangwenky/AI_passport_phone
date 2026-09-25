const ids = new Set(['codex', 'profile']);
const fields = {name: 80, headline: 120, bio: 4000, website: 200, email: 160, contact: 200};

export const defaultModules = {
  enabled: ['codex', 'profile'],
  profile: {name: '', headline: '', bio: '', website: '', email: '', contact: ''}
};

export function normalizeModules(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value) || !Array.isArray(value.enabled))
    throw new Error('Invalid modules');
  const enabled = [];
  for (const id of value.enabled) {
    if (!ids.has(id) || enabled.includes(id)) throw new Error('Unknown or duplicate module');
    enabled.push(id);
  }
  const source = value.profile;
  if (!source || typeof source !== 'object' || Array.isArray(source)) throw new Error('Invalid profile');
  const profile = {};
  for (const [field, limit] of Object.entries(fields)) {
    const text = source[field] ?? '';
    if (typeof text !== 'string' || text.length > limit) throw new Error(`Invalid profile ${field}`);
    profile[field] = text;
  }
  return {enabled, profile};
}
