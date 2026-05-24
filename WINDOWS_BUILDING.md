# Building kRPC on Windows

kRPC is built exclusively through the `buildenv` Docker image. There is no longer a separate WSL +
Mono + apt setup procedure for Windows — Docker Desktop is the only supported path.

## Prerequisites

1. Install [Docker Desktop](https://www.docker.com/products/docker-desktop/) for Windows. The WSL 2
   backend is recommended.
2. Clone this repository to a folder of your choice, for example `C:\Dev\krpc`.

## Build

From PowerShell, in the repository root:

```powershell
# Option A — pull the published image
docker pull ghcr.io/thecandianvendingmachine/krpc-buildenv:latest 
docker run --rm -it -v "${PWD}:/build/krpc" -w /build/krpc ghcr.io/thecandianvendingmachine/krpc-buildenv:latest bash

# Option B — build the image locally from the Dockerfile in this repo
docker build -t krpc-buildenv .
docker run --rm -it -v "${PWD}:/build/krpc" -w /build/krpc krpc-buildenv bash
```

Note: the `"${PWD}:/build/krpc"` argument **must** be quoted as a single string. Without the outer
quotes, PowerShell mis-tokenizes the colon between the Windows drive path and the container
target, and `docker run` errors with `invalid reference format`.

Inside the container:

```bash
bazel build //...
bazel test //:test
```

The `lib/ksp` (KSP stub DLLs) and `lib/mono-4.5` symlinks expected by the build are already set up
inside the image, so no Windows-side symlinking or admin command prompt is needed.

## Build output on the Windows host

Because the repository is bind-mounted into the container, Bazel's `bazel-bin`, `bazel-out` and
`bazel-testlogs` symlinks appear in your Windows working copy as soon as the build completes. Open
them from Windows directly — no `mklink` to `\\wsl$\...` required.

## Notes

* Do not install Bazel, Mono, Java, LaTeX, etc. on the Windows host or in WSL. The Docker image owns
  the entire toolchain.
* Visual Studio is not part of the supported build flow. Use the Docker container for compiling and
  testing; use VS only as an editor if desired.
* For full project context (code layout, tools, Bazel cheat sheet), see
  [Development-Guide.md](Development-Guide.md).
