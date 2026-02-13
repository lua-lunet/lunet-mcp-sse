#!/usr/bin/env luajit
-- MCP-SSE Tavily Demo Server
-- 
-- A minimal MCP (Model Context Protocol) server exposing Tavily search
-- via SSE transport. Uses the Lunet framework for async I/O.
--
-- Usage:
--   luajit app/main.lua
--   # or via make:
--   make run
--
-- Environment:
--   TAVILY_API_KEY - Your Tavily API key (from .env)
--   PORT           - Server port (default 8080)
--   MCP_TRACE      - Trace level (0-5 or off/error/warn/info/debug/trace)
--
-- Test:
--   curl http://localhost:8080/
--   curl -N http://localhost:8080/sse
--
-- Tracing:
--   MCP_TRACE=info make run
--   MCP_TRACE=debug make run

io.stdout:setvbuf('no')
io.stderr:setvbuf('no')

local lunet = require("lunet")
local socket = require("lunet.socket")

-- Zero-cost tracing (no overhead when MCP_TRACE is not set)
local trace = require("app.trace")

local MCP_VERSION = "2024-11-05"
local SERVER_NAME = "lunet-tavily-mcp-demo"
local SERVER_VERSION = "0.1.0"

-- Load .env file
local function load_env_file(path)
    local file = io.open(path, "r")
    if not file then return end
    for line in file:lines() do
        local key, value = line:match("^([%w_]+)=(.*)$")
        if key and value then
            value = value:gsub("^['\"]", ""):gsub("['\"]$", "")
            if not os.getenv(key) then
                rawset(_G, "_ENV_" .. key, value)
            end
        end
    end
    file:close()
end

local function getenv(key)
    return os.getenv(key) or rawget(_G, "_ENV_" .. key)
end

load_env_file(".env")
local TAVILY_API_KEY = getenv("TAVILY_API_KEY")
if not TAVILY_API_KEY then
    print("WARNING: TAVILY_API_KEY not set. Tavily search will fail.")
    trace.warn("CONFIG", "TAVILY_API_KEY not set")
end

-- JSON encoder/decoder (minimal implementation)
local function escape_json_string(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"', '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    s = s:gsub('\b', '\\b')
    s = s:gsub('\f', '\\f')
    return s
end

local function json_encode(val)
    local t = type(val)
    if val == nil then
        return "null"
    elseif t == "boolean" then
        return val and "true" or "false"
    elseif t == "number" then
        if val ~= val then return "null" end
        if val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "string" then
        return '"' .. escape_json_string(val) .. '"'
    elseif t == "table" then
        local is_array = #val > 0 or next(val) == nil
        if is_array then
            local parts = {}
            for i, v in ipairs(val) do
                parts[i] = json_encode(v)
            end
            return "[" .. table.concat(parts, ",") .. "]"
        else
            local parts = {}
            for k, v in pairs(val) do
                if type(k) == "string" then
                    parts[#parts + 1] = '"' .. escape_json_string(k) .. '":' .. json_encode(v)
                end
            end
            return "{" .. table.concat(parts, ",") .. "}"
        end
    end
    return "null"
end

local function json_decode(str)
    local pos = 1
    local function skip_ws()
        pos = str:match("^%s*()", pos)
    end
    local function parse_value()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == '"' then
            local start = pos + 1
            local i = start
            local parts = {}
            while i <= #str do
                local ch = str:sub(i, i)
                if ch == '"' then
                    parts[#parts + 1] = str:sub(start, i - 1)
                    pos = i + 1
                    local result = table.concat(parts)
                    result = result:gsub("\\(.)", function(e)
                        local escapes = {n="\n", r="\r", t="\t", b="\b", f="\f", ['"']='"', ["\\"]="\\", ["/"]="/"}
                        return escapes[e] or e
                    end)
                    return result
                elseif ch == "\\" then
                    parts[#parts + 1] = str:sub(start, i - 1)
                    i = i + 1
                    local esc = str:sub(i, i)
                    if esc == "u" then
                        local hex = str:sub(i + 1, i + 4)
                        local cp = tonumber(hex, 16)
                        if cp then
                            if cp < 0x80 then
                                parts[#parts + 1] = string.char(cp)
                            elseif cp < 0x800 then
                                parts[#parts + 1] = string.char(
                                    0xC0 + math.floor(cp / 64),
                                    0x80 + (cp % 64))
                            else
                                parts[#parts + 1] = string.char(
                                    0xE0 + math.floor(cp / 4096),
                                    0x80 + math.floor((cp % 4096) / 64),
                                    0x80 + (cp % 64))
                            end
                        else
                            parts[#parts + 1] = "?"
                        end
                        i = i + 5
                    else
                        i = i + 1
                    end
                    start = i
                else
                    i = i + 1
                end
            end
            error("Unterminated string")
        elseif c == "{" then
            pos = pos + 1
            local obj = {}
            skip_ws()
            if str:sub(pos, pos) == "}" then
                pos = pos + 1
                return obj
            end
            while true do
                skip_ws()
                local key = parse_value()
                skip_ws()
                if str:sub(pos, pos) ~= ":" then error("Expected ':'") end
                pos = pos + 1
                local val = parse_value()
                obj[key] = val
                skip_ws()
                local sep = str:sub(pos, pos)
                if sep == "}" then
                    pos = pos + 1
                    return obj
                elseif sep == "," then
                    pos = pos + 1
                else
                    error("Expected ',' or '}'")
                end
            end
        elseif c == "[" then
            pos = pos + 1
            local arr = {}
            skip_ws()
            if str:sub(pos, pos) == "]" then
                pos = pos + 1
                return arr
            end
            while true do
                arr[#arr + 1] = parse_value()
                skip_ws()
                local sep = str:sub(pos, pos)
                if sep == "]" then
                    pos = pos + 1
                    return arr
                elseif sep == "," then
                    pos = pos + 1
                else
                    error("Expected ',' or ']'")
                end
            end
        elseif str:sub(pos, pos + 3) == "true" then
            pos = pos + 4
            return true
        elseif str:sub(pos, pos + 4) == "false" then
            pos = pos + 5
            return false
        elseif str:sub(pos, pos + 3) == "null" then
            pos = pos + 4
            return nil
        elseif c == "-" or c:match("%d") then
            local num_str = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
            pos = pos + #num_str
            return tonumber(num_str)
        else
            error("Unexpected character: " .. c .. " at position " .. pos)
        end
    end
    return parse_value()
end

-- Session ID generator
local function random_id()
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local id = {}
    for i = 1, 16 do
        local idx = math.random(1, #chars)
        id[i] = chars:sub(idx, idx)
    end
    return table.concat(id)
end

-- SSE event formatter
local function sse_event(event_name, data)
    local lines = {}
    if event_name then
        lines[#lines + 1] = "event: " .. event_name
    end
    lines[#lines + 1] = "data: " .. data
    lines[#lines + 1] = ""
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
end

-- JSON-RPC helpers
local function jsonrpc_response(id, result)
    return json_encode({
        jsonrpc = "2.0",
        id = id,
        result = result,
    })
end

local function jsonrpc_error(id, code, message)
    return json_encode({
        jsonrpc = "2.0",
        id = id,
        error = {
            code = code,
            message = message,
        },
    })
end

-- HTTP request parser
local function parse_http_request(data)
    local req = {headers = {}, body = nil}
    local header_end = data:find("\r\n\r\n")
    if not header_end then return nil end

    local header_section = data:sub(1, header_end - 1)
    local body = data:sub(header_end + 4)

    local first_line = header_section:match("^([^\r\n]+)")
    if not first_line then return nil end

    req.method, req.path = first_line:match("^(%S+)%s+(%S+)")
    if not req.method then return nil end

    local path_only, query = req.path:match("^([^?]+)%??(.*)")
    req.path = path_only or req.path
    req.query = {}
    if query and query ~= "" then
        for pair in query:gmatch("[^&]+") do
            local k, v = pair:match("^([^=]+)=?(.*)")
            if k then req.query[k] = v or "" end
        end
    end

    for line in header_section:gmatch("\r\n([^\r\n]+)") do
        local name, value = line:match("^([^:]+):%s*(.*)$")
        if name then
            req.headers[name:lower()] = value
        end
    end

    local content_length = req.headers["content-length"]
    if content_length then
        content_length = tonumber(content_length)
        if content_length and content_length > 0 then
            req.body = body:sub(1, content_length)
        end
    end

    return req
end

-- HTTP response builder
local function http_response(status, headers, body)
    local status_texts = {
        [200] = "OK", [202] = "Accepted", [400] = "Bad Request",
        [404] = "Not Found", [405] = "Method Not Allowed",
        [500] = "Internal Server Error",
    }
    local parts = {"HTTP/1.1 " .. status .. " " .. (status_texts[status] or "OK") .. "\r\n"}
    headers = headers or {}
    if body and not headers["Content-Length"] then
        headers["Content-Length"] = #body
    end
    for name, value in pairs(headers) do
        parts[#parts + 1] = name .. ": " .. tostring(value) .. "\r\n"
    end
    parts[#parts + 1] = "\r\n"
    if body then parts[#parts + 1] = body end
    return table.concat(parts)
end

-- Shell escape for curl
local function shell_escape(s)
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Tavily API call via curl (no TLS in Lunet yet)
local function tavily_search(query, max_results)
    if not TAVILY_API_KEY then
        return nil, "TAVILY_API_KEY not configured"
    end

    max_results = max_results or 5
    local request_body = json_encode({
        query = query,
        max_results = max_results,
        include_answer = true,
        search_depth = "basic",
    })

    local cmd = "curl -s -X POST 'https://api.tavily.com/search' " ..
                "-H 'Content-Type: application/json' " ..
                "-H " .. shell_escape("Authorization: Bearer " .. TAVILY_API_KEY) .. " " ..
                "-d " .. shell_escape(request_body)

    local handle = io.popen(cmd)
    if not handle then
        return nil, "Failed to execute curl"
    end

    local response = handle:read("*a")
    handle:close()

    if not response or response == "" then
        return nil, "Empty response from Tavily API"
    end

    local ok, result = pcall(json_decode, response)
    if not ok then
        return nil, "Failed to parse Tavily response: " .. tostring(result)
    end

    if result.error then
        return nil, "Tavily API error: " .. (result.error or "unknown")
    end

    return result
end

-- MCP tool definitions (just tavily-search)
local tools = {
    {
        name = "tavily-search",
        description = "Search the web using Tavily AI search engine. Returns relevant web content with titles, URLs, and snippets.",
        inputSchema = {
            type = "object",
            properties = {
                query = {
                    type = "string",
                    description = "The search query",
                },
                max_results = {
                    type = "number",
                    description = "Maximum number of results (1-10, default 5)",
                },
            },
            required = {"query"},
        },
    },
}

-- Handle tool calls
local function handle_tool_call(name, arguments)
    trace.info("TOOL", "Calling tool: %s", name)
    
    if name == "tavily-search" then
        local query = arguments.query
        local max_results = arguments.max_results or 5
        if max_results > 10 then max_results = 10 end
        if max_results < 1 then max_results = 1 end

        trace.debug("TOOL", "tavily-search query=%s max_results=%d", query, max_results)
        
        local result, err = tavily_search(query, max_results)
        if not result then
            trace.error("TOOL", "tavily-search failed: %s", err or "unknown")
            return {
                content = {{type = "text", text = "Error: " .. (err or "unknown")}},
                isError = true,
            }
        end
        
        trace.debug("TOOL", "tavily-search returned %d results", result.results and #result.results or 0)

        local output = {}
        if result.answer then
            output[#output + 1] = "Answer: " .. result.answer
            output[#output + 1] = ""
        end
        if result.results then
            output[#output + 1] = "Results:"
            for i, r in ipairs(result.results) do
                output[#output + 1] = i .. ". " .. (r.title or "No title")
                output[#output + 1] = "   URL: " .. (r.url or "")
                if r.content then
                    local snippet = r.content:sub(1, 200)
                    if #r.content > 200 then snippet = snippet .. "..." end
                    output[#output + 1] = "   " .. snippet
                end
                output[#output + 1] = ""
            end
        end

        return {
            content = {{type = "text", text = table.concat(output, "\n")}},
        }
    end

    return {
        content = {{type = "text", text = "Unknown tool: " .. name}},
        isError = true,
    }
end

-- Handle MCP JSON-RPC requests
local function handle_mcp_request(msg)
    local method = msg.method
    local params = msg.params or {}
    local id = msg.id

    trace.debug("MCP", "Request: method=%s id=%s", method or "nil", tostring(id))

    if method == "initialize" then
        return jsonrpc_response(id, {
            protocolVersion = MCP_VERSION,
            capabilities = {
                tools = {},
            },
            serverInfo = {
                name = SERVER_NAME,
                version = SERVER_VERSION,
            },
        })
    elseif method == "notifications/initialized" then
        return nil
    elseif method == "tools/list" then
        return jsonrpc_response(id, {
            tools = tools,
        })
    elseif method == "tools/call" then
        local tool_name = params.name
        local arguments = params.arguments or {}
        local result = handle_tool_call(tool_name, arguments)
        return jsonrpc_response(id, result)
    elseif method == "ping" then
        return jsonrpc_response(id, {})
    else
        return jsonrpc_error(id, -32601, "Method not found: " .. (method or "nil"))
    end
end

-- Session storage
local sessions = {}

-- Handle SSE connection
local function handle_sse_request(client, session_id)
    local headers = {
        ["Content-Type"] = "text/event-stream",
        ["Cache-Control"] = "no-cache",
        ["Connection"] = "keep-alive",
        ["Access-Control-Allow-Origin"] = "*",
    }

    local header_str = "HTTP/1.1 200 OK\r\n"
    for k, v in pairs(headers) do
        header_str = header_str .. k .. ": " .. v .. "\r\n"
    end
    header_str = header_str .. "\r\n"
    socket.write(client, header_str)

    local endpoint = "/message?session=" .. session_id
    socket.write(client, sse_event("endpoint", endpoint))

    sessions[session_id] = {
        client = client,
        messages = {},
    }

    trace.info("SSE", "Session %s connected", session_id)
end

-- Handle message POST
local function handle_message_request(client, req, session_id)
    local session = sessions[session_id]
    if not session then
        socket.write(client, http_response(404, {
            ["Content-Type"] = "application/json",
        }, json_encode({error = "Session not found"})))
        socket.close(client)
        return
    end

    if not req.body or req.body == "" then
        socket.write(client, http_response(400, {
            ["Content-Type"] = "application/json",
        }, json_encode({error = "Empty body"})))
        socket.close(client)
        return
    end

    local ok, msg = pcall(json_decode, req.body)
    if not ok then
        socket.write(client, http_response(400, {
            ["Content-Type"] = "application/json",
        }, json_encode({error = "Invalid JSON"})))
        socket.close(client)
        return
    end

    socket.write(client, http_response(202, {}, ""))
    socket.close(client)

    local response = handle_mcp_request(msg)
    if response and session.client then
        local err = socket.write(session.client, sse_event("message", response))
        if err then
            trace.info("SSE", "Session %s disconnected: %s", session_id, tostring(err))
            socket.close(session.client)
            sessions[session_id] = nil
        end
    end
end

-- Main client handler
local function handle_client(client)
    local data = socket.read(client)
    if not data then
        trace.trace("HTTP", "Client disconnected before sending data")
        socket.close(client)
        return
    end

    local req = parse_http_request(data)
    if not req then
        trace.warn("HTTP", "Bad request: could not parse HTTP")
        socket.write(client, http_response(400, {}, "Bad Request"))
        socket.close(client)
        return
    end

    trace.debug("HTTP", "%s %s", req.method, req.path)

    -- CORS preflight
    if req.method == "OPTIONS" then
        socket.write(client, http_response(200, {
            ["Access-Control-Allow-Origin"] = "*",
            ["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS",
            ["Access-Control-Allow-Headers"] = "Content-Type",
        }, ""))
        socket.close(client)
        return
    end

    -- SSE endpoint
    if req.path == "/sse" and req.method == "GET" then
        local session_id = random_id()
        handle_sse_request(client, session_id)
        return
    end

    -- Message endpoint
    if req.path == "/message" and req.method == "POST" then
        local session_id = req.query.session
        if not session_id then
            socket.write(client, http_response(400, {
                ["Content-Type"] = "application/json",
            }, json_encode({error = "session parameter required"})))
            socket.close(client)
            return
        end
        handle_message_request(client, req, session_id)
        return
    end

    -- Server info endpoint
    if req.path == "/" and req.method == "GET" then
        local info = {
            name = SERVER_NAME,
            version = SERVER_VERSION,
            protocol = "MCP",
            protocolVersion = MCP_VERSION,
            endpoints = {
                sse = "/sse",
                message = "/message?session=<id>",
            },
            tools = {},
        }
        for _, tool in ipairs(tools) do
            info.tools[#info.tools + 1] = tool.name
        end
        socket.write(client, http_response(200, {
            ["Content-Type"] = "application/json",
        }, json_encode(info)))
        socket.close(client)
        return
    end

    socket.write(client, http_response(404, {}, "Not Found"))
    socket.close(client)
end

-- Initialize random seed
math.randomseed(os.time())

-- Main server
lunet.spawn(function()
    local port = tonumber(getenv("PORT")) or 8080
    local host = getenv("HOST") or "127.0.0.1"
    local listener, err = socket.listen("tcp", host, port)
    if not listener then
        trace.error("SERVER", "Cannot listen on port %d: %s", port, err or "unknown")
        print("FATAL: Cannot listen: " .. (err or "unknown"))
        return
    end

    trace.info("SERVER", "Starting on port %d", port)
    print("MCP-SSE Tavily Demo Server")
    print("==========================")
    print("Protocol: MCP " .. MCP_VERSION)
    print("Server:   " .. SERVER_NAME .. " v" .. SERVER_VERSION)
    print("Port:     http://" .. host .. ":" .. port)
    print("")
    print("Endpoints:")
    print("  GET  /       -> Server info")
    print("  GET  /sse    -> SSE stream (creates session)")
    print("  POST /message?session=<id> -> Send JSON-RPC message")
    print("")
    print("Tools: tavily-search")
    print("")
    print("Test:")
    print("  curl http://localhost:" .. port .. "/")
    print("  curl -N http://localhost:" .. port .. "/sse")

    while true do
        local client = socket.accept(listener)
        if client then
            lunet.spawn(function()
                handle_client(client)
            end)
        end
    end
end)
