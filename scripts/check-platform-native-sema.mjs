#!/usr/bin/env node
// Deliberate source-only Zig semantic subset, NOT upstream runtime/link/release
// acceptance. Never fabricates dependency stamps or starts a serving process.
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, writeFileSync, copyFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
assert(args.length === 6 && args[0] === '--source' && args[2] === '--zig' && args[4] === '--webp-source' && [args[1], args[3], args[5]].every(path.isAbsolute),
  'usage: check-platform-native-sema.mjs --source ABS_CHECKOUT --zig ABS_ZIG --webp-source ABS_WEBP_1_6_0');
const source = args[1], zig = args[3], webp = args[5];
const run = (file, argv, options = {}) => execFileSync(file, argv, { encoding: 'utf8', timeout: 180_000, maxBuffer: 16 * 1024 * 1024, ...options });
const git = (directory, ...argv) => run('git', ['--no-replace-objects', '-C', directory, ...argv]);
assert.equal(git(source, 'rev-parse', 'HEAD').trim(), '046b647686419df06c6c7132fb1d15d76185c3e5');
assert.equal(git(webp, 'rev-parse', 'HEAD').trim(), '4fa21912338357f89e4fd51cf2368325b59e9bd9');
assert.equal(git(webp, 'status', '--porcelain').trim(), '', 'modified webp headers');
assert.deepEqual(git(source, 'diff', '--name-only').trim().split('\n').sort(), ['build.zig','lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','src/arch/ds4.zig','src/arch/ds4_stub.zig','src/arch/llama.zig','src/arch/llama_stub.zig','src/arch/mlx_stream.zig','src/arch/mlx_stream_stub.zig','src/llama_ffi.zig','src/main.zig','src/mlx.zig','src/model_registry.zig','src/scheduler.zig','src/server.zig','src/transformer.zig']);
for (const line of git(source, 'ls-tree', 'HEAD', 'lib/').split('\n').filter(line => line.startsWith('160000 '))) {
  const [, , , revision, module] = line.match(/^(\d+) (\w+) ([a-f0-9]+)\t(.+)$/);
  assert.equal(git(path.join(source, module), 'rev-parse', 'HEAD').trim(), revision, `unreviewed ${module}`);
  assert.equal(git(path.join(source, module), 'diff', '--name-only').trim(), '', `modified ${module}`);
}
run(process.execPath, [path.join(root, 'scripts/check-platform-native.mjs'), '--source', source, '--zig', zig]);
// Check the actual sources being semantically compiled against the exact patch.
const patch = readFileSync(path.join(root, 'platform/studio/native/mlx-serve-26.10.3.patch'), 'utf8');
assert.equal(git(source, 'diff', '--', 'build.zig','lib/llama_shim/llama_shim.cpp','lib/llama_shim/llama_shim.h','src/arch/ds4.zig','src/arch/ds4_stub.zig','src/arch/llama.zig','src/arch/llama_stub.zig','src/arch/mlx_stream.zig','src/arch/mlx_stream_stub.zig','src/llama_ffi.zig','src/main.zig','src/mlx.zig','src/model_registry.zig','src/server.zig','src/scheduler.zig','src/transformer.zig'), patch, 'native checkout differs from reviewed patch');
for (const name of ['backend_lifetime.zig', 'request_ownership.zig', 'control_protocol.zig', 'control_transport.zig', 'device_owner.zig', 'startup_guard.zig']) {
  assert.equal(readFileSync(path.join(source, 'src', name), 'utf8'), readFileSync(path.join(root, 'platform/studio/native', name), 'utf8'));
}
for (const name of ['device_owner_barrier.cpp', 'device_owner_barrier.h']) {
  assert.equal(readFileSync(path.join(source, 'lib', name), 'utf8'), readFileSync(path.join(root, 'platform/studio/native', name), 'utf8'));
}
// The exact reviewed patch above now includes ONLY two macOS C++ source
// additions in the build graph; upstream staging guards remain intact.
let build = readFileSync(path.join(source, 'build.zig'), 'utf8');
const guards = `    if (target.result.os.tag == .macos) {\n        if (webp_prefix) |dir| verifyCopiedDeps(b, dir) else verifyBrewDeps(b);\n        verifyMlxStage(b);\n    }\n`;
const check = '        const check = b.step("check", "Type-check everything, emitting no binary");\n';
assert.equal(build.split(guards).length, 2);
assert.equal(build.split(check).length, 2);
build = build.replace(guards, '    // Development-only unstaged Zig Sema subset; never runtime/release acceptance.\n')
  .replace(check, check + '        for (mod.getGraph().modules) |m| m.link_objects.clearRetainingCapacity();\n        for (test_mod.getGraph().modules) |m| m.link_objects.clearRetainingCapacity();\n');
const scratch = mkdtempSync(path.join(tmpdir(), 'fios-native-sema-'));
const filename = `fios-sema-${randomUUID()}.zig`, generated = path.join(source, filename);
let written = false;
try {
  const headers = path.join(scratch, 'include/webp');
  mkdirSync(headers, { recursive: true });
  mkdirSync(path.join(scratch, 'lib')); // Empty and explicitly unlinked; no fabricated library/stamp.
  for (const filename of readdirSync(path.join(webp, 'src/webp')).filter(name => /^[a-z_]+\.h$/.test(name))) {
    copyFileSync(path.join(webp, 'src/webp', filename), path.join(headers, filename));
  }
  writeFileSync(generated, build, { flag: 'wx', mode: 0o600 });
  written = true;
  // Fixed check target only: no C/object/library linkage, install, run or test
  // execution step. All original Zig module roots and imported sources remain.
  run(zig, ['build', '--build-file', filename, 'check', `-Dwebp-prefix=${scratch}`], { cwd: source });
  console.log('PASS: pinned native executable/test Zig roots semantically compile with the ownership patch.');
  console.log('SUBSET ONLY: runtime staging, C/object/library linkage, ABI, inference and full upstream build are NOT established.');
} finally {
  if (written) rmSync(generated);
  rmSync(scratch, { recursive: true, force: true });
}
