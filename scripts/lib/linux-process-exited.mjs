// Finite container-fixture observation only. A local child being gone/zombie
// is never evidence of native inference completion or a released model lease.
export function localLinuxProcessExited(pid, readFile) {
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new TypeError('Invalid fixture process');
  let stat;
  try {
    stat = readFile('/proc/' + pid + '/stat', 'utf8');
  } catch (error) {
    // The child can exit after enumeration/readiness, before this single read.
    // Permission, I/O and malformed observations remain failures, not absence.
    if (error?.code === 'ENOENT') return true;
    throw error;
  }
  const open = stat.indexOf('('), close = stat.lastIndexOf(')');
  const tail = stat.slice(close + 1).trimStart();
  if (open < 1 || close <= open || stat.slice(0, open).trim() !== String(pid) ||
      !/^[A-Za-z](?:\s|$)/.test(tail)) throw new Error('Invalid fixture process observation');
  return tail[0] === 'Z';
}
