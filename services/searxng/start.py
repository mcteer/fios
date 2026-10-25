"""Nonroot bootstrap; no persistent secret, config mutation or query logging."""
import logging
import os
import secrets
import sys

logging.disable(logging.CRITICAL)
# Granian loads the image's packaged SearXNG source. No host source is mounted.
sys.path.insert(0,'/usr/local/searxng')
if __name__=='__main__':
    from granian import cli
    os.environ['SEARXNG_SECRET']=secrets.token_hex(32)
    sys.argv=['granian','--no-access-log','searx.webapp:app']
    cli.entrypoint()
