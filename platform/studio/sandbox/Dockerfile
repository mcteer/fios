# Release producer must verify APPROVED_BASE is an already-cached, reviewed
# immutable image ID containing the locked CPython3.11.17 environment.
# No runtime build/pull is permitted. Never grant this image daemon authority.
ARG APPROVED_BASE
FROM ${APPROVED_BASE}
USER 65532:65532
WORKDIR /workspace
COPY runner.py /runner.py
ENTRYPOINT ["/opt/venv/bin/python", "-I", "-B", "/runner.py"]
