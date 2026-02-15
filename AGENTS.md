# Agent Notes: lunet-mcp-sse

This repo consumes Lunet via a repo-local git submodule at `deps/lunet`, following the official Lunet xmake integration guide:
https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md

Rules

- Do not use or write to a sibling checkout like `../lunet`.
- If Lunet needs changes: open a PR in `lua-lunet/lunet` first, then bump the `deps/lunet` submodule pointer in a separate PR here.
- Initialize deps before building: `git submodule update --init --recursive`.
