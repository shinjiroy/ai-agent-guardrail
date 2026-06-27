FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    jq \
    grep \
    coreutils \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/bats-core/bats-core.git /opt/bats \
    && git clone --depth 1 https://github.com/bats-core/bats-support.git /opt/bats-support \
    && git clone --depth 1 https://github.com/bats-core/bats-assert.git /opt/bats-assert \
    && ln -s /opt/bats/bin/bats /usr/local/bin/bats

WORKDIR /workspace

COPY . /workspace

RUN chmod +x core/guardrail.sh \
    adapters/claude/pretooluse.sh \
    adapters/cursor/*.sh \
    install.sh

CMD ["bats", "--recursive", "tests/"]
