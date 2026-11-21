#!/usr/bin/env python3
"""Actual native custody and selected Table host reads; no model or GPU."""
from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile,shutil,re
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--zig',type=Path,required=True);a=p.parse_args()
assert os.uname().sysname=='Darwin' and os.geteuid()>0
for v in [a.source,a.zig]:assert v==v.resolve() and str(v).startswith('/private/tmp/')
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest();assert sha(a.zig)=='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'
r=Path(__file__).resolve().parents[1];base=r/'platform/studio/native';patch=base/'mlx-serve-engram-bounded-cleanup.patch';parents=base/'engram_bounded_cleanup_parents.json';fixture=base/'engram_native_table.zig.fixture';w=Path(tempfile.mkdtemp(prefix='fios-009-engram-native-table-',dir='/private/tmp'));unit=w/'unit';unit.mkdir();inputs={str(p):sha(p) for p in [patch,parents,fixture,Path(__file__)]};env={'PATH':'/usr/bin:/bin','HOME':str(w),'LANG':'C','LC_ALL':'C','DEVELOPER_DIR':'/Applications/Xcode.app/Contents/Developer'}
for name in json.loads(parents.read_text()):
 src=a.source/name;inputs[str(src)]=sha(src);dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
for reverse in [True,False]:
 subprocess.run(['/usr/bin/git','apply',*(['--reverse'] if reverse else []),str(patch)],cwd=unit,env=env,check=True,capture_output=True,timeout=5)
 for name,digest in json.loads(parents.read_text()).items():assert sha(unit/name)==(digest if reverse else inputs[str(a.source/name)])
pending=['src/fios/request_ownership.zig','src/fios/sdk_request_ownership.zig','src/sdk/util/warm_request_origins.zig','src/sdk/util/crt.zig'];copied=set()
while pending:
 name=pending.pop()
 if name in copied:continue
 src=a.source/name;assert src.is_file() and not src.is_symlink() and src.stat().st_size<=1<<20
 copied.add(name);assert len(copied)<=128;inputs[str(src)]=sha(src);dst=unit/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
 for match in re.finditer(r'@import\("([^"\n]+\.zig)"\)',src.read_text()):
  dep=(src.parent/match.group(1)).resolve();relative=dep.relative_to(a.source)
  if dep.exists():pending.append(str(relative))
text=(unit/'src/plugins/deepseek_v41/engram.zig').read_text()
def method(text,signature):
 start=text.index(signature);at=text.index('{',start)+1;depth=1
 while depth:
  depth+=(text[at]=='{')-(text[at]=='}');at+=1
 return text[start:at]
table=method(text,'pub const Table = struct ')
read=table[:table.index('    pub fn open(')]+table[table.index('    pub const Raw = struct '):table.index('    /// The first `n` rows')]+table[table.index('    /// Asks the kernel'):]
params=a.source/'src/sdk/quant/params.zig';inputs[str(params)]=sha(params)
quant=method(params.read_text(),'pub const QuantMode = enum ')
prefetch=text[text.index('const fios_prefetch_cleanup_failed ='):text.index('const GCD_ROWS =')]
helpers=text[text.index('const GCD_ROWS ='):text.index('fn fileSize(')]
rendered=fixture.read_text().replace('@@QUANT_MODE@@',quant+';').replace('@@TABLE_READ@@',read+';').replace('@@READ_HELPERS@@',helpers).replace('@@PREFETCH@@',prefetch)
(unit/'src/plugins/deepseek_v41/check.zig').write_text(rendered)
(unit/'src/main.zig').write_text('comptime {_ = @import("plugins/deepseek_v41/check.zig");}')
(unit/'options.zig').write_text('pub const fios_source_sdk=true;pub const fios_source_ane=false;pub const llama_engine=false;')
rows=b''.join((i+100).to_bytes(4,'little') for i in range(640))+b''.join((i+200).to_bytes(2,'little') for i in range(640))+b''.join((i+300).to_bytes(2,'little') for i in range(640))
(unit/'rows.bin').write_bytes(rows);inputs[str(unit/'rows.bin')]=sha(unit/'rows.bin');records=[]
for mode in ['Debug','ReleaseSafe']:
 for case in ['GCD','threaded','duplicate','bad row','negative getter']:
  args=['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',str(a.zig),'test','-O'+mode,'--test-filter','native Engram actual table '+case,'--dep','build_options','-Mroot='+str(unit/'src/main.zig'),'-Mbuild_options='+str(unit/'options.zig'),'-lc']
  result=subprocess.run(args,cwd=unit,env=env,capture_output=True,text=True,timeout=60);log=w/(mode+'-'+case.replace(' ','-')+'.log');log.write_text(result.stdout+result.stderr)
  assert result.returncode==0 and 'All 2 tests passed.' in log.read_text(),log.read_text()
  records.append({'mode':mode,'case':case,'status':result.returncode,'log_sha256':sha(log)})
assert inputs=={n:sha(Path(n)) for n in inputs}
p=w/'receipt.json';p.write_text(json.dumps({'scope':'actual_native_custody_ABI_prefetch_and_selected_Table_CPU_file_reads_not_model_or_native_acceptance','inputs':inputs,'records':records,'private_row_bytes':len(rows),'gcd_and_joined_thread_reads':True,'model_loader_and_dequantizer_exercised':False,'selected_Engram_negative_getter_enrolled':True,'whole_backend_probe_enrolled':False,'synthetic_table_reader':False,'models':0,'model_requests':0,'GPU_work':False,'native_authority':False,'all_client_coverage':False,'installed':False},indent=2)+'\n');print(json.dumps({'directory':str(w),'sha256':sha(p)}))
