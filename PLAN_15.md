# Implementation Plan - Issue #15

## Upgrade to Lunet v0.9.2 and Switch to Binary Release Consumption

### 1. Overview & Goals
The objective is to migrate `lunet-mcp-sse` from building the Lunet framework from source via a git submodule (`deps/lunet`) and `xmake` to consuming official upstream pre-built binary release archives (`v0.9.2`). This simplifies downstream development, eliminates compilation toolchain requirements (`xmake`, C compilers), and provides out-of-the-box editor navigation via LuaCATS / Teal type definitions.

### 2. Architecture & Design
- **Binary Runtime Layout**:
  - Downloaded release artifacts reside in `.lunet/` (ignored by git).
  - Executable runner: `.lunet/bin/lunet-run` (or `.lunet/lunet-run`).
  - Runtime shared libraries: `lunet.so` / `lunet.dylib` / `lunet.dll` and `lunet/httpc.so`.
  - Type definitions: Extracted to `types/` for editor autocomplete and diagnostics.
- **Release Fetcher**:
  - Vendored script: `scripts/lunet_fetch_release_v0.9.2.lua`.
  - Driven by host `lua` (Lua 5.1+ or LuaJIT) using standard curl / tar / unzip system utilities.
  - Downloads platform-specific tarball/zip from `lua-lunet/lunet` GitHub releases.
- **Editor & IDE Integration**:
  - `.luarc.json` configured with `workspace.library = ["types"]` for LuaCATS and Teal editor navigation.

### 3. Migration Strategy & Components

#### A. Release Fetcher Integration
- Vendor `scripts/lunet_fetch_release_v0.9.2.lua`.
- Support target directory `.lunet/` and extraction of `types/`.

#### B. Build & Execution Tooling (Makefile, Scripts)
- Update `Makefile`:
  - Target `build` / `fetch`: Invokes release fetcher to populate `.lunet/`.
  - Target `run`: Executes `app/main.lua` via `.lunet/bin/lunet-run`.
  - Target `clean-all`: Cleans `.lunet/` and `types/` alongside temporary logs.
  - Remove all xmake and submodule invocations.
- Update helper scripts (`run.sh`, `scripts/lunet_bin.sh`).

#### C. Submodule and xmake Removal
- Drop `deps/lunet` submodule from `.gitmodules` and git index.
- Drop `.xmake/` and any xmake project references.

#### D. Containerization (Dockerfile)
- Update `Dockerfile` to install runtime system libraries (`libuv1`, `libluajit-5.1-2`, `libcurl4`, `zlib1g`).
- Download or copy binary runtime `lunet-run` and shared libraries.

#### E. Continuous Integration (.github/workflows/ci.yml)
- Simplify CI workflow by removing submodule initialization and xmake build steps.
- Run fetcher script to retrieve `v0.9.2` binaries and run tests on Linux/macOS.

#### F. Test Verification
- Verify `test/stress_mcp.lua` and `test/bench_memory.lua` under `lunet-run`.
- Verify SSE streaming and Tavily tool integration.

### 4. Verification Loop
1. Run fetcher: `make build` (downloads v0.9.2 release artifacts to `.lunet/`).
2. Start server: `make run` or `.lunet/bin/lunet-run app/main.lua`.
3. Verify endpoints:
   - Server info: `curl -s http://localhost:8080/`
   - SSE connection: `curl -sN http://localhost:8080/sse`
4. Run stress & benchmark tests:
   - `make stress`
   - `make bench`
5. Verify Docker image build and execution.
