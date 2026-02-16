-- lunet-mcp-sse: MCP SSE server built on Lunet
-- Build system: xmake (delegates to deps/lunet for native targets)
--
-- Usage:
--   git submodule update --init --recursive
--   xmake lunet-build
--   xmake lunet-run
--
-- See also: https://github.com/lua-lunet/lunet/blob/main/docs/XMAKE_INTEGRATION.md

set_project("lunet-mcp-sse")
set_version("0.1.0")

-- ============================================================================
-- Configuration
-- ============================================================================

local lunet_dir = "deps/lunet"

-- ============================================================================
-- Helpers
-- ============================================================================

local function quote(s)
    return "\"" .. tostring(s):gsub("\"", "\\\"") .. "\""
end

local function xmake_in_lunet(cmd)
    os.exec("cd " .. quote(lunet_dir) .. " && " .. cmd)
end

local function runner_path(mode)
    local name = is_host("windows") and "lunet-run.exe" or "lunet-run"
    local matches = os.files(path.join(lunet_dir, "build/**/" .. mode .. "/" .. name))
    if #matches == 0 then
        raise("lunet-run not found for mode: " .. mode .. ". Run: xmake lunet-build")
    end
    return matches[1]
end

local function lunet_module_dir(mode)
    local dirs = os.dirs(path.join(lunet_dir, "build/**/" .. mode .. "/lunet"))
    if #dirs > 0 then return dirs[1] end
    return nil
end

-- ============================================================================
-- Tasks
-- ============================================================================

task("lunet-build")
    set_menu {
        usage = "xmake lunet-build",
        description = "Build Lunet runtime + modules from deps/lunet"
    }
    on_run(function ()
        local p = "-P " .. quote(lunet_dir)
        os.runv("xmake", {"f", "-P", lunet_dir, "-m", "release", "--lunet_trace=n", "--lunet_verbose_trace=n", "-y"})
        os.runv("xmake", {"build", "-P", lunet_dir, "lunet-bin"})
        os.runv("xmake", {"build", "-P", lunet_dir, "lunet-sqlite3"})
        os.runv("xmake", {"build", "-P", lunet_dir, "lunet-httpc"})
        local runner = runner_path("release")
        cprint("${green}Build complete.${clear} Runner: " .. runner)
    end)
task_end()

task("lunet-run")
    set_menu {
        usage = "xmake lunet-run [--trace=LEVEL] [--port=PORT]",
        description = "Start the MCP server",
        options = {
            {nil, "trace", "kv", nil, "MCP trace level (off/error/warn/info/debug/trace)"},
            {nil, "port",  "kv", nil, "Server port (default 8080)"},
        }
    }
    on_run(function ()
        import("core.base.option")
        local runner = runner_path("release")
        local cmd = quote(runner) .. " app/main.lua"
        local env_prefix = ""
        if option.get("trace") then env_prefix = env_prefix .. "MCP_TRACE=" .. option.get("trace") .. " " end
        if option.get("port") then env_prefix = env_prefix .. "PORT=" .. option.get("port") .. " " end
        os.run(env_prefix .. cmd)
    end)
task_end()

task("lunet-test")
    set_menu {
        usage = "xmake lunet-test",
        description = "Test server endpoints (server must be running)"
    }
    on_run(function ()
        print("Testing server info endpoint...")
        os.exec("curl -s --max-time 5 http://localhost:8080/ || echo 'ERROR: Server not responding'")
        print("")
        print("Testing SSE endpoint (3 seconds)...")
        os.exec("curl -sN --max-time 3 http://localhost:8080/sse || true")
        print("")
    end)
task_end()

task("lunet-stress")
    set_menu {
        usage = "xmake lunet-stress",
        description = "Run Lua stress test (server must be running)"
    }
    on_run(function ()
        local runner = runner_path("release")
        if is_host("windows") then
            os.execv(runner, {"test/stress_mcp.lua"})
        else
            os.execv("bash", {"-lc", "timeout 60 " .. quote(runner) .. " test/stress_mcp.lua || echo 'Stress test timed out or failed'"})
        end
    end)
task_end()

task("lunet-bench")
    set_menu {
        usage = "xmake lunet-bench",
        description = "Run Lua memory benchmark"
    }
    on_run(function ()
        local runner = runner_path("release")
        if is_host("windows") then
            os.execv(runner, {"test/bench_memory.lua"})
        else
            os.execv("bash", {"-lc", "timeout 30 " .. quote(runner) .. " test/bench_memory.lua || echo 'Benchmark timed out or failed'"})
        end
    end)
task_end()

task("lunet-bench-heavy")
    set_menu {
        usage = "xmake lunet-bench-heavy",
        description = "Run Lua memory benchmark with more clients"
    }
    on_run(function ()
        local runner = runner_path("release")
        if is_host("windows") then
            os.execv(runner, {"test/bench_memory.lua"}, {envs = {BENCH_CLIENTS = "100", BENCH_REQUESTS = "50"}})
        else
            os.execv("bash", {"-lc", "BENCH_CLIENTS=100 BENCH_REQUESTS=50 timeout 60 " .. quote(runner) .. " test/bench_memory.lua || echo 'Heavy benchmark timed out or failed'"})
        end
    end)
task_end()

task("lunet-smoke")
    set_menu {
        usage = "xmake lunet-smoke",
        description = "Run httpc smoke test (HTTPS GET to example.com)"
    }
    on_run(function ()
        local runner = runner_path("release")
        os.execv(runner, {".tmp/httpc_smoke.lua"})
    end)
task_end()

task("lunet-package")
    set_menu {
        usage = "xmake lunet-package",
        description = "Package dist/ directory for release"
    }
    on_run(function ()
        local runner = runner_path("release")
        local moddir = lunet_module_dir("release")

        os.mkdir("dist/bin")
        os.mkdir("dist/lib")
        os.mkdir("dist/app")
        os.mkdir("dist/test")

        os.cp(runner, "dist/bin/lunet" .. (is_host("windows") and ".exe" or ""))

        if moddir then
            local ext = is_host("windows") and "*.dll" or "*.so"
            local libs = os.files(path.join(moddir, ext))
            for _, f in ipairs(libs) do os.cp(f, "dist/lib/") end
        end

        local lunet_so = os.files(path.join(lunet_dir, "build/**/release/lunet" .. (is_host("windows") and ".dll" or ".so")))
        if #lunet_so > 0 then os.cp(lunet_so[1], "dist/lib/") end

        os.cp("app/*", "dist/app/")
        os.cp("test/*", "dist/test/")
        os.cp("Makefile", "dist/")
        os.cp("README.md", "dist/")
        if os.isfile("lunet-mcp-sse-scm-1.rockspec") then
            os.cp("lunet-mcp-sse-scm-1.rockspec", "dist/")
        end

        if is_host("windows") then
            os.exec("cd dist && 7z a ../lunet-mcp-sse-windows-amd64.zip .")
        else
            local f = io.open("dist/run.sh", "w")
            f:write('#!/bin/bash\n')
            f:write('SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"\n')
            f:write('export LUA_CPATH="$SCRIPT_DIR/lib/?.so;;"\n')
            f:write('exec "$SCRIPT_DIR/bin/lunet" "$SCRIPT_DIR/app/main.lua" "$@"\n')
            f:close()
            os.exec("chmod +x dist/run.sh")
        end

        cprint("${green}Package complete.${clear} Output: dist/")
    end)
task_end()
