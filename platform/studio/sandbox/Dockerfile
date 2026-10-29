# Producer requires an independently reviewed, already-cached immutable ID.
# No runtime build/pull, package install or network-enabled build step.
ARG APPROVED_BASE
FROM ${APPROVED_BASE} AS reviewed_python
# Fresh configuration excludes inherited app env, CMD, ports, volumes and
# health actions. Copy only the baked Python environment and ELF libraries;
# no app tree, host credentials, general shell entry point or runtime socket.
FROM scratch
COPY --from=reviewed_python /opt/python /opt/python
COPY --from=reviewed_python /opt/venv /opt/venv
COPY --from=reviewed_python /usr/lib /usr/lib
COPY --from=reviewed_python /lib /lib
# Fixed unprivileged VM metadata reader; no general shell/tool distribution.
COPY --from=reviewed_python /bin/cat /bin/cat
ENV PATH=/opt/venv/bin:/usr/bin:/bin LANG=C LC_ALL=C PYTHONDONTWRITEBYTECODE=1
WORKDIR /workspace
COPY runner.py /runner.py
USER 65532:65532
ENTRYPOINT ["/opt/venv/bin/python", "-I", "-B", "/runner.py"]
