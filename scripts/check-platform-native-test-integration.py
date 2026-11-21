#!/usr/bin/env python3
"""Review the exact native test/SDK boundary overlay and real closure check."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--parent', type=Path, required=True)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
for path in [args.source, args.parent]:
    assert str(path).startswith('/private/tmp/') and path.resolve() == path
sha = lambda data: hashlib.sha256(data).hexdigest()
parents = json.loads((root/'platform/studio/native/native_test_integration_parents.json').read_text())
work = Path(tempfile.mkdtemp(prefix='fios-009-native-test-integration-', dir='/private/tmp'))
review = work/'review'
review.mkdir(mode=0o700)
inputs = {}
for name in parents:
    data = (args.source/name).read_bytes()
    target = review/name
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    target.write_bytes(data)
    inputs[name] = sha(data)
patch = (root/'platform/studio/native/mlx-serve-native-test-integration.patch').read_bytes()
(work/'source.patch').write_bytes(patch)
subprocess.run(['/usr/bin/git', 'apply', '--reverse', str(work/'source.patch')], cwd=review, capture_output=True, check=True)
for name, expected in parents.items():
    assert not (review/name).exists() if expected is None else sha((review/name).read_bytes()) == expected
    assert not (args.parent/name).exists() if expected is None else sha((args.parent/name).read_bytes()) == expected
subprocess.run(['/usr/bin/git', 'apply', str(work/'source.patch')], cwd=review, capture_output=True, check=True)
for name in parents:
    assert inputs[name] == sha((review/name).read_bytes())
assert (args.source/'scripts/unit_closure.py').read_bytes() == (args.parent/'scripts/unit_closure.py').read_bytes()
receipt = dict(scope='exact_test_graph_sdk_boundary_overlay_and_actual_import_closure_not_native_authority',
               inputs=inputs, parent_projection=parents, patch_sha256=sha(patch), runner_sha256=sha(Path(__file__).read_bytes()),
               closure_checker_sha256=sha((args.source/'scripts/unit_closure.py').read_bytes()),
               models=0, installed=False, activation=False, results=[])
for label, source in [('parent', args.parent), ('candidate', args.source)]:
    result = subprocess.run(['/usr/bin/sandbox-exec', '-p', '(version 1)(allow default)(deny network*)', sys.executable,
                             '-I', 'scripts/unit_closure.py', '--except', 'clef,qwen4_exp'], cwd=source, capture_output=True, timeout=30)
    output = result.stdout+result.stderr
    (work/(label+'.log')).write_bytes(output)
    expected = (result.returncode == 1 and b'src/sdk/ane/source_guard.zig' in output and b'src/fios/current_ane_run_uncertainty.zig' in output) if label == 'parent' else result.returncode == 0
    receipt['results'].append(dict(label=label, status=result.returncode, expected=expected, log_sha256=sha(output)))
    (work/'receipt.json').write_text(json.dumps(receipt, indent=2)+'\n')
    assert expected, str(work)
print(work)
print('PASS original closure failure and corrected closure; native build/runtime remain separate')
