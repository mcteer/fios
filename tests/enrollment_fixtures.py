"""Generate disposable PKI. Never use these credentials outside tests."""

import os
from pathlib import Path
import shutil
import subprocess

OPENSSL = Path(os.environ.get("FIOS_OPENSSL") or shutil.which("openssl")).resolve()


class Signer:
    def __init__(self, root, name):
        self.root = root
        self.name = name
        self.run("req", "-x509", "-newkey", "ec",
                           "-pkeyopt", "ec_paramgen_curve:prime256v1", "-noenc",
                           "-subj", f"/CN={name}", "-days", "2", "-addext",
                           "basicConstraints=critical,CA:TRUE,pathlen:0", "-addext",
                           "keyUsage=critical,keyCertSign,cRLSign", "-keyout", self.path("ca.key"),
                           "-out", self.path("ca.crt"))
        self.ca = self.path("ca.crt")

    def path(self, name):
        return self.root / f"{self.name}-{name}"

    def run(self, *args):
        return subprocess.run([OPENSSL, *args], check=True, capture_output=True, timeout=5)

    def issue(self, label, *, san=None, server=False, days=1):
        key, csr, cert, extensions = (self.path(f"{label}.{suffix}")
                                       for suffix in ("key", "csr", "crt", "ext"))
        self.run("req", "-new", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1",
                 "-noenc", "-subj", f"/CN={label}", "-keyout", key, "-out", csr)
        key.chmod(0o600)
        purpose = "serverAuth" if server else "clientAuth"
        extensions.write_text("basicConstraints=critical,CA:FALSE\n"
                              "keyUsage=critical,digitalSignature\n"
                              f"extendedKeyUsage={purpose}\n"
                              f"subjectAltName={san or 'DNS:' + label}\n"
                              "subjectKeyIdentifier=hash\n"
                              "authorityKeyIdentifier=keyid\n")
        if days < 0:
            config, index, serial = (self.path(name) for name in ("ca.cnf", "index", "serial"))
            index.write_text("")
            serial.write_text("AB00\n")
            config.write_text(f"[ca]\ndefault_ca=signer\n[signer]\ndatabase={index}\n"
                              f"serial={serial}\nnew_certs_dir={self.root}\n"
                              "default_md=sha256\npolicy=leaf\n[leaf]\ncommonName=supplied\n")
            self.run("ca", "-batch", "-notext", "-config", config, "-in", csr, "-cert", self.ca,
                     "-keyfile", self.path("ca.key"), "-startdate", "20010101000000Z",
                     "-enddate", "20010102000000Z", "-extfile", extensions, "-out", cert)
        else:
            self.run("x509", "-req", "-in", csr, "-CA", self.ca,
                     "-CAkey", self.path("ca.key"), "-CAcreateserial", "-days", str(days),
                     "-extfile", extensions, "-out", cert)
        return cert, key
