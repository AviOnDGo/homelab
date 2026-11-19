export const types = {
  feat: 'minor',
  fix: 'patch',
  perf: 'patch',
  revert: 'patch',
  docs: false,
  style: false,
  refactor: false,
  test: false,
  build: false,
  ci: false,
  chore: false,
};

const prefix = `(${Object.keys(types).join('|')})(?:\\(([a-zA-Z0-9][a-zA-Z0-9._/-]*)\\))?`;
const description = ': (\\S[^\\r\\n]*)$';
export const parserOpts = {
  headerPattern: new RegExp(`^${prefix}!?${description}`),
  breakingHeaderPattern: new RegExp(`^${prefix}!${description}`),
  // Only an explicit conventional `revert:` subject is classified as a revert.
  revertPattern: /(?!)/,
};

export function isValidTitle(title) {
  return typeof title === 'string' && !/[\r\n]/.test(title) && parserOpts.headerPattern.test(title);
}
