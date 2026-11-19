import { parserOpts, types } from './scripts/release/conventions.mjs';

const conventional = { preset: 'conventionalcommits', parserOpts };

export default {
  branches: ['main'],
  tagFormat: 'v${version}',
  plugins: [
    ['@semantic-release/commit-analyzer', {
      ...conventional,
      releaseRules: [
        { breaking: true, release: 'major' },
        ...Object.entries(types).map(([type, release]) => ({ type, release })),
      ],
    }],
    ['@semantic-release/release-notes-generator', conventional],
    ['@semantic-release/github', {
      successComment: false,
      failComment: false,
      failTitle: false,
      releasedLabels: false,
      addReleases: false,
      draftRelease: false,
    }],
  ],
};
