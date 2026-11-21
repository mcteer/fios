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
assert mode in [None,"--expected-instance","--exact-target","--startup","--startup-26113","--correlation","--activity","--retirement","--preparation","--pristine-preparation","--background-sealed","--route-guards","--route-legacy"]
check_route_legacy=mode=="--route-legacy"
check_route_guards=mode in ["--route-guards","--route-legacy"]
route_guard_records=[]
check_background_sealed=mode=="--background-sealed"
check_instance=mode in ["--expected-instance","--exact-target","--correlation","--retirement","--preparation","--pristine-preparation"]
check_target=mode in ["--exact-target","--correlation","--retirement","--preparation","--pristine-preparation"]
check_correlation=mode in ["--correlation","--retirement"]
check_retirement=mode=="--retirement"
startup_version={"--startup":b"26.11.2-fios-source-fixture","--startup-26113":b"26.11.3-fios-source-fixture"}.get(mode)
check_startup=startup_version is not None
check_activity=mode=="--activity"
check_preparation=mode in ["--preparation","--pristine-preparation"]
check_pristine=mode=="--pristine-preparation"
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
default_denial=None
if check_background_sealed:
 probe_home=pathlib.Path(tempfile.mkdtemp(prefix="f9-sealed-default-",dir="/private/tmp"));probe_models=probe_home/"empty-models";probe_models.mkdir(mode=0o700)
 probe_env={**env,"HOME":str(probe_home),"XDG_CACHE_HOME":str(probe_home/"cache")}
 probe_log=os.open(probe_home/"native.log",os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
 probe=subprocess.Popen([str(binary),"serve","--host","127.0.0.1","--port",str(port),"--model-dir",str(probe_models),"--no-warmup-eager"],cwd=probe_home,env=probe_env,stdout=probe_log,stderr=probe_log,start_new_session=True);os.close(probe_log)
 try:
  try:probe.wait(timeout=5)
  except subprocess.TimeoutExpired:raise AssertionError("SEALED_SOURCE_DEFAULT_REFRESH_NOT_REFUSED")
  text=(probe_home/"native.log").read_bytes();assert len(text)<=65536
  assert probe.returncode != 0 and b"Untracked SDK background participant refused" in text,"SEALED_SOURCE_DEFAULT_REFUSAL_MISMATCH"
  default_denial={"private_home":str(probe_home),"exit":probe.returncode,"configuration":"existing_default_unmodified","inference_started":False}
 finally:
  if probe.poll() is None:os.killpg(probe.pid,signal.SIGKILL)
  probe.wait(timeout=2)
 # This explicit test-only child configuration changes no installed setting.
 env["MLX_METAL_RESIDENCY_REFRESH_INTERVAL_MS"]="0"
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
 if check_background_sealed:
  def background_snapshot(version, epoch):
   background=bytearray(32);background[:4]=b"FIB9";background[4]=version;background[8:24]=epoch
   channel=socket.socket(socket.AF_UNIX);channel.settimeout(2)
   try:
    channel.connect(str(control));channel.sendall(background);channel.shutdown(socket.SHUT_WR)
    reply=b""
    while len(reply)<64:
     part=channel.recv(64-len(reply));assert part;reply+=part
    assert channel.recv(1)==b"","SEALED_SOURCE_BACKGROUND_TRAILING_BYTES"
    return reply
   finally:channel.close()
  epoch=bytes.fromhex(instance)
  reply=background_snapshot(3,epoch)
  assert reply[:6]==b"FIF9"+bytes([3,0]) and reply[8:24]==epoch,"SEALED_SOURCE_BACKGROUND_FRAME_MISMATCH"
  assert reply[40]==1 and reply[41:]==bytes(23),"SEALED_SOURCE_BACKGROUND_NOT_EXCLUDED"
  assert reply[7]==0,"SEALED_SOURCE_CLEANUP_UNCERTAINTY"
  legacy=background_snapshot(2,epoch)
  assert legacy[:8]==b"FIF9"+bytes([2,0])+reply[6:8] and legacy[8:24]==epoch,"SEALED_SOURCE_BACKGROUND_CHANGED_V2"
  assert legacy[40:]==bytes(24),"SEALED_SOURCE_BACKGROUND_V2_RESERVED_BYTES"
  wrong_epoch=bytes([epoch[0]^1])+epoch[1:]
  refused=background_snapshot(3,wrong_epoch)
  assert refused[:8]==b"FIF9"+bytes([3,3,0,0]) and refused[8:24]==epoch,"SEALED_SOURCE_BACKGROUND_WRONG_EPOCH_ACCEPTED"
  assert refused[40:]==bytes(24),"SEALED_SOURCE_BACKGROUND_REFUSAL_PUBLISHED_READING"
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
 if check_activity:
  previous=0
  for _ in range(2):
   status,data=get("/v1/fios/activity")
   assert status==200,"CURRENT_NATIVE_ACTIVITY_INTERFACE_MISSING"
   activity=json.loads(data)
   assert set(activity)=={"schema_version","coverage","reason","observer_included","source_instance","admissions_closed","sequence","sample_sequence","uncertain","owned_requests","ingress","preparing","active","responding"}
   assert activity["schema_version"]==1 and activity["coverage"]=="unknown" and activity["reason"]=="native_ownership_audit_incomplete"
   assert activity["observer_included"] is True and activity["source_instance"]==instance
   assert type(activity["admissions_closed"]) is bool and type(activity["uncertain"]) is bool
   assert type(activity["sequence"]) is int and activity["sequence"]>0
   assert type(activity["sample_sequence"]) is int and previous<activity["sample_sequence"]<=9007199254740991
   previous=activity["sample_sequence"]
   assert all(type(activity[key]) is int and 0<=activity[key]<=256 for key in ["owned_requests","ingress","preparing","active","responding"])
   assert 1<=activity["owned_requests"]==sum(activity[key] for key in ["ingress","preparing","active","responding"])
 if check_startup:
  # Metadata-only calls remain available while the original process owns
  # the reservation; these do not enter serving or load a model.
  version=subprocess.run([str(binary),"--version"],cwd=home,env=env,capture_output=True,timeout=3)
  assert version.returncode==0 and startup_version in version.stdout,"CURRENT_NATIVE_METADATA_VERSION_BLOCKED"
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
   duplicate_log=(home/"second-native.log").read_bytes()
   assert result!=0 and b"StartupGuardUnavailable" in duplicate_log,"CURRENT_NATIVE_DUPLICATE_NOT_REFUSED_BY_RESERVATION"
   original_log=(home/"native.log").read_bytes()
   for marker in [b"Metal GPU:",b"Server listening on"]:
    assert marker in original_log,"CURRENT_NATIVE_STARTUP_MARKER_CONTROL_MISSING"
    assert marker not in duplicate_log,"CURRENT_NATIVE_DUPLICATE_REACHED_BACKEND_OR_LISTENER"
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
 if check_route_guards:
  # All targets are deliberately absent from the private empty registry. These
  # are refusal POSTs, not model competence or all-client completion evidence.
  routes=["/v1/chat/completions","/v1/completions","/v1/responses","/v1/embeddings",
          "/v1/images/generations","/v1/images/edits","/v1/audio/speech",
          "/v1/audio/transcriptions","/v1/audio/music-generations","/v1/audio/sound-generations",
          "/v1/video/generations","/v1/3d/generations"]
  wrong=("0" if instance[0]!="0" else "1")+instance[1:]
  for route in routes:
   payload=json.dumps({"model":"fixture/missing-model","messages":[],"input":"fixture","prompt":"fixture","max_tokens":1})
   for label,epoch,expected_result in ([] if check_route_legacy else [("stale-instance",wrong,(409,"native_instance_changed")),
                                       ("absent-target",instance,(404,"native_target_not_found"))]):
    connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
    try:
     connection.request("POST",route,payload,{"Content-Type":"application/json","X-Fios-Native-Instance":epoch})
     response=connection.getresponse();data=response.read(65537);assert len(data)<=65536
     actual=(response.status,json.loads(data)["error"]["type"])
     supported=route=="/v1/chat/completions"
     expected_result=expected_result if supported else (400,"invalid_native_identity_route")
     assert actual==expected_result,(route,label,actual)
     route_guard_records.append({"path":route,"case":label,"status":actual[0],"error_type":actual[1]})
    finally:connection.close()
   if not check_route_legacy and route!="/v1/chat/completions":
    for header in ["X-Fios-Request-ID","X-Fios-Handoff-Root"]:
     connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
     try:
      value="a"*64 if header=="X-Fios-Request-ID" else "1"
      connection.request("POST",route,payload,{"Content-Type":"application/json",header:value})
      response=connection.getresponse();data=response.read(65537);assert len(data)<=65536
      actual=(response.status,json.loads(data)["error"]["type"])
      assert actual==(400,"invalid_native_identity_route"),(route,header,actual)
      route_guard_records.append({"path":route,"case":header,"status":actual[0],"error_type":actual[1]})
     finally:connection.close()
   connection=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
   try:
    connection.request("POST",route,payload,{"Content-Type":"application/json"})
    response=connection.getresponse();data=response.read(65537);assert len(data)<=65536
    assert response.status==503 and json.loads(data)["error"]["type"]=="no_model",(route,response.status)
    route_guard_records.append({"path":route,"case":"ordinary-unbound-empty-catalog","status":503,"error_type":"no_model"})
   finally:connection.close()
  assert len(route_guard_records)==(12 if check_route_legacy else 58)
  status,catalog=get("/v1/models");assert status==200 and json.loads(catalog)["data"]==[]
  end=time.monotonic()+2
  while time.monotonic()<end:
   current,counter=snapshot()
   if current[0]==0:break
   time.sleep(.025)
  assert current[0]==0 and current[5]==0,"ROUTE_REFUSAL_RETAINED_LOCAL_OWNER_OR_MUTATION"
  # Local HTTP-reference cleanup only, never independent native terminality.
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
    if check_retirement:
     # Controlled empty fixture has exactly one sequential HTTP caller. This
     # predicts its next local token solely to exercise history wiring; an
     # aggregate counter is NOT a production per-request/native proof.
     code,activity_body=get("/v1/fios/activity");assert code==200
     controlled_root=json.loads(activity_body)["sequence"]+1
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
    if check_retirement:
     query=bytearray(64);query[:4]=b"FIE9";query[4]=1;query[8:56]=lineage_request[8:56];query[56:64]=struct.pack(">Q",controlled_root)
     client=socket.socket(socket.AF_UNIX);client.settimeout(2);client.connect(str(control));client.sendall(query);client.shutdown(socket.SHUT_WR);retired=b""
     try:
      while len(retired)<88:
       part=client.recv(88-len(retired));assert part;retired+=part
      assert client.recv(1)==b""
     finally:client.close()
     assert retired[:8]==b"FIZ9"+bytes([1,0,1,0]),"CURRENT_NATIVE_LOCAL_RETIREMENT_RECORD_MISSING"
     assert retired[8:56]==query[8:56] and retired[64:72]==query[56:64] and retired[80:88]==bytes(8)
     assert struct.unpack(">Q",retired[56:64])[0]>struct.unpack(">Q",lineage[56:64])[0] and struct.unpack(">Q",retired[72:80])[0]>0


  else:
   assert legacy==matching and legacy[0]>=400,"CURRENT_NATIVE_MATCHING_EPOCH_CHANGED_LEGACY_SELECTION"
 if check_preparation:
  # Actual empty-native surface only: no advertised model can execute.
  preparation=bytearray(1104);preparation[:4]=b"FIP9";preparation[4]=1;preparation[5]=1
  preparation[8:24]=bytes.fromhex(instance);preparation[24:56]=bytes([0xcc])*32
  target=b"fixture/missing-model";preparation[64:66]=struct.pack(">H",len(target));preparation[68:72]=struct.pack(">I",5000);preparation[80:80+len(target)]=target
  def preparation_exchange(payload):
   channel=socket.socket(socket.AF_UNIX);channel.settimeout(2);channel.connect(str(control));channel.sendall(payload);channel.shutdown(socket.SHUT_WR);result=b""
   try:
    while len(result)<88:
     part=channel.recv(88-len(result));assert part;result+=part
    assert channel.recv(1)==b""
   finally:channel.close()
   return result
  refused=preparation_exchange(preparation)
  assert refused[:8]==b"FIV9"+bytes([1,2,1,0]) and refused[8:]==bytes(80),"CURRENT_NATIVE_PREPARATION_UNSUPPORTED_SOURCE_GRANTED"
  preparation[5]=2;preparation[56:64]=bytes([255])*8;preparation[68:72]=bytes(4)
  withdrawn=preparation_exchange(preparation)
  assert withdrawn[:8]==b"FIV9"+bytes([1,2,2,0]) and withdrawn[8:]==bytes(80),"CURRENT_NATIVE_UNKNOWN_PREPARATION_WITHDRAWN"
  if check_pristine:
   preparation[4]=2;preparation[5]=3
   closed=preparation_exchange(preparation)
   assert closed[:8]==b"FIV9"+bytes([2,2,3,0]) and closed[8:]==bytes(80),"CURRENT_NATIVE_UNKNOWN_PRISTINE_PREPARATION_CLOSED"
   for version,operation in [(1,3),(2,1),(2,2)]:
    preparation[4]=version;preparation[5]=operation
    mixed=preparation_exchange(preparation)
    assert mixed[:4]==b"FIV9" and mixed[5]==1 and mixed[8:]==bytes(80),"CURRENT_NATIVE_MIXED_PRISTINE_OPERATION_ACCEPTED"
  def preparation_post(path,headers):
   channel=http.client.HTTPConnection("127.0.0.1",port,timeout=2)
   try:
    channel.request("POST",path,body,{"Content-Type":"application/json",**headers})
    result=channel.getresponse();payload=result.read(65537);assert len(payload)<=65536
    return result.status,json.loads(payload)["error"]["type"]
   finally:channel.close()
  bound={"X-Fios-Native-Instance":instance,"X-Fios-Request-ID":"d"*64,"X-Fios-Preparation-Root":str(2**64-1)}
  assert preparation_post("/v1/chat/completions",{"X-Fios-Preparation-Root":str(2**64-1)})==(400,"invalid_preparation_identity"),"CURRENT_NATIVE_PREPARATION_IDENTITY_NOT_REQUIRED"
  assert preparation_post("/v1/chat/completions",{**bound,"X-Fios-Handoff-Root":"7"})==(400,"invalid_preparation_identity"),"CURRENT_NATIVE_PREPARATION_HANDOFF_FALLBACK_ALLOWED"
  assert preparation_post("/v1/load-model",bound)==(400,"invalid_preparation_route"),"CURRENT_NATIVE_PREPARATION_ADMIN_ROUTE_ALLOWED"
  assert preparation_post("/v1/chat/completions",bound)==(404,"native_target_not_found"),"CURRENT_NATIVE_PREPARATION_UNREGISTERED_TARGET_ALLOWED"
  end=time.monotonic()+2
  while time.monotonic()<end:
   current,_=snapshot()
   if current[0]==0:break
   time.sleep(.025)
  assert current[0]==0,"CURRENT_NATIVE_REJECTED_PREPARATION_HTTP_OWNER_RETAINED"
 receipt={"route_guard_records":route_guard_records,"guarded_refusal_posts":len(route_guard_records),"binary_sha256":hashlib.sha256(binary.read_bytes()).hexdigest(),"native_pid":proc.pid,"source_instance":instance,"source_sequence":sequence,"source_sampled_at":stamp,"http_connection_counts":list(counts),"accepted_connection_observed":True,"original_http_connection_retired":True,"private_home":str(home),"models":0,"model_requests":(9 if check_correlation else (7 if check_target else (3 if check_instance else 0)))+(4 if check_preparation else 0)+len(route_guard_records),"preparation_control_refused":check_preparation,"pristine_preparation_control_refused":check_pristine,"preparation_http_guards_checked":check_preparation,"expected_instance_guard_checked":check_instance,"exact_target_guard_checked":check_target,"correlation_header_checked":check_correlation,"retired_lineage_is_unknown":check_correlation,"local_retirement_record_checked":check_retirement,"http_activity_checked":check_activity,"startup_reservation_checked":check_startup,"startup_reacquired_after_original_exit":check_startup,"metadata_available_while_reserved":check_startup,"inference_started":False,"coverage":"unknown","native_admission_authority":False,"peer_authentication_proven":False,"installed":False}
 if check_background_sealed:
  receipt.update({"explicit_private_background_exclusion":True,"default_refresh_startup_refused":default_denial,
      "test_child_refresh_interval_ms":0,"source_background_untracked":False,"all_client_coverage":False,
      "backend_frame_v2_reserved_preserved":True,"backend_frame_v3_wrong_epoch_refused":True,
      "configuration_scope":"private_child_only_not_installed_model_policy"})
 (home/"receipt.json").write_text(json.dumps(receipt,indent=2)+"\n");print(json.dumps(receipt))
finally:
 if proc.poll() is None:proc.terminate()
 try:proc.wait(timeout=5)
 except subprocess.TimeoutExpired:
  if proc.poll() is None:os.killpg(proc.pid,signal.SIGKILL)
  proc.wait(timeout=2)
 print("RETAINED_PRIVATE_NATIVE_FIXTURE "+str(home),file=sys.stderr)
