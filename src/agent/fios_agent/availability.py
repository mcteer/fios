"""Read-only readiness. Gateway peer advertisements are not health evidence."""
import asyncio
import json
import re
import time
import os
import stat
import hashlib
from urllib.parse import urlsplit
import httpx2

LIMIT = 1024 * 1024


def invalid_constant(_):
    raise ValueError('Invalid JSON.')


def endpoint(value):
    if not isinstance(value, str) or re.search(r'[\s?#]', value):
        raise ValueError('Invalid availability configuration.')
    parsed = urlsplit(value)
    if (parsed.scheme not in ('http', 'https') or not parsed.hostname or parsed.username is not None
            or parsed.password is not None or not parsed.path.rstrip('/').endswith('/v1')):
        raise ValueError('Invalid availability configuration.')
    parsed.port
    return str(httpx2.URL(value)).rstrip('/')


def peer_configuration(value='{}'):
    peers = json.loads(value or '{}')
    if not isinstance(peers, dict) or len(peers) > 16:
        raise ValueError('Invalid availability configuration.')
    for name, url in peers.items():
        if not re.fullmatch(r'[A-Za-z0-9_.-]{1,128}', name) or name == 'gateway':
            raise ValueError('Invalid availability configuration.')
        peers[name] = endpoint(url)
    return peers


def catalog(payload):
    if not isinstance(payload, dict) or not isinstance(payload.get('data'), list) or len(payload['data']) > 512:
        raise ValueError('catalog')
    seen = set()
    for model in payload['data']:
        if not isinstance(model, dict): raise ValueError('catalog')
        name = model.get('id')
        caps = model.get('capabilities', [])
        peer = model.get('lan_peer')
        if (not isinstance(name, str) or not name or len(name) > 512 or re.search(r'[\s\x00-\x1f]', name)
                or name in seen or not isinstance(caps, list) or len(caps) > 16
                or any(not isinstance(c, str) or len(c) > 64 for c in caps)
                or ('loaded' in model and type(model['loaded']) is not bool)
                or ('lan_peer' in model and (not isinstance(peer, str) or not re.fullmatch(r'[A-Za-z0-9_.-]{1,128}', peer)))):
            raise ValueError('catalog')
        seen.add(name)
    return payload['data']


def snapshot_observation(path, name, url):
    try:
        with os.fdopen(os.open(path, os.O_RDONLY | os.O_NONBLOCK | os.O_NOFOLLOW), 'rb') as source:
            if not stat.S_ISREG(os.fstat(source.fileno()).st_mode): raise ValueError('snapshot')
            body = source.read(LIMIT + 1)
        if len(body) > LIMIT: raise ValueError('snapshot')
        value = json.loads(body, parse_constant=invalid_constant)
        fingerprint = hashlib.sha256(endpoint(url).encode()).hexdigest()
        observation = next((p for p in value.get('peers', []) if p.get('name') == name and p.get('endpointHash') == fingerprint), None)
        now = int(time.time()*1000)
        if (type(value.get('v')) is not int or value.get('v') != 1 or observation is None or type(observation.get('checkedAt')) is not int
                or now-observation['checkedAt'] > 5000 or observation['checkedAt'] > now+1000
                or observation.get('status') not in ('available','unavailable','unknown')
                or observation.get('reason') not in ('ok','host_down','unauthorized','invalid_catalog','host_unverified')
                or (observation['status'] == 'available' and observation['reason'] != 'ok')):
            raise ValueError('snapshot')
        models = catalog({'data':observation.get('models')}) if observation['status'] == 'available' else []
        return {'name':name,'status':observation['status'],'reason':observation['reason'],'checkedAt':observation['checkedAt'],
                'models':models,'modelCount':sum(not m.get('lan_peer') and '@' not in m['id'] for m in models)}
    except (OSError,ValueError,TypeError,AttributeError):
        return {'name':name,'status':'unknown','reason':'host_unverified','checkedAt':int(time.time()*1000),'models':[],'modelCount':0}


async def discover(settings, *, transport=None, timeout=2):
    base = endpoint(settings.base_url)
    peers = peer_configuration(json.dumps(settings.peers))
    async with httpx2.AsyncClient(transport=transport, trust_env=False, follow_redirects=False,
                                 timeout=httpx2.Timeout(timeout)) as http:
        async def read(url, headers):
            try:
                async with http.stream('GET', url, headers=headers) as response:
                    if not 200 <= response.status_code < 300:
                        unauthorized = response.status_code in (401, 403)
                        return {'status': 'unknown' if unauthorized else 'unavailable',
                                'reason': 'unauthorized' if unauthorized else 'host_down'}
                    body = bytearray()
                    async for chunk in response.aiter_bytes():
                        if len(body) + len(chunk) > LIMIT:
                            return {'status': 'unknown', 'reason': 'invalid_catalog'}
                        body.extend(chunk)
                    try: return {'status': 'available', 'reason': 'ok', 'data': json.loads(body, parse_constant=invalid_constant)}
                    except (ValueError, UnicodeError): return {'status': 'unknown', 'reason': 'invalid_catalog'}
            except (httpx2.HTTPError, OSError):
                return {'status': 'unavailable', 'reason': 'host_down'}
        async def probe(name, url, key=''):
            headers = {'Accept-Encoding': 'identity'}
            if key and key != 'fios-local-no-key': headers['Authorization'] = 'Bearer ' + key
            # A wall-clock deadline also bounds slow trickle streams, not just socket idle reads.
            async def bounded(target):
                try: return await asyncio.wait_for(read(target, headers), timeout)
                except TimeoutError: return {'status': 'unavailable', 'reason': 'host_down'}
            health, listing = await asyncio.gather(bounded(url[:-3] + '/health'), bounded(url + '/models'))
            failure = next((r for r in (health, listing) if r['status'] != 'available'), None)
            status, reason, models = 'available', 'ok', []
            if failure: status, reason = failure['status'], failure['reason']
            elif not isinstance(health['data'], dict) or health['data'].get('status') != 'ok':
                status, reason = 'unknown', 'invalid_catalog'
            else:
                try: models = catalog(listing['data'])
                except ValueError: status, reason = 'unknown', 'invalid_catalog'
            return {'name': name, 'status': status, 'reason': reason, 'checkedAt': int(time.time()*1000),
                    'modelCount': sum(not m.get('lan_peer') and '@' not in m['id'] for m in models), 'models': models}
        async def peer_probe(name, url):
            if settings.readiness_file: return snapshot_observation(settings.readiness_file, name, url)
            return await probe(name, url)
        hosts = await asyncio.gather(probe('gateway', base, settings.api_key),
                                     *(peer_probe(name, url) for name, url in peers.items()))
    by_name = {h['name']: h for h in hosts}
    for model in hosts[0]['models']:
        peer = model.get('lan_peer')
        if peer and peer not in by_name:
            host = {'name':peer,'status':'unknown','reason':'host_unverified','checkedAt':int(time.time()*1000),'modelCount':0,'models':[]}
            hosts.append(host)
            by_name[peer] = host
    models = []
    for m in hosts[0]['models']:
        caps = m.get('capabilities', [])
        if caps and 'chat' not in caps: continue
        peer = m.get('lan_peer')
        host = peer or 'gateway'
        observation = by_name.get(host)
        availability = observation['status'] if observation else 'unknown'
        reason = observation['reason'] if observation else 'host_unverified'
        bare = m['id'][:-len(peer)-1] if peer and m['id'].endswith('@'+peer) else m['id']
        if (peer and (peer not in peers or bare == m['id'])) or (not peer and '@' in m['id']):
            availability, reason = 'unknown', 'host_unverified'
        live = next((v for v in observation['models'] if not v.get('lan_peer') and '@' not in v['id'] and v['id'] == bare), None) if peer and observation else None
        if peer and availability == 'available' and (live is None or (live.get('capabilities') and 'chat' not in live['capabilities'])):
            availability, reason = 'unavailable', 'not_advertised'
        current = live or m
        models.append({'id': m['id'], 'loaded': current.get('loaded', current.get('state') == 'ready'),
                       'capabilities': current.get('capabilities', []), 'peer': peer, 'host': host,
                       'state': current['state'] if isinstance(current.get('state'), str) and len(current['state']) < 32 else 'ready' if current.get('loaded') else 'unloaded',
                       'availability': availability, 'reason': reason})
    return {'models': models, 'hosts': [{k:v for k,v in h.items() if k != 'models'} for h in hosts],
            'checkedAt': int(time.time()*1000)}
