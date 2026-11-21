#!/usr/bin/env python3
"""Finite metadata children exercise the development compiler gate, never models."""
from pathlib import Path
import hashlib,json,os,signal,subprocess,sys,tempfile,time
assert sys.version_info[:3]==(3,11,17) and os.geteuid()>0
repo=Path(__file__).resolve().parents[1];gate=repo/'scripts/platform-compiler-gate.py';sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();digest=sha(gate)
w=Path(tempfile.mkdtemp(prefix='fios-009-compiler-gate-check-',dir='/private/tmp'))
program=w/'mock-compiler.py';program.write_text('#!'+sys.executable+' -I\nimport sys,time\ntime.sleep(float(sys.argv[1]))\nsys.exit(int(sys.argv[2]) if len(sys.argv)>2 else 0)\n');program.chmod(0o755)
checker_digest=sha(Path(__file__));program_digest=sha(program);records=[]
def setup(name,deadline=5):
 root=w/name;root.mkdir(mode=0o700)
 for name in ['slot-0','slot-1','events.jsonl']:
  p=root/name;p.touch(mode=0o600)
 config=root/'config.json';config.write_text(json.dumps(dict(version=1,scope='metadata_mock',root=str(root),program=str(program),program_sha256=sha(program),gate_sha256=digest,deadline_seconds=deadline)));config.chmod(0o600)
 return root,[sys.executable,'-I',str(gate),'--config',str(config),'--']
def finish(root):
 events=[json.loads(x) for x in (root/'events.jsonl').read_text().splitlines()];active=set();peak=0
 for e in events:
  if e['event']=='start':assert e['job'] not in active;active.add(e['job']);peak=max(peak,len(active))
  elif e['event']=='end':active.remove(e['job'])
  else:raise AssertionError(e)
 assert not active and peak<=2 and not (root/'blocked').exists()
 return len(events)//2,peak
root,args=setup('parallel');children=[subprocess.Popen(args+['.2'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL) for _ in range(4)]
assert [c.wait(timeout=10) for c in children]==[0]*4
jobs,peak=finish(root);assert jobs==4 and peak==2;records.append(dict(case='parallel',jobs=jobs,peak=peak))
root,args=setup('cancel');child=subprocess.Popen(args+['5'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
end=time.monotonic()+5
while not (root/'events.jsonl').stat().st_size:
 assert child.poll() is None and time.monotonic()<end;time.sleep(.01)
child.send_signal(signal.SIGTERM);assert child.wait(timeout=5)==143
assert finish(root)==(1,1)
assert subprocess.run(args+['0'],timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
assert finish(root)==(2,1);records.append(dict(case='cancel_then_reuse',jobs=2,peak=1))
root,args=setup('deadline',1);assert subprocess.run(args+['5'],timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==143
assert finish(root)==(1,1);records.append(dict(case='deadline',jobs=1,peak=1))
root,args=setup('failure');assert subprocess.run(args+['0','7'],timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==7
assert finish(root)==(1,1)
assert subprocess.run(args+['0'],timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==0
assert finish(root)==(2,1);records.append(dict(case='failed_job_then_reuse',jobs=2,peak=1))
root,args=setup('changed-program');program.write_text(program.read_text()+'# changed\n');assert subprocess.run(args+['0'],timeout=5,stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode==125
assert finish(root)==(0,0);records.append(dict(case='changed_program_refused',jobs=0,peak=0))
assert sha(gate)==digest and sha(Path(__file__))==checker_digest
p=w/'receipt.json';p.write_text(json.dumps(dict(scope='metadata_child_admission_cancellation_deadline_identity_not_native_compiler_or_model_acceptance',gate_sha256=digest,checker_sha256=checker_digest,initial_mock_program_sha256=program_digest,event_sha256={p.parent.name:sha(p) for p in w.glob('*/events.jsonl')},records=records,model_requests=0,native_authority=False),indent=2)+'\n');print(json.dumps(dict(directory=str(w),receipt_sha256=sha(p))))
