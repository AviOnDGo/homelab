import { execFileSync } from 'node:child_process';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import semanticRelease from 'semantic-release';
import config from '../../release.config.mjs';

const cwd = process.cwd();
const { GITHUB_SERVER_URL: server, GITHUB_REPOSITORY: repository } = process.env;
if (!server || !repository) throw new Error('Missing GitHub repository context.');
const repositoryUrl = `${server}/${repository}.git`;

const mirror = mkdtempSync(join(tmpdir(), 'homelab-release-preview-'));
try {
  execFileSync('git', ['init', '--bare', '--quiet', '--initial-branch=main', mirror]);
  execFileSync('git', [`--git-dir=${mirror}`, 'fetch', '--quiet', cwd,
    'HEAD:refs/heads/main', 'refs/tags/*:refs/tags/*', 'refs/notes/*:refs/notes/*']);
  // Some semantic-release Git commands inherit the process environment directly.
  Object.assign(process.env, {
    GIT_ALLOW_PROTOCOL: 'file',
    GIT_CONFIG_COUNT: '1',
    GIT_CONFIG_KEY_0: `url.${pathToFileURL(mirror).href}.insteadOf`,
    GIT_CONFIG_VALUE_0: repositoryUrl,
  });
  // semantic-release verifies push access even in dry-run mode. Point Git at a local
  // mirror while retaining the GitHub URL for release-note links.
  await semanticRelease({
    ...config,
    plugins: config.plugins.slice(0, 2),
    repositoryUrl,
    dryRun: true,
    ci: false,
  }, { cwd });
} finally {
  rmSync(mirror, { recursive: true, force: true });
}
