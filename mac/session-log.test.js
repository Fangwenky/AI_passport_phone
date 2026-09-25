import test from 'node:test';
import assert from 'node:assert/strict';
import {applyRecord} from './session-log.js';

test('log records show working then done without exposing full prompt as title', () => {
  const task = {id: 'x', project: 'Codex', status: 'idle'};
  applyRecord(task, {type: 'session_meta', payload: {id: 'abc', cwd: '/work/My App', source: 'vscode'}});
  applyRecord(task, {type: 'event_msg', timestamp: '2026-09-20T10:00:00Z', payload: {type: 'task_started'}});
  assert.equal(task.status, 'working');
  assert.equal(task.project, 'My App');
  applyRecord(task, {type: 'event_msg', timestamp: '2026-09-20T10:01:00Z', payload: {type: 'task_complete', last_agent_message: 'Finished'}});
  assert.equal(task.status, 'done');
  assert.equal(task.summary, 'Finished');
});

test('public agent messages enter the feed without tool output or reasoning', () => {
  const task = {id: 'x', status: 'working', updates: []};
  applyRecord(task, {type: 'event_msg', timestamp: '2026-09-20T10:00:00Z', payload: {type: 'item_completed', item: {type: 'Reasoning', summary_text: 'private'}}});
  applyRecord(task, {type: 'event_msg', timestamp: '2026-09-20T10:00:01Z', payload: {type: 'item_completed', item: {type: 'CommandExecution', stdout: 'secret'}}});
  applyRecord(task, {type: 'event_msg', timestamp: '2026-09-20T10:00:02Z', payload: {type: 'item_completed', item: {type: 'AgentMessage', phase: 'commentary', content: [{type: 'Text', text: '正在处理'}]}}});
  assert.deepEqual(task.updates.map(x => x.text), ['正在处理']);
});
