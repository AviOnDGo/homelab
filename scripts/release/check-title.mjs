import { isValidTitle, types } from './conventions.mjs';

if (!isValidTitle(process.env.PR_TITLE)) {
  console.error('Use "type(scope)!: description"; scope and ! are optional.');
  console.error(`Accepted types: ${Object.keys(types).join(', ')}.`);
  process.exitCode = 1;
}
