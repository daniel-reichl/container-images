FROM mcr.microsoft.com/devcontainers/base:debian

# Copy start-chrome.sh to a stable system path
COPY start-chrome.sh /usr/local/bin/start-chrome
RUN chmod +x /usr/local/bin/start-chrome

# Install dotenvx and task
COPY install-tools.sh /tmp/install-tools.sh
RUN sh /tmp/install-tools.sh dotenvx task && rm /tmp/install-tools.sh

# Install Claude Code CLI and configure shell for the vscode user
USER vscode
RUN curl -fsSL https://claude.ai/install.sh | bash && \
  mkdir -p ~/.local/bin && \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
