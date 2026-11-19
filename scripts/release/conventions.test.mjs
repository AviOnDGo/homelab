import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { analyzeCommits } from '@semantic-release/commit-analyzer';
import config from '../../release.config.mjs';
import { isValidTitle } from './conventions.mjs';

const analyze = (...messages) => analyzeCommits(config.plugins[0][1], {
  cwd: process.cwd(),
  commits: messages.map((message) => ({ message })),
  logger: { log() {} },
});

test('accepted titles and the real analyzer agree on every classification', async () => {
  const expected = {
    feat: 'minor', fix: 'patch', perf: 'patch', revert: 'patch', docs: null,
    style: null, refactor: null, test: null, build: null, ci: null, chore: null,
  };
  for (const [type, release] of Object.entries(expected)) {
    const title = `${type}(service/sub-system): describe change`;
    const breaking = `${type}!: describe breaking change`;
    assert.ok(isValidTitle(title), title);
    assert.ok(isValidTitle(breaking), breaking);
    assert.equal(await analyze(title), release, title);
    assert.equal(await analyze(breaking), 'major', breaking);
  }
});

test('malformed titles are rejected and shell metacharacters stay data', () => {
  for (const title of [
    'Add a feature', 'unknown: description', 'fix(): invalid', 'fix(scope):',
    'fix: ', 'fix: \t', 'fix!:missing space', 'fix(scope!): invalid', 'fix: text\n',
  ]) {
    assert.equal(isValidTitle(title), false, JSON.stringify(title));
  }
  const checker = fileURLToPath(new URL('./check-title.mjs', import.meta.url));
  for (const [title, status] of [['$(exit 0)', 1], ['fix: $(exit 1)', 0]]) {
    assert.equal(spawnSync(process.execPath, [checker], {
      env: { ...process.env, PR_TITLE: title },
    }).status, status);
  }
});

test('breaking footers, mixed ranges and no-release ranges', async () => {
  assert.equal(await analyze('fix: fix it', 'feat: add it', 'chore: clean it'), 'minor');
  assert.equal(await analyze('docs: revise restore\n\nBREAKING CHANGE: migrate data', 'feat: add it'), 'major');
  assert.equal(await analyze('chore: clean up\n\nBREAKING CHANGE: migrate data'), 'major');
  assert.equal(await analyze('docs: explain it', 'chore: clean up', 'Old squash message'), null);
});
