'use strict';
// Write a state file under <project>/.claude/ without following symlinks. A checkout can ship a symlink at the
// state path (or at .claude itself) pointing at a file outside the project; a plain writeFileSync would overwrite
// that file. Here the content goes to a fresh temp file in the same directory (O_EXCL: never an existing path) and
// is renamed over the target, which replaces a symlink instead of writing through it; a .claude that is itself a
// symlink is refused. Used by gate-check.cjs (P1 record) and reconcile-check.cjs (verdict state).
const fs = require('fs');
const path = require('path');

function writeStateFile(file, content) {
  const dir = path.dirname(file);
  fs.mkdirSync(dir, { recursive: true });
  if (fs.lstatSync(dir).isSymbolicLink()) throw new Error(`${dir} is a symlink; refusing to write state through it`);
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, content, { flag: 'wx' });
  try {
    fs.renameSync(tmp, file);
  } catch (e) {
    fs.rmSync(tmp, { force: true });
    throw e;
  }
}

module.exports = { writeStateFile };
