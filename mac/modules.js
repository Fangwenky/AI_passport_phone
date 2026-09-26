const fields = {name: 80, headline: 120, bio: 4000, website: 200, email: 160, contact: 200};

// This catalog is the shared module registry. Desktop managers and the phone use
// the same IDs and presentation metadata; each native client only implements the
// settings or renderer that belongs to that ID.
export const moduleCatalog = [
  {
    id: 'codex', name: 'Codex 工作流', shortName: 'Codex 监看', category: '工作',
    summary: '实时查看任务进度，并通过确认后的语音命令创建或继续任务。',
    icon: 'waveform.path', phoneIcon: '◉', settings: 'codex',
    features: ['实时任务流', '语音命令', '断线状态']
  },
  {
    id: 'profile', name: '个人名片', shortName: '个人名片', category: '展示',
    summary: '在手机上展示自我介绍、个人网站和联系方式。',
    icon: 'person.crop.rectangle', phoneIcon: '✦', settings: 'profile',
    features: ['个人简介', '联系方式', '全屏展示']
  }
];
const ids = new Set(moduleCatalog.map(module => module.id));

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
