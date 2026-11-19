import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

const script = (name) => fileURLToPath(new URL(name, import.meta.url));

function fixture(t) {
  const cwd = mkdtempSync(join(tmpdir(), 'homelab-release-test-'));
  t.after(() => rmSync(cwd, { recursive: true, force: true }));
  const bare = join(cwd, 'remote.git');
  const env = {
    ...process.env,
    GIT_AUTHOR_NAME: 'Release Test',
    GIT_AUTHOR_EMAIL: 'test@example.invalid',
    GIT_COMMITTER_NAME: 'Release Test',
    GIT_COMMITTER_EMAIL: 'test@example.invalid',
    GIT_CONFIG_NOSYSTEM: '1',
    GIT_CONFIG_GLOBAL: '/dev/null',
    GIT_ALLOW_PROTOCOL: 'file',
    GITHUB_ACTIONS: 'true',
    GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/main',
    GITHUB_SERVER_URL: 'https://github.com',
    GITHUB_REPOSITORY: 'example/homelab',
    GITHUB_OUTPUT: join(cwd, 'output'),
    PUBLISHED_TAGS: '',
    PATH: `${cwd}:${process.env.PATH}`,
  };
  const git = (...args) => execFileSync('git', args, { cwd, env, encoding: 'utf8' }).trim();
  git('init', '--quiet', '--initial-branch=main');
  git('init', '--quiet', '--bare', bare);
  git('remote', 'add', 'origin', bare);
  writeFileSync(join(cwd, 'gh'), '#!/bin/sh\nprintf "%s\\n" "$PUBLISHED_TAGS"\n', { mode: 0o700 });
  const tree = execFileSync('git', ['mktree'], { cwd, env, input: '', encoding: 'utf8' }).trim();
  let head;
  const commit = (subject) => {
    head = git('commit-tree', tree, ...(head ? ['-p', head] : []), '-m', subject);
    git('update-ref', 'refs/heads/main', head);
    env.GITHUB_SHA = head;
    return head;
  };
  const baseline = commit('Historical setup');
  env.RELEASE_BASELINE_SHA = baseline;
  const syncRemote = () => git(`--git-dir=${bare}`, 'fetch', '--quiet', cwd,
    'refs/heads/main:refs/heads/main', 'refs/tags/*:refs/tags/*');
  syncRemote();
  const guard = (overrides = {}, mode = 'preflight') => {
    writeFileSync(env.GITHUB_OUTPUT, '');
    const run = spawnSync('bash', [script('./guard.sh'), mode], {
      cwd, env: { ...env, ...overrides }, encoding: 'utf8',
    });
    return { ...run, output: readFileSync(env.GITHUB_OUTPUT, 'utf8') };
  };
  const preview = () => spawnSync(process.execPath, [script('./preview.mjs')], {
    cwd, env, encoding: 'utf8',
  });
  return { git, baseline, commit, syncRemote, guard, preview };
}

test('guard blocks missing/mismatched baselines, non-main refs, stale commits and partial publication', (t) => {
  const repo = fixture(t);
  assert.match(repo.guard().stderr, /Missing annotated v1\.0\.0/);
  assert.match(repo.guard({ GITHUB_REF: 'refs/heads/feature' }).stderr, /exact event commit on main/);
  repo.git('tag', '-a', 'v1.0.0', repo.baseline, '-m', 'Baseline');
  repo.syncRemote();
  assert.match(repo.guard({ RELEASE_BASELINE_SHA: '0'.repeat(40) }).stderr, /must match/);
  assert.match(repo.guard().stderr, /Tag v1\.0\.0 exists without/);

  const tip = repo.commit('fix: restore startup');
  assert.equal(repo.guard({ PUBLISHED_TAGS: 'v1.0.0' }).output, 'current=false\n');
  repo.syncRemote();
  assert.equal(repo.guard({ PUBLISHED_TAGS: 'v1.0.0' }).output, 'current=true\n');

  repo.git('tag', 'v1.0.1', tip);
  repo.syncRemote();
  for (const mode of ['preflight', 'verify-tags']) {
    const partial = repo.guard({ PUBLISHED_TAGS: 'v1.0.0' }, mode);
    assert.equal(partial.status, 1);
    assert.match(partial.stderr, /Tag v1\.0\.1 exists without a published stable GitHub Release/);
  }
  assert.equal(repo.guard({ PUBLISHED_TAGS: 'v1.0.0\nv1.0.1' }).output, 'current=true\n');
  assert.equal(repo.git('rev-parse', 'v1.0.1'), tip);
});

test('actual dry run is read-only and an already released commit is a no-op', (t) => {
  const repo = fixture(t);
  repo.git('tag', '-a', 'v1.0.0', repo.baseline, '-m', 'Baseline');
  repo.commit('fix: restore startup');
  const tip = repo.commit('feat: add backups');
  repo.syncRemote();
  repo.git('switch', '--quiet', '--detach', tip);
  const first = repo.preview();
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /next release version is 1\.1\.0/);
  assert.match(first.stdout, /add backups/);
  assert.match(first.stdout, /github\.com\/example\/homelab/);
  assert.equal(repo.git('tag', '--list'), 'v1.0.0');
  assert.equal(repo.git('ls-remote', '--tags', '--refs', 'origin').split('\n').length, 1);

  repo.git('tag', 'v1.1.0', tip);
  repo.syncRemote();
  const repeat = repo.preview();
  assert.equal(repeat.status, 0, repeat.stderr);
  assert.match(repeat.stdout, /no relevant changes, so no new version is released/i);
});

test('breaking migration text is preserved in notes, unlike ordinary docs changes', (t) => {
  const repo = fixture(t);
  repo.git('tag', '-a', 'v1.0.0', repo.baseline, '-m', 'Baseline');
  repo.commit('docs: clarify the procedure');
  const routine = repo.preview();
  assert.equal(routine.status, 0, routine.stderr);
  assert.match(routine.stdout, /no relevant changes, so no new version is released/i);

  repo.commit('docs!: change the restore procedure\n\nBREAKING CHANGE: Move the existing volume first.');
  const breaking = repo.preview();
  assert.equal(breaking.status, 0, breaking.stderr);
  assert.match(breaking.stdout, /next release version is 2\.0\.0/);
  assert.match(breaking.stdout, /Move the existing volume first/);
});
