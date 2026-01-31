-- Zero-Cost Tracing Module
--
-- Provides runtime-configurable logging with zero overhead when disabled.
-- When MCP_TRACE environment variable is not set (or set to "0"/"false"),
-- all trace calls compile to empty functions via LuaJIT's dead code elimination.
--
-- Trace Levels (cumulative):
--   0/off   - No tracing (default, zero overhead)
--   1/error - Errors only
--   2/warn  - Warnings and above
--   3/info  - Informational messages and above  
--   4/debug - Debug messages and above
--   5/trace - All messages including fine-grained tracing
--
-- Environment Variables:
--   MCP_TRACE       - Trace level (0-5 or off/error/warn/info/debug/trace)
--   MCP_TRACE_FILE  - Output file (default: stderr)
--
-- Usage:
--   local trace = require("app.trace")
--   trace.info("SSE", "Session %s connected", session_id)
--   trace.debug("HTTP", "Request: %s %s", method, path)
--   trace.trace("MCP", "JSON-RPC: %s", json_encode(msg))

local M = {}

-- Parse trace level from environment
local function parse_level(val)
    if not val then return 0 end
    val = val:lower()
    if val == "off" or val == "0" or val == "false" or val == "" then return 0 end
    if val == "error" or val == "1" then return 1 end
    if val == "warn" or val == "warning" or val == "2" then return 2 end
    if val == "info" or val == "3" then return 3 end
    if val == "debug" or val == "4" then return 4 end
    if val == "trace" or val == "all" or val == "5" then return 5 end
    return tonumber(val) or 0
end

-- Configuration (read once at module load)
local LEVEL = parse_level(os.getenv("MCP_TRACE"))
local OUTPUT_FILE = os.getenv("MCP_TRACE_FILE")
local output = io.stderr

-- Open custom output file if specified
if OUTPUT_FILE and OUTPUT_FILE ~= "" and OUTPUT_FILE ~= "stderr" then
    local f, err = io.open(OUTPUT_FILE, "a")
    if f then
        output = f
        f:setvbuf('line')
    else
        io.stderr:write("[TRACE] WARNING: Cannot open trace file: " .. OUTPUT_FILE .. ": " .. (err or "unknown") .. "\n")
    end
end

-- Statistics (only tracked when tracing is enabled)
local stats = {
    messages = 0,
    by_level = {0, 0, 0, 0, 0},
    by_category = {},
    start_time = os.clock(),
}

-- Level names for output
local LEVEL_NAMES = {"ERROR", "WARN", "INFO", "DEBUG", "TRACE"}

-- Format a trace message
local function format_message(level, category, fmt, ...)
    local timestamp = string.format("%.3f", os.clock() - stats.start_time)
    local level_name = LEVEL_NAMES[level] or "???"
    local message = string.format(fmt, ...)
    return string.format("[%s] [%s] [%s] %s\n", timestamp, level_name, category, message)
end

-- Core logging function (only called when level check passes)
local function log(level, category, fmt, ...)
    stats.messages = stats.messages + 1
    stats.by_level[level] = (stats.by_level[level] or 0) + 1
    stats.by_category[category] = (stats.by_category[category] or 0) + 1
    
    output:write(format_message(level, category, fmt, ...))
end

-- Generate trace functions based on current level
-- When tracing is disabled, these are empty functions that LuaJIT can eliminate
if LEVEL >= 1 then
    function M.error(category, fmt, ...) log(1, category, fmt, ...) end
else
    function M.error() end
end

if LEVEL >= 2 then
    function M.warn(category, fmt, ...) log(2, category, fmt, ...) end
else
    function M.warn() end
end

if LEVEL >= 3 then
    function M.info(category, fmt, ...) log(3, category, fmt, ...) end
else
    function M.info() end
end

if LEVEL >= 4 then
    function M.debug(category, fmt, ...) log(4, category, fmt, ...) end
else
    function M.debug() end
end

if LEVEL >= 5 then
    function M.trace(category, fmt, ...) log(5, category, fmt, ...) end
else
    function M.trace() end
end

-- Check if a level is enabled (for conditional expensive operations)
function M.is_enabled(level)
    if type(level) == "string" then
        level = parse_level(level)
    end
    return LEVEL >= level
end

-- Get current trace level
function M.get_level()
    return LEVEL
end

-- Get statistics (only meaningful when tracing is enabled)
function M.get_stats()
    return {
        messages = stats.messages,
        by_level = stats.by_level,
        by_category = stats.by_category,
        elapsed = os.clock() - stats.start_time,
        level = LEVEL,
    }
end

-- Dump statistics to output
function M.dump_stats()
    if LEVEL == 0 then return end
    
    output:write("\n[TRACE] ========== Trace Statistics ==========\n")
    output:write(string.format("[TRACE] Level: %d (%s)\n", LEVEL, LEVEL_NAMES[LEVEL] or "off"))
    output:write(string.format("[TRACE] Total messages: %d\n", stats.messages))
    output:write(string.format("[TRACE] Elapsed: %.3fs\n", os.clock() - stats.start_time))
    
    output:write("[TRACE] By level:\n")
    for i, name in ipairs(LEVEL_NAMES) do
        if stats.by_level[i] and stats.by_level[i] > 0 then
            output:write(string.format("[TRACE]   %s: %d\n", name, stats.by_level[i]))
        end
    end
    
    output:write("[TRACE] By category:\n")
    for cat, count in pairs(stats.by_category) do
        output:write(string.format("[TRACE]   %s: %d\n", cat, count))
    end
    output:write("[TRACE] ==========================================\n")
end

-- Print startup banner if tracing is enabled
if LEVEL > 0 then
    output:write(string.format("[TRACE] Tracing enabled at level %d (%s)\n", 
        LEVEL, LEVEL_NAMES[LEVEL] or "unknown"))
    if OUTPUT_FILE then
        output:write(string.format("[TRACE] Output file: %s\n", OUTPUT_FILE))
    end
end

return M
