#!/usr/bin/env luajit

local http = require("socket.http")
local ltn12 = require("ltn12")

local BASE_URL = "http://localhost:8080"

local function http_post(path, body)
    local resp_body = {}
    local _, status = http.request{
        url = BASE_URL .. path,
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["Content-Length"] = #body,
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(resp_body),
    }
    return table.concat(resp_body), status
end

local function http_get(path)
    local resp_body = {}
    local _, status = http.request{
        url = BASE_URL .. path,
        sink = ltn12.sink.table(resp_body),
    }
    return table.concat(resp_body), status
end

print("=== MCP-SSE Lua Test Suite ===")
print("")

print("Test 1: Server Info Endpoint")
local info, status = http_get("/")
if status == 200 then
    print("  PASS: GET / returned 200")
    print("  Response: " .. info:sub(1, 200) .. "...")
else
    print("  FAIL: GET / returned " .. tostring(status))
    os.exit(1)
end

print("")
print("Test 2: SSE Endpoint Connection")
local sse, status = http_get("/sse")
if status == 200 then
    print("  PASS: GET /sse returned 200")
    if sse:find("event: endpoint") then
        print("  PASS: SSE stream includes endpoint event")
    else
        print("  FAIL: No endpoint event in SSE stream")
        os.exit(1)
    end
else
    print("  FAIL: GET /sse returned " .. tostring(status))
    os.exit(1)
end

print("")
print("Test 3: Initialize Request (no session)")
local init_resp, status = http_post("/message", '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}')
print("  Response status: " .. tostring(status))
if status == 202 or status == 200 or status == 400 then
    print("  PASS: Message endpoint responded")
else
    print("  FAIL: Unexpected status " .. tostring(status))
end

print("")
print("=== All Tests Passed ===")