import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const root = path.join(os.homedir(), '.codex', 'sessions');
const text = value => typeof value === 'string' ? value : '';

export function listRecentLogs(now = new Date()) {
  const files = [];
  for (let offset = 0; offset < 3; offset++) {
    const day = new Date(now.getTime() - offset * 86400000);
    const dir = path.join(root, String(day.getFullYear()), String(day.getMonth() + 1).padStart(2, '0'), String(day.getDate()).padStart(2, '0'));
    try {
      for (const entry of fs.readdirSync(dir)) if (entry.endsWith('.jsonl')) files.push(path.join(dir, entry));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }
  return files;
}

export function applyRecord(task, record) {
  const p = record?.payload || {};
  const timestamp = Date.parse(record?.timestamp || '') || Date.now();
  if (record?.type === 'session_meta') {
    task.id = p.id || p.session_id || task.id;
    task.project = path.basename(p.cwd || '') || 'Codex';
    task.source = p.source || 'unknown';
  }
  if (record?.type === 'event_msg') {
    if (p.type === 'task_started') {
      task.status = 'working';
      task.startedAt = timestamp;
      task.updatedAt = timestamp;
    } else if (p.type === 'task_complete') {
      task.status = 'done';
      task.updatedAt = timestamp;
      task.summary = text(p.last_agent_message).slice(0, 280);
    } else if (p.type === 'task_failed') {
      task.status = 'failed';
      task.updatedAt = timestamp;
    } else if (p.type === 'item_completed' && p.item?.type === 'AgentMessage' && ['commentary', 'final'].includes(p.item.phase)) {
      const message = (p.item.content || []).map(x => text(x.text)).join('\n').trim();
      if (message) {
        task.updates ||= [];
        task.updates.push({at: timestamp, phase: p.item.phase, text: message.slice(0, 600)});
        task.updates = task.updates.slice(-8);
        task.updatedAt = timestamp;
      }
    }
  }
  if (record?.type === 'response_item' && p.type === 'message' && p.role === 'assistant') {
    const content = Array.isArray(p.content) ? p.content : [];
    const message = content.map(x => text(x.text)).join(' ').trim();
    if (message) task.summary = message.slice(0, 280);
    if (message) task.updatedAt = timestamp;
  }
  return task;
}

export class SessionLog {
  constructor() { this.files = new Map(); }
  snapshot() {
    for (const file of listRecentLogs()) {
      let stat;
      try { stat = fs.statSync(file); } catch { continue; }
      const previous = this.files.get(file);
      if (previous && previous.size === stat.size) continue;
      // Reparse only changed files; JSONL is append-only in normal Codex use.
      const task = {id: path.basename(file, '.jsonl'), project: 'Codex', source: 'unknown', status: 'idle', updatedAt: stat.mtimeMs, summary: '', updates: []};
      try {
        const lines = fs.readFileSync(file, 'utf8').split('\n');
        for (const line of lines) {
          if (!line) continue;
          try { applyRecord(task, JSON.parse(line)); } catch { /* writer may be mid-line */ }
        }
      } catch { continue; }
      task.updatedAt = Math.max(task.updatedAt, stat.mtimeMs);
      this.files.set(file, {size: stat.size, task});
    }
    return [...this.files.values()].map(x => x.task).sort((a,b) => b.updatedAt - a.updatedAt).slice(0, 15);
  }
}
