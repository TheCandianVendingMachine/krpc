# kRPC Build Environment
# Based on Ubuntu 22.04 to match expected Mono 4.5 paths (/usr/lib/mono/4.5)
FROM ubuntu:22.04

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive

# ── 1. Core system utilities ──────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    software-properties-common \
    wget \
    git \
    unzip \
    zip \
    xz-utils \
    build-essential \
    make \
    pkg-config \
  && rm -rf /var/lib/apt/lists/*

# ── 2. Mono (C# compiler, runtime and tools) ──────────────────────────────────
# Add the official Mono apt repository, as instructed in the guide
RUN curl -fsSL https://download.mono-project.com/repo/xamarin.gpg \
      | gpg --dearmor -o /usr/share/keyrings/mono-official.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/mono-official.gpg] \
      https://download.mono-project.com/repo/ubuntu stable-focal main" \
      > /etc/apt/sources.list.d/mono-official-stable.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends mono-complete \
  && rm -rf /var/lib/apt/lists/*

# ── 3. All other apt dependencies from the guide ─────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Python
    python-is-python3 \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-virtualenv \
    # Autotools
    autotools-dev \
    automake \
    autoconf \
    libtool \
    # Lua
    luarocks \
    # Java / Maven (needed for the Java client build)
    default-jdk \
    maven \
    # LaTeX / SVG (for building the documentation)
    latexmk \
    texlive-latex-base \
    texlive-latex-recommended \
    texlive-fonts-recommended \
    texlive-latex-extra \
    texlive-fonts-extra \
    tex-gyre \
    librsvg2-bin \
    # XML / XSLT (used by docgen)
    libxml2-dev \
    libxslt1-dev \
    # Spell-checking (used by Sphinx docs)
    libenchant-2-2 \
    # Test dependencies (cppcheck, socat)
    cppcheck \
    socat \
    # Misc
    libssl-dev \
  && rm -rf /var/lib/apt/lists/*

# ── 4. Bazel (via Bazelisk) ───────────────────────────────────────────────────
# Use Bazelisk so the Bazel version pinned in `.bazelversion` (currently 7.2.1)
# is fetched automatically. Installing the apt `bazel` package instead would
# require the exact `bazel-<version>` binary to already be present and would
# break every time `.bazelversion` is bumped.
ARG BAZELISK_VERSION=v1.20.0
RUN curl -fsSL -o /usr/local/bin/bazel \
      "https://github.com/bazelbuild/bazelisk/releases/download/${BAZELISK_VERSION}/bazelisk-linux-amd64" \
  && chmod +x /usr/local/bin/bazel

# ── 5. Non-root build user ───────────────────────────────────────────────────
# rules_python's hermetic interpreter refuses to run as root, so every
# subsequent Bazel step (and the default CMD) runs as a dedicated user.
#
# The user is named `runner` with UID/GID 1001 to match GitHub-hosted Ubuntu
# runners — the CI workflow uses `--user runner:runner`, and a matching UID
# means bind-mounted workspace files have correct ownership.
#
# Override the UID/GID at build time if your Linux host shell user has a
# different UID and you want bind-mounted ownership to line up:
#   docker build --build-arg USER_UID=$(id -u) --build-arg USER_GID=$(id -g) ...
ARG USER_UID=1001
ARG USER_GID=1001
RUN groupadd --gid ${USER_GID} runner \
  && useradd --uid ${USER_UID} --gid ${USER_GID} --create-home --shell /bin/bash runner \
  && mkdir -p /build \
  && chown -R runner:runner /build

# Entrypoint: recreate lib/{ksp,mono-4.5} symlinks at container start so they
# survive a bind-mount of the host repo over /build/krpc (both names are
# .gitignored, so they never live in the source tree itself).
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

USER runner

# ── 6. KSP stub DLLs ─────────────────────────────────────────────────────────
# Download the implementation-stripped KSP DLLs from the ksp-lib repo.
# These are sufficient to compile against without distributing the real game.
WORKDIR /build
RUN mkdir ksp \
  && cd ksp \
  && wget -q https://github.com/TheCandianVendingMachine/ksp-lib/raw/main/ksp/ksp-1.12.5.zip \
  && unzip -q ksp-1.12.5.zip \
  && rm ksp-1.12.5.zip

# ── 7. Clone kRPC and set up symlinks ────────────────────────────────────────
RUN git clone https://github.com/TheCandianVendingMachine/krpc.git

WORKDIR /build/krpc

RUN \
  # Point lib/ksp at the stub DLLs downloaded above
  ln -s /build/ksp lib/ksp \
  # Point lib/mono-4.5 at the system Mono installation (Ubuntu 22.04 path)
  && ln -sf /usr/lib/mono/4.5 lib/mono-4.5

# ── 8. Pre-fetch all Bazel dependencies so offline builds are possible ────────
# This layer is cached separately; re-run only when BUILD files change.
RUN bazel fetch //...

# ── 9. Default build command ──────────────────────────────────────────────────
# Builds the full release archive at bazel-out/krpc-<version>.zip
# Override CMD (or use docker run with extra args) to build a specific target.
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bazel", "build", "//..."]
