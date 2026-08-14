# Agent Notes: lunet-mcp-sse

This repository consumes the official Lunet runtime as a pinned binary release (`v0.9.2`) via the vendored fetcher script (`scripts/lunet_fetch_release_v0.9.2.lua`).

## Rules & Workflow

- Do not use or write to a sibling checkout like `../lunet`.
- If Lunet needs changes: open a PR in `lua-lunet/lunet` first.
- The Lunet runtime is consumed as a pinned binary release (`v0.9.2`), not built from source or submodules.
- How to bump version:
  1. Update the pinned version in `Makefile`.
  2. Update/vendor the upstream fetcher script (`scripts/lunet_fetch_release_v<version>.lua`) from the upstream release assets.
- Build and editor artifacts:
  - `.lunet/` (runtime binaries and shared libraries) and `types/` (LuaCATS/Teal type definitions) are downloaded on demand via `make build` / the fetcher script.
  - `.lunet/` and `types/` MUST NEVER be committed to version control.

