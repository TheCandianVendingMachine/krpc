#!/usr/bin/env bash
set -euo pipefail

# When the host repo is bind-mounted over /build/krpc the symlinks baked into
# the image are hidden. Re-create them on each container start so Bazel can
# find the KSP stub DLLs (lib/ksp -> /build/ksp) and the Mono libraries
# (lib/mono-4.5 -> /usr/lib/mono/4.5). Both paths are .gitignored.
if [ -d /build/krpc/lib ]; then
  [ ! -e /build/krpc/lib/ksp ]      && ln -s /build/ksp        /build/krpc/lib/ksp      || true
  [ ! -e /build/krpc/lib/mono-4.5 ] && ln -s /usr/lib/mono/4.5 /build/krpc/lib/mono-4.5 || true
fi

exec "$@"
