#!/usr/bin/env python3
"""One-shot private development compiler admission; never native inference authority."""
import argparse,fcntl,hashlib,json,os,signal,stat,subprocess,sys,time,uuid
from pathlib import Path
PIN='1c5f706db0ed6d55451940f31dc05a6177d05696bc1fa5d853696d04c718b523'

def unique(rows):
 result={}
 for key,value in rows:
  if key in result:raise ValueError('duplicate')
  result[key]=value
 return result

def checked(path,maximum,mode):
 fd=os.open(path,os.O_RDONLY|os.O_NOFOLLOW|os.O_NONBLOCK|os.O_CLOEXEC)
 try:
  before=os.fstat(fd)
  if not(stat.S_ISREG(before.st_mode) and before.st_uid==os.getuid() and before.st_nlink==1 and stat.S_IMODE(before.st_mode)==mode and 0<before.st_size<=maximum):raise ValueError('identity')
  chunks=[];length=0
  while length<before.st_size:
   part=os.read(fd,min(65536,before.st_size-length))
   if not part:raise ValueError('short')
   chunks.append(part);length+=len(part)
  data=b''.join(chunks)
  after=os.fstat(fd);named=os.stat(path,follow_symlinks=False)
  identity=lambda s:(s.st_dev,s.st_ino,s.st_uid,s.st_gid,s.st_mode,s.st_nlink,s.st_size,s.st_mtime_ns,s.st_ctime_ns)
  if identity(before)!=identity(after) or identity(after)!=identity(named):raise ValueError('changed')
  return data
 finally:os.close(fd)

def main():
 p=argparse.ArgumentParser();p.add_argument('--config',type=Path,required=True);p.add_argument('arguments',nargs=argparse.REMAINDER);a=p.parse_args()
 if os.geteuid()==0 or sys.version_info[:3]!=(3,11,17):raise ValueError('runtime')
 if not(a.config.is_absolute() and str(a.config).startswith('/private/tmp/') and a.config.resolve()==a.config):raise ValueError('path')
 c=json.loads(checked(a.config,16384,0o600),object_pairs_hook=unique)
 if set(c)!={'version','scope','root','program','program_sha256','gate_sha256','deadline_seconds'} or type(c['version'])is not int or c['version']!=1:raise ValueError('schema')
 root=Path(c['root']);info=root.lstat()
 if root!=a.config.parent or root.resolve()!=root or not stat.S_ISDIR(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)!=0o700:raise ValueError('root')
 if c['scope'] not in ['native_compile_only','metadata_mock'] or type(c['deadline_seconds'])is not int or not 1<=c['deadline_seconds']<=1200:raise ValueError('scope')
 gate=Path(__file__).resolve();program=Path(c['program'])
 if hashlib.sha256(gate.read_bytes()).hexdigest()!=c['gate_sha256']:raise ValueError('gate changed')
 if not(program.is_absolute() and str(program).startswith('/private/tmp/') and program.resolve()==program):raise ValueError('program')
 data=checked(program,256<<20,0o755)
 if hashlib.sha256(data).hexdigest()!=c['program_sha256'] or c['scope']=='native_compile_only' and (program.name!='zig' or c['program_sha256']!=PIN):raise ValueError('compiler')
 args=a.arguments
 if not args or args[0]!='--':raise ValueError('arguments')
 args=args[1:]
 if c['scope']=='native_compile_only' and (not args or args[0] not in ['translate-c','build-obj','build-exe','build-lib','test','env','version','targets','ar','cc','c++','clang','ld.lld']):raise ValueError('nested execution refused')
 stopped=[None]
 def stop(number,_):stopped[0]=number
 for number in [signal.SIGTERM,signal.SIGINT]:signal.signal(number,stop)
 began=time.monotonic();lease=None;slot=None;job=str(uuid.uuid4());child=None
 def event(kind,**fields):
  fd=os.open(root/'events.jsonl',os.O_WRONLY|os.O_APPEND|os.O_NOFOLLOW|os.O_CLOEXEC)
  try:
   s=os.fstat(fd)
   if not stat.S_ISREG(s.st_mode) or s.st_uid!=os.getuid() or s.st_nlink!=1 or stat.S_IMODE(s.st_mode)!=0o600:raise ValueError('event identity')
   fcntl.flock(fd,fcntl.LOCK_EX);record={'event':kind,'job':job,'slot':slot,'wrapper_pid':os.getpid(),'at':time.monotonic(),**fields};payload=(json.dumps(record,separators=(',',':'))+'\n').encode();assert len(payload)<8192
   if os.write(fd,payload)!=len(payload):raise OSError('short event')
  finally:os.close(fd)
 def block(reason):
  try:
   fd=os.open(root/'blocked',os.O_WRONLY|os.O_CREAT|os.O_EXCL|os.O_NOFOLLOW,0o600);os.write(fd,reason.encode());os.close(fd)
  except FileExistsError:pass
 while lease is None:
  if (root/'blocked').exists() or stopped[0] or time.monotonic()-began>=c['deadline_seconds']:return 124
  for index in range(2):
   fd=os.open(root/('slot-'+str(index)),os.O_RDWR|os.O_NOFOLLOW|os.O_CLOEXEC)
   s=os.fstat(fd)
   if not stat.S_ISREG(s.st_mode) or s.st_uid!=os.getuid() or s.st_nlink!=1 or stat.S_IMODE(s.st_mode)!=0o600 or s.st_size!=0:os.close(fd);raise ValueError('slot identity')
   try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
   except BlockingIOError:os.close(fd);continue
   lease=fd;slot=index;break
  if lease is None:time.sleep(.005)
 try:
  if (root/'blocked').exists() or stopped[0]:return 124
  child=subprocess.Popen([str(program),*args],start_new_session=True)
  event('start',compiler_pid=child.pid,argument_sha256=hashlib.sha256(json.dumps(args).encode()).hexdigest())
  term_at=None;killed=False
  while child.poll() is None:
   now=time.monotonic()
   if (stopped[0] or now-began>=c['deadline_seconds']) and term_at is None:
    os.killpg(child.pid,signal.SIGTERM);term_at=now
   if term_at is not None and now-term_at>=2 and not killed and child.poll() is None:
    os.killpg(child.pid,signal.SIGKILL);killed=True
   time.sleep(.005)
  status=child.wait();end=time.monotonic()+2
  while True:
   try:os.killpg(child.pid,0);present=True
   except ProcessLookupError:present=False
   if not present:break
   if time.monotonic()>=end:block('compiler descendant group remains unknown');event('uncertain',compiler_pid=child.pid);return 125
   time.sleep(.01)
  event('end',compiler_pid=child.pid,status=status)
  return status if status>=0 else 128-status
 except BaseException:
  block('compiler gate failed; no new jobs')
  if child is not None and child.poll() is None:
   os.killpg(child.pid,signal.SIGKILL);child.wait()
  raise
 finally:
  if lease is not None:os.close(lease)

if __name__=='__main__':
 try:raise SystemExit(main())
 except Exception:
  print('Compiler gate failed; retain private build data.',file=sys.stderr);raise SystemExit(125)
