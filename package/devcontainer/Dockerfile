FROM mcr.microsoft.com/devcontainers/base:debian

LABEL org.opencontainers.image.description="Development container with Go, Node.js + pnpm, Python + uv"

COPY start-chrome.sh /usr/local/bin/start-chrome
COPY install-tools.sh /tmp/install-tools.sh

RUN \
  apt-get update && \
  # PostgreSQL client
  apt-get install -y --no-install-recommends postgresql-client && \
  # Clean up apt cache
  apt-get clean && rm -rf /var/lib/apt/lists/* && \
  # Install additional tools
  sh /tmp/install-tools.sh caddy dotenvx task uv && rm /tmp/install-tools.sh && \
  # Setup Chrome
  chmod +x /usr/local/bin/start-chrome

ENV JAVA_HOME=/usr/lib/jvm/default-java
ENV PATH=/opt/oracle/sqlcl/bin:${PATH}

USER vscode
RUN \
  # Claude Code
  curl -fsSL https://claude.ai/install.sh | bash && \
  # Codex
  curl -fsSL https://github.com/openai/codex/releases/latest/download/install.sh | bash && \
  # Shell Configuration
  mkdir -p ~/.local/bin && \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && \
  echo "alias cc='claude --dangerously-skip-permissions'" >> ~/.bashrc && \
  echo "alias cx='codex --yolo'" >> ~/.bashrc
