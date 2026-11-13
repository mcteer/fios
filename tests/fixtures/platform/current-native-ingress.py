# Ordinary core-only source-interface fixture. This executes a caller-reviewed
# private binary, not a package installer or native admission producer. It reads
# empty-model health/catalog/control, holds one accepted HTTP connection briefly,
# then stops only its original private child. Optional selection checks use only
# unregistered fixture IDs in the empty registry. No real service action
# or native terminality proof; private state is retained on success/failure.
# Kernel-authenticated manager integration is separate from this wire fixture.
import pathlib,subprocess,socket,tempfile,os,time,http.client,json,signal,sys,struct,hashlib
assert sys.platform=="darwin" and os.geteuid()>0
assert len(sys.argv) in [4,5] and sys.argv[1]=="--isolated"
mode=sys.argv[4] if len(sys.argv)==5 else None
assert mode in [None,"--expected-instance","--exact-target","--startup","--correlation"]
check_instance=mode in ["--expected-instance","--exact-target","--correlation"]
check_target=mode in ["--exact-target","--correlation"]
check_correlation=mode=="--correlation"
check_startup=mode=="--startup"
binary=pathlib.Path(sys.argv[2]);expected=sys.argv[3]
assert binary.is_absolute() and str(binary).startswith("/private/tmp/") and binary.name=="mlx-serve"
info=binary.lstat();assert binary.is_file() and not binary.is_symlink() and info.st_uid==os.geteuid() and info.st_nlink==1 and not info.st_mode&0o022 and 0<info.st_size<=64*1024*1024
assert len(expected)==64 and all(c in "0123456789abcdef" for c in expected)
assert hashlib.sha256(binary.read_bytes()).hexdigest()==expected
assert subprocess.check_output(["/usr/sbin/scutil","--get","LocalHostName"],timeout=2,text=True).strip()=="fios-core"
assert subprocess.check_output(["/usr/sbin/sysctl","-n","hw.memsize"],timeout=2,text=True).strip()==str(24*2**30)
assert subprocess.check_output(["/usr/sbin/sysctl","-n","machdep.cpu.brand_string"],timeout=2,text=True).strip().startswith("Apple M4")
home=pathlib.Path(tempfile.mkdtemp(prefix="f9-cur-ingress-",dir="/private/tmp"));models=home/"empty-models";models.mkdir(mode=0o700)
listener=socket.socket();listener.bind(("127.0.0.1",0));port=listener.getsockname()[1];listener.close()
env={"PATH":"/usr/bin:/bin","HOME":str(home),"LANG":"C","LC_ALL":"C","XDG_CACHE_HOME":str(home/"cache"),"FIOS_NATIVE_CONTROL":"isolated-source-fixture","FIOS_NATIVE_STARTUP":"isolated-source-fixture"}
log=os.open(home/"native.log",os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
proc=subprocess.Popen([str(binary),"serve","--host","127.0.0.1","--port",str(port),"--model-dir",str(models),"--no-warmup-eager"],cwd=home,env=env,stdout=log,stderr=log,start_new_session=True);os.close(log)
def get(path):
 conn=http.client.HTTPConnection("127.0.0.1",port,timeout=1)
 try:
  conn.request("GET",path);reply=conn.getresponse();data=reply.read(65537);assert len(data)<=65536
  return reply.status,data
 finally:conn.close()
try:
 end=time.monotonic()+15;healthy=False
 while time.monotonic()<end:
  assert proc.poll() is None,"CURRENT_NATIVE_SERVER_EXITED"
  try:healthy=get("/health")[0]==200
  except (OSError,http.client.HTTPException):pass
  if healthy:break
  time.sleep(.025)
 assert healthy,"CURRENT_NATIVE_HEALTH_UNAVAILABLE"
 status,body=get("/v1/models");assert status==200 and json.loads(body)["data"]==[],"CURRENT_NATIVE_MODELS_NOT_EMPTY"
 control=home/".fios-native-control/control.sock"
 end=time.monotonic()+1
 while not control.exists() and time.monotonic()<end:time.sleep(.025)
 assert control.exists(),"CURRENT_NATIVE_INGRESS_INTERFACE_MISSING"
 info=control.stat();assert info.st_uid==os.geteuid() and info.st_mode&0o777==0o600
 client=socket.socket(socket.AF_UNIX);client.settimeout(2);client.connect(str(control))
 request=bytearray(32);request[:4]=b"FIC9";request[4]=3;client.sendall(request);client.shutdown(socket.SHUT_WR)
 frame=b""
 while len(frame)<80:
  part=client.recv(80-len(frame));assert part;frame+=part
 client.close()
 assert frame[:4]==b"FIR9" and frame[4:8]==bytes([3,0,0,0])
 instance=frame[8:24].hex();assert int(instance,16)>0
 counts=struct.unpack(">6I",frame[32:56]);assert counts[0]==sum(counts[1:5]) and counts[5]==0
 sequence,stamp=struct.unpack(">2Q",frame[64:80]);assert 0<sequence<=9007199254740991 and -1000<=int(time.time()*1000)-stamp<=5000
 def snapshot():
  connection=socket.socket(socket.AF_UNIX);connection.settimeout(2);connection.connect(str(control));connection.sendall(request);connection.shutdown(socket.SHUT_WR);value=b""
  try:
   while len(value)<80:
    part=connection.recv(80-len(value));assert part;value+=part
  finally:connection.close()
  assert value[:8]==frame[:8] and value[8:24].hex()==instance
  return struct.unpack(">6I",value[32:56]),struct.unpack(">2Q",value[64:80])[0]
 # One ordinary accepted connection proves that request handling and control
 # share the original host ledger across the vendor's compilation units.
 held=socket.create_connection(("127.0.0.1",port),timeout=2)
 try:
  end=time.monotonic()+2;owned=None
  while time.monotonic()<end:
   current,counter=snapshot()
   if current[0]>=1 and current[1]>=1:owned=current;break
   time.sleep(.025)
  assert owned is not None,"CURRENT_NATIVE_HTTP_LEDGER_PARTITIONED"
 finally:held.close()
 end=time.monotonic()+2;released=False
 while time.monotonic()<end:
  current,counter=snapshot()
  if current[0]==0:released=True;break
  time.sleep(.025)
 assert released,"CURRENT_NATIVE_HTTP_CONNECTION_NOT_RETIRED"
 if check_startup:
  # Metadata-only calls remain available while the original process owns
  # the reservation; these do not enter serving or load a model.
  version=subprocess.run([str(binary),"--version"],cwd=home,env=env,capture_output=True,timeout=3)
  assert version.returncode==0 and b"26.11.2-fios-source-fixture" in version.stdout,"CURRENT_NATIVE_METADATA_VERSION_BLOCKED"
  usage=subprocess.run([str(binary),"--help"],cwd=home,env=env,capture_output=True,timeout=3)
  assert usage.returncode==0 and b"mlx-serve" in usage.stdout,"CURRENT_NATIVE_METADATA_HELP_BLOCKED"
  # A second ordinary empty-model invocation shares the private reservation,
  # but has a different loopback port and no control transport collision.
  second_listener=socket.socket();second_listener.bind(("127.0.0.1",0));second_port=second_listener.getsockname()[1];second_listener.close()
  second_env=dict(env);second_env.pop("FIOS_NATIVE_CONTROL")
  second_log=os.open(home/"second-native.log",os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  second=subprocess.Popen([str(binary),"serve","--host","127.0.0.1","--port",str(second_port),"--model-dir",str(models),"--no-warmup-eager"],cwd=home,env=second_env,stdout=second_log,stderr=second_log,start_new_session=True);os.close(second_log)
  try:
   try:result=second.wait(timeout=3)
   except subprocess.TimeoutExpired:
    connection=http.client.HTTPConnection("127.0.0.1",second_port,timeout=1)
    try:
     connection.request("GET","/health");response=connection.getresponse();response.read(65537)
     assert response.status==200,"CURRENT_NATIVE_SECOND_STARTUP_UNEXPECTED_STATE"
    finally:connection.close()
    raise AssertionError("CURRENT_NATIVE_STARTUP_RESERVATION_MISSING")
   assert result!=0 and b"StartupGuardUnavailable" in (home/"second-native.log").read_bytes(),"CURRENT_NATIVE_DUPLICATE_NOT_REFUSED_BY_RESERVATION"
   assert proc.poll() is None and get("/health")[0]==200,"CURRENT_NATIVE_ORIGINAL_LOST_AFTER_DUPLICATE"
  finally:
   if second.poll() is None:second.terminate()
   try:second.wait(timeout=2)
   except subprocess.TimeoutExpired:
    if second.poll() is None:os.killpg(second.pid,signal.SIGKILL)
    second.wait(timeout=2)
  # Once the original private process has exited, the same reservation can
  # be acquired normally. This says nothing about independent native work.
  proc.terminate();proc.wait(timeout=5)
  replacement_log=os.open(home/"replacement-native.log",os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
  replacement=subprocess.Popen([str(binary),"serve","--host","127.0.0.1","--port",str(second_port),"--model-dir",str(models),"--no-warmup-eager"],cwd=home,env=second_env,stdout=replacement_log,stderr=replacement_log,start_new_session=True);os.close(replacement_log)
  try:
   end=time.monotonic()+5;ready=False
   while time.monotonic()<end:
    assert replacement.poll() is None,"CURRENT_NATIVE_STARTUP_REACQUIRE_EXITED"
    connection=http.client.HTTPConnection("127.0.0.1",second_port,timeout=1)
    try:
     connection.request("GET","/health");response=connection.getresponse();response.read(65537);ready=response.status==200
    except (OSError,http.client.HTTPException):pass
    finally:connection.close()
    if ready:break
    time.sleep(.025)
   assert ready,"CURRENT_NATIVE_STARTUP_REACQUIRE_UNAVAILABLE"
  finally:
   if replacement.poll() is None:replacement.terminate()
   try:replacement.wait(timeout=2)
   except subprocess.TimeoutExpired:
    if replacement.poll() is None:os.killpg(replacement.pid,signal.SIGKILL)
    replacement.wait(timeout=2)
 if check_instance:
  wrong=("0" if instance[0]!="0" else "1")+instance[1:]
  connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
  try:
   body=json.dumps({"model":"fixture/missing-model","messages":[{"role":"user","content":"fixture only"}],"max_tokens":1})
   connection.request("POST","/v1/chat/completions",body,{"Content-Type":"application/json","X-Fios-Native-Instance":wrong})
   response=connection.getresponse();reply=response.read(65537)
   assert len(reply)<=65536 and response.status==409,"CURRENT_NATIVE_STALE_EPOCH_NOT_REJECTED"
   assert json.loads(reply)["error"]["type"]=="native_instance_changed"
  finally:connection.close()
  def rejected_with(headers, payload=None):
   connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
   try:
    connection.request("POST","/v1/chat/completions",body if payload is None else payload,{"Content-Type":"application/json",**headers})
    response=connection.getresponse();data=response.read(65537);assert len(data)<=65536
    return response.status,json.loads(data)["error"]["type"]
   finally:connection.close()
  legacy=rejected_with({});matching=rejected_with({"X-Fios-Native-Instance":instance})
  if check_target:
   assert matching==(404,"native_target_not_found"),"CURRENT_NATIVE_BOUND_TARGET_USED_LEGACY_SELECTION"
   assert legacy[0]>=400 and legacy[1]!="native_target_not_found"
   # Ordinary JSON selection shapes; no registered model can execute here.
   for payload,expected_result in [
    ('{"messages":[],"metadata":{"model":"fixture/nested"}}',(404,"native_target_not_found")),
    ('{"model":17,"messages":[]}',(400,"invalid_request_error")),
    ('{"model":"fixture\\u002fmissing-model","messages":[]}',(404,"native_target_not_found")),
    ('{"model":"mlx-serve","messages":[]}',(404,"native_target_not_found")),
   ]:
    assert rejected_with({"X-Fios-Native-Instance":instance},payload)==expected_result,"CURRENT_NATIVE_BOUND_JSON_SELECTION_CHANGED"
   if check_correlation:
    assert rejected_with({"X-Fios-Native-Instance":instance,"X-Fios-Request-ID":"bad-id"})==(400,"invalid_request_identity"),"CURRENT_NATIVE_CORRELATION_HEADER_IGNORED"
    assert rejected_with({"X-Fios-Native-Instance":instance,"X-Fios-Request-ID":"a"*64})==(404,"native_target_not_found"),"CURRENT_NATIVE_VALID_CORRELATION_CHANGED_TARGET"
    end=time.monotonic()+2
    while time.monotonic()<end:
     current,_=snapshot()
     if current[0]==0:break
     time.sleep(.025)
    assert current[0]==0,"CURRENT_NATIVE_CORRELATION_HTTP_ROOT_NOT_RETIRED"
    lineage_request=bytearray(64);lineage_request[:4]=b"FIQ9";lineage_request[4]=1;lineage_request[8:24]=bytes.fromhex(instance);lineage_request[24:56]=bytes([0xaa])*32
    client=socket.socket(socket.AF_UNIX);client.settimeout(2);client.connect(str(control));client.sendall(lineage_request);client.shutdown(socket.SHUT_WR);lineage=b""
    try:
     while len(lineage)<112:
      part=client.recv(112-len(lineage));assert part;lineage+=part
    finally:client.close()
    assert lineage[:8]==b"FIP9"+bytes([1,0,0,1]) and lineage[8:24].hex()==instance and lineage[24:56]==bytes([0xaa])*32,"CURRENT_NATIVE_MISSING_LINEAGE_NOT_UNKNOWN"
    assert 0<struct.unpack(">Q",lineage[56:64])[0]<=9007199254740991 and lineage[64:100]==bytes(36)

  else:
   assert legacy==matching and legacy[0]>=400,"CURRENT_NATIVE_MATCHING_EPOCH_CHANGED_LEGACY_SELECTION"
 receipt={"binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),"native_pid":proc.pid,"source_instance":instance,"source_sequence":sequence,"source_sampled_at":stamp,"http_connection_counts":list(counts),"accepted_connection_observed":True,"original_http_connection_retired":True,"private_home":str(home),"models":0,"model_requests":9 if check_correlation else (7 if check_target else (3 if check_instance else 0)),"expected_instance_guard_checked":check_instance,"exact_target_guard_checked":check_target,"correlation_header_checked":check_correlation,"retired_lineage_is_unknown":check_correlation,"startup_reservation_checked":check_startup,"startup_reacquired_after_original_exit":check_startup,"metadata_available_while_reserved":check_startup,"inference_started":False,"coverage":"unknown","native_admission_authority":False,"peer_authentication_proven":False,"installed":False}
 (home/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n");print(json.dumps(receipt))
finally:
 if proc.poll() is None:proc.terminate()
 try:proc.wait(timeout=5)
 except subprocess.TimeoutExpired:
  if proc.poll() is None:os.killpg(proc.pid,signal.SIGKILL)
  proc.wait(timeout=2)
 print("RETAINED_PRIVATE_NATIVE_FIXTURE "+str(home),file=sys.stderr)
