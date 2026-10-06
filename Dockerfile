FROM ubuntu:22.04

ENV CODEFACE_SYSTEM_PYTHON=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /opt/codeface
COPY . .

# Reuse the installer; database configuration is supplied at runtime.
RUN bash install/install_codeface.sh --dependencies-only \
    && rm -rf /var/lib/apt/lists/* /root/.cache

ENTRYPOINT ["bash", "run/run.sh"]
CMD ["run"]
