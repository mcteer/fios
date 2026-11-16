#!/usr/bin/env python3
"""Validate the narrowly scoped Qwen reader-publication overlay; no execution authority."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--isolated', action='store_true', required=True)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--zig', type=Path, required=True)
args = parser.parse_args()
source = args.source
assert source == source.resolve() and str(source).startswith('/private/tmp/')
root = Path(__file__).resolve().parents[1]
assert platform.system() == 'Darwin' and platform.machine() == 'arm64'
base = root / 'platform/studio/native'
patch = base / 'mlx-serve-qwen-warm-publication.patch'
parents = base / 'qwen_warm_publication_parents.json'
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
assert args.zig == args.zig.resolve() and str(args.zig).startswith('/private/tmp/')
assert sha(args.zig) == '1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
expected = json.loads(parents.read_text())
name = 'src/plugins/qwen4_exp/trunk_load.zig'
assert set(expected) == {name}
original = source / name
assert original.is_file() and not original.is_symlink()
assert original.stat().st_uid == os.geteuid() and original.stat().st_mode & 0o022 == 0
assert sha(original) == expected[name], 'requires the exact pre-publication parent'
work = Path(tempfile.mkdtemp(prefix='fios-009-qwen-publication-check-', dir='/private/tmp'))
target = work / name
target.parent.mkdir(parents=True)
target.write_bytes(original.read_bytes())
env = {'PATH': '/usr/bin:/bin', 'HOME': str(work), 'LANG': 'C', 'LC_ALL': 'C',
       'GIT_CONFIG_GLOBAL': '/dev/null', 'GIT_CONFIG_NOSYSTEM': '1'}
subprocess.run(['/usr/bin/git', 'apply', '--check', str(patch)], cwd=work,
               env=env, check=True, capture_output=True, timeout=15)
subprocess.run(['/usr/bin/git', 'apply', str(patch)], cwd=work,
               env=env, check=True, capture_output=True, timeout=15)
text = target.read_text()
load = text[text.index('pub fn load('):text.index('\n/// A raw ggml table')]
assert load.count('st.table.startWarm();') == 1
publication = load.index('st.table.startWarm();')
assert publication > load.rindex('try ')
assert publication > load.index('const result: Trunk = .{')
assert load[publication:].strip() == 'st.table.startWarm();\n    }\n    return result;\n}'
# Reader placement must preserve both original host-role and table predicates.
role = 'if (config.pleLocalLayer() != null and !(if (config.dist_shard) |sh| sh.rank != 0 else false)) {'
assert load.count(role) == 2
assert load.rindex(role) < publication
assert 'if (st.gpu == null or st.table.embedded == null) st.table.startWarm();' in load
candidate = sha(target)
candidate_text = text
subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(patch)], cwd=work,
               env=env, check=True, capture_output=True, timeout=15)
assert sha(target) == expected[name] and sha(original) == expected[name]
receipt = {'scope': 'actual_load_tail_publication_and_failure_order_with_explicit_model_ports_not_native_runtime_proof',
           'parent': expected, 'candidate_sha256': candidate,
           'zig_sha256': sha(args.zig),
           'inputs': {str(p.relative_to(root)): sha(p) for p in [patch, parents, Path(__file__), base / 'qwen_warm_publication.zig.fixture']},
           'model_requests': 0, 'runtime_failure_injection': True,
           'modeled_ports': ['GPU_selection_and_MLX_values', 'MTP_and_bias_errors', 'owned_list_failure', 'table_reader_and_cleanup'],
           'actual_execution': 'unaltered_load_tail_control_flow_with_real_reader_thread_and_allocator',
           'records': [],
           'bounded_shutdown': False, 'installed': False, 'native_authority': False}
def save():
    (work / 'receipt.json').write_text(json.dumps(receipt, indent=2) + '\n')
save()
template = (base / 'qwen_warm_publication.zig.fixture').read_text()
assert template.count('@@LOAD_TAIL@@') == 1
for label, selected in [('parent', original.read_text()), ('candidate', candidate_text)]:
    begin = selected.index('    var weights_bytes: usize = 0;')
    end = selected.index('\n}\n', begin)
    unit = work / (label + '.zig')
    unit.write_text(template.replace('@@LOAD_TAIL@@', selected[begin:end]))
    for mode in ['Debug', 'ReleaseSafe']:
        binary = work / (label + '-' + mode)
        result = subprocess.run([str(args.zig), 'test', str(unit), '-lc', '-O' + mode,
                                 '--test-no-exec', '-femit-bin=' + str(binary)],
                                env=env, capture_output=True, text=True, timeout=120)
        log = work / (label + '-' + mode + '-compile.log')
        log.write_text(result.stdout + result.stderr)
        assert result.returncode == 0, log.read_text()
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', str(binary)],
                                env=env, capture_output=True, text=True, timeout=15)
        log = work / (label + '-' + mode + '-runtime.log')
        log.write_text(result.stdout + result.stderr)
        passed = (result.returncode != 0 and 'expected 0, found 1' in log.read_text()) if label == 'parent' else result.returncode == 0
        receipt['records'].append({'profile': label, 'mode': mode, 'status': result.returncode,
                                   'expected': passed, 'log_sha256': sha(log)})
        save()
        assert passed, log.read_text()
receipt['inputs_unchanged'] = (sha(original) == expected[name]
                              and sha(args.zig) == receipt['zig_sha256']
                              and all(sha(root / name) == digest for name, digest in receipt['inputs'].items()))
assert receipt['inputs_unchanged']
save()
print(json.dumps({'directory': str(work), 'receipt_sha256': sha(work / 'receipt.json')}))
