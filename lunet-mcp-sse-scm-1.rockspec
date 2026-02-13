rockspec_format = "3.0"
package = "lunet-mcp-sse"
version = "scm-1"

source = {
    url = "git+https://github.com/lua-lunet/lunet-mcp-sse.git"
}

description = {
    summary = "MCP-SSE demo server for Tavily search using Lunet",
    detailed = [[
        A minimal MCP (Model Context Protocol) server that exposes Tavily
        web search as a tool via SSE transport. Demonstrates how to build
        async networking applications with the Lunet framework.
        
        Features:
        - MCP 2024-11-05 protocol support
        - SSE (Server-Sent Events) transport
        - Tavily search integration
        - Zero-cost tracing
        - Memory-efficient design (~2 MB RSS)
    ]],
    homepage = "https://github.com/lua-lunet/lunet-mcp-sse",
    license = "MIT",
    maintainer = "Lunet Project"
}

dependencies = {
    "lua >= 5.1",
    "lunet >= 0.1.2",
}

build = {
    type = "builtin",
    modules = {},
    install = {
        lua = {
            ["app.main"] = "app/main.lua",
            ["app.trace"] = "app/trace.lua",
        }
    }
}
