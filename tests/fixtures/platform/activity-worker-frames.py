"""Actual Swift export -> installed Python guard. No model or native authority."""
import json
from pathlib import Path
import sys,time,inspect
from fios_agent import platform_protocol
from fios_agent.platform_guard import GuardProfile,validate_observation,validate_preparation_observation,NativeGuardError
from fios_agent.platform_protocol import parse_platform_command

project=Path(__file__).resolve().parents[3]
for relative,loaded in [('platform_guard.py',Path(inspect.getfile(validate_observation))),('platform_protocol.py',Path(platform_protocol.__file__))]:
    assert '/site-packages/fios_agent/' in str(loaded),'Current installed package required'
    assert loaded.read_bytes()==(project/'src/agent/fios_agent'/relative).read_bytes(),'Stale installed worker source'
root=Path(sys.argv[1])
profile=GuardProfile('/fixture/observe.sock','fixture-host','b'*64,'c'*32,7,'fixture/model@studio-a','fixture/model')
command=parse_platform_command({'v':1,'type':'run','job_id':'00000000-0000-4000-8000-000000000003','attempt':0,
    'epoch':'00000000-0000-4000-8000-000000000002','model':'fixture/model','endpoint_hash':'a'*64,
    'expires_at':int(time.time()*1000)+5000,'context':[{'role':'user','content':'fixture'}]})
for name in ('idle','queued','active','responding','preparing','unknown','conflict'):
    value=json.loads((root/(name+'.json')).read_text())
    try:
        validate_observation(value,profile,command,int(time.time()*1000))
        if name in ('preparing','unknown','conflict'):raise AssertionError('Unknown Swift export became eligible')
    except NativeGuardError:
        if name not in ('preparing','unknown','conflict'):raise
print('PASS actual Swift current exports -> installed Python:4 eligible fixtures/3 preparation-or-unknown refusals; no native authority')

for offset in (-5001,-5000,1000,1001):
    value=json.loads((root/f'resource-{offset}.json').read_text())
    now=value['sampled_at']
    assert value['resources']['sampled_at']==now+offset
    try:
        validate_observation(value,profile,command,now)
    except NativeGuardError:
        assert offset in (-5001,1001),f'Valid resource age refused: {offset}'
    else:
        assert offset in (-5000,1000),f'Invalid resource age accepted: {offset}'
print('PASS Swift responding frames -> installed Python: independent resource-clock boundaries')

short_pressure=json.loads((root/'short-pressure.json').read_text())
assert short_pressure['resources']['pressure']=='unknown'
assert short_pressure['resources']['thermal']=='nominal'
validate_observation(short_pressure,profile,command,short_pressure['sampled_at'])
print('PASS short pressure sample remains unknown through activity wire; independent thermal sample retained')

preparation=json.loads((root/'preparation.json').read_text())
validate_preparation_observation(preparation,profile,command,'18446744073709551615',int(time.time()*1000))
for changes in ({'source_coverage':'unknown'},{'root_sequence':'1'},{'lease_expires_at':int(time.time()*1000)}):
    try:
        validate_preparation_observation({**preparation,**changes},profile,command,'18446744073709551615',int(time.time()*1000))
    except NativeGuardError:pass
    else:raise AssertionError('Invalid original preparation frame became eligible')
print('PASS actual checked original Swift preparation -> installed Python; scope/lease/unresolved claim retained; no native authority')
