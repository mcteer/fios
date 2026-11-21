# Producer requires an independently reviewed, already-cached immutable ID.
# No runtime build/pull, package install or network-enabled build step.
ARG APPROVED_BASE
FROM ${APPROVED_BASE} AS reviewed_python
# The runner requires only the pinned standalone Python standard library.
# Relocate that runtime to the existing entry-point prefix, independently of
# the application virtual environment. Keep the fresh image configuration.
FROM scratch
COPY --from=reviewed_python /opt/python/cpython-3.11.17-linux-aarch64-gnu /opt/venv
COPY --from=reviewed_python /usr/lib /usr/lib
COPY --from=reviewed_python /lib /lib
# Fixed unprivileged VM metadata reader; no general shell/tool distribution.
COPY --from=reviewed_python /bin/cat /bin/cat
ENV PATH=/opt/venv/bin:/usr/bin:/bin LANG=C LC_ALL=C PYTHONDONTWRITEBYTECODE=1
WORKDIR /workspace
COPY runner.py /runner.py
USER 65532:65532
ENTRYPOINT ["/opt/venv/bin/python", "-I", "-B", "/runner.py"]
