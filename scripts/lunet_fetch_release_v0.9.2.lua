#!/usr/bin/env lua
-- lunet_fetch_release.lua -- fetch, verify and install an official lunet
-- binary release into a project-local, versioned directory.
--
-- This file is a TEMPLATE: CI renders it per release as
--   lunet_fetch_release_<tag>.lua
-- by substituting v0.9.2. Do not hand-edit rendered copies.
--
-- Result layout (relative to the current working directory):
--   .lunet/<tag>/lunet-run     (lunet-run.exe on Windows)
--   .lunet/<tag>/types/        (shipped LuaCATS + Teal documentation)
--   ... remaining official archive contents preserved alongside.
--
-- Usage:
--   lua lunet_fetch_release_<tag>.lua
--   stdout (last line): the runtime path, e.g. .lunet/v0.7.2/lunet-run
--   All progress/diagnostics go to stderr so Makefiles can capture stdout:
--     LUNET_RUN := $(shell lua lunet_fetch_release_<tag>.lua)
--
-- Guarantees:
--   * host OS/arch detection; fails clearly on unsupported hosts
--   * downloads only from the official lua-lunet/lunet GitHub release
--   * SHA-256 of the archive verified against the release metadata digest
--     before extraction; fails closed on mismatch
--   * atomic install: download/extract in a sibling staging dir, moved into
--     place only after digest and layout checks pass
--   * idempotent: a valid existing install is not downloaded again; an
--     incomplete install is repaired
--
-- Host requirements: curl, a SHA-256 tool (shasum or sha256sum on Unix,
-- certutil on Windows), tar (Windows 10+ ships bsdtar as tar.exe, which also
-- reads .zip). Runs on Lua 5.1+ and LuaJIT.

local RELEASE_TAG = "v0.9.2"
local REPO = "lua-lunet/lunet"

local DEST = ".lunet/" .. RELEASE_TAG
local STAGING = ".lunet/.staging-" .. RELEASE_TAG
local IS_WINDOWS = os.getenv("OS") == "Windows_NT"
local BINNAME = IS_WINDOWS and "lunet-run.exe" or "lunet-run"

local function log(msg)
	io.stderr:write("[lunet-fetch] " .. msg .. "\n")
end

local function die(msg)
	log("ERROR: " .. msg)
	os.exit(1)
end

-- Portable os.execute wrapper: true iff the command exited 0.
-- 5.1/LuaJIT return a raw status number (0 == success); 5.2+ return
-- true, "exit", 0 on success.
local function run(cmd)
	local ok, _, code = os.execute(cmd)
	if ok == true then
		return code == 0
	end
	if type(ok) == "number" then
		return ok == 0
	end
	return false
end

local function capture(cmd)
	local p = io.popen(cmd)
	if not p then
		return nil
	end
	local out = p:read("*a")
	p:close()
	return out
end

local function winpath(p)
	return (p:gsub("/", "\\"))
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function mkdir_p(path)
	if IS_WINDOWS then
		run('if not exist "' .. winpath(path) .. '" mkdir "' .. winpath(path) .. '"')
	else
		run('mkdir -p "' .. path .. '"')
	end
end

local function rm_rf(path)
	if IS_WINDOWS then
		run('if exist "' .. winpath(path) .. '" rmdir /s /q "' .. winpath(path) .. '"')
	else
		run('rm -rf "' .. path .. '"')
	end
end

local function detect_asset()
	if IS_WINDOWS then
		local arch = os.getenv("PROCESSOR_ARCHITECTURE") or ""
		if arch == "AMD64" then
			return "lunet-windows-amd64.zip"
		end
		return nil, "unsupported Windows architecture: "
			.. (arch ~= "" and arch or "unknown")
			.. " (published: amd64)"
	end
	local uname_s = (capture("uname -s 2>/dev/null") or ""):gsub("%s+", "")
	local uname_m = (capture("uname -m 2>/dev/null") or ""):gsub("%s+", "")
	if uname_s == "Darwin" then
		return "lunet-macos.tar.gz"
	end
	if uname_s == "Linux" then
		if uname_m == "x86_64" or uname_m == "amd64" then
			return "lunet-linux-amd64.tar.gz"
		end
		if uname_m == "aarch64" or uname_m == "arm64" then
			return "lunet-linux-arm64.tar.gz"
		end
		return nil, "unsupported Linux architecture: " .. uname_m .. " (published: amd64, arm64)"
	end
	return nil, "unsupported host OS: " .. (uname_s ~= "" and uname_s or "unknown")
end

-- Expected SHA-256 for the asset, from the official release metadata.
-- The GitHub API emits per-asset "digest":"sha256:<hex>" fields; we bound the
-- search to the window between this asset's "name" and the end of its object
-- ("browser_download_url", the last field) so a null/missing digest on our
-- asset can never match a different asset's digest.
local function fetch_expected_digest(asset)
	local api = "https://api.github.com/repos/" .. REPO .. "/releases/tags/" .. RELEASE_TAG
	local json = capture(
		'curl -fsSL --connect-timeout 10 --max-time 30'
			.. ' -H "Accept: application/vnd.github+json"'
			.. ' -H "User-Agent: lunet-fetch-release"'
			.. ' "' .. api .. '"'
	)
	if not json or json == "" then
		die("could not query release metadata: " .. api)
	end
	local assets_start = json:find('"assets"%s*:%s*%[') or 1
	local needle = '"name":"' .. asset .. '"'
	local _, name_end = json:find(needle, assets_start, true)
	if not name_end then
		die("asset " .. asset .. " not found in release " .. RELEASE_TAG .. " metadata")
	end
	local window_end = json:find('"browser_download_url"', name_end, true) or #json
	local window = json:sub(name_end, window_end)
	local hex = window:match('"digest"%s*:%s*"sha256:([0-9a-fA-F]+)"')
	if not hex then
		die("no SHA-256 digest published for " .. asset .. " (failing closed)")
	end
	return hex:lower()
end

local function sha256_file(path)
	if IS_WINDOWS then
		local out = capture('certutil -hashfile "' .. winpath(path) .. '" SHA256')
		if out then
			local lines = {}
			for l in out:gmatch("[^\r\n]+") do
				lines[#lines + 1] = l
			end
			local hex = (lines[2] or ""):gsub("%s+", ""):lower()
			if #hex == 64 and hex:match("^[0-9a-f]+$") then
				return hex
			end
		end
		return nil
	end
	if run("command -v shasum >/dev/null 2>&1") then
		local out = capture('shasum -a 256 "' .. path .. '"')
		return out and out:match("^([0-9a-f]+)")
	end
	if run("command -v sha256sum >/dev/null 2>&1") then
		local out = capture('sha256sum "' .. path .. '"')
		return out and out:match("^([0-9a-f]+)")
	end
	return nil
end

local function extract(archive, dest_dir)
	if archive:match("%.zip$") then
		if IS_WINDOWS then
			if run('tar -xf "' .. winpath(archive) .. '" -C "' .. winpath(dest_dir) .. '"') then
				return true
			end
			return run(
				"powershell -NoProfile -Command \"Expand-Archive -LiteralPath '"
					.. winpath(archive)
					.. "' -DestinationPath '"
					.. winpath(dest_dir)
					.. "' -Force\""
			)
		end
		return run('unzip -q "' .. archive .. '" -d "' .. dest_dir .. '"')
	end
	return run('tar -xzf "' .. archive .. '" -C "' .. dest_dir .. '"')
end

local function install_valid(dir)
	return file_exists(dir .. "/" .. BINNAME)
		and file_exists(dir .. "/types/lunet.lua")
		and file_exists(dir .. "/.install-sha256")
end

local function main()
	-- Idempotency: a valid matching install is reused without any network I/O.
	if install_valid(DEST) then
		log("valid existing installation at " .. DEST .. " (nothing to do)")
		print(DEST .. "/" .. BINNAME)
		return
	end
	if file_exists(DEST .. "/" .. BINNAME) or file_exists(DEST .. "/types/lunet.lua") then
		log("incomplete installation at " .. DEST .. " (repairing)")
	end

	local asset, err = detect_asset()
	if not asset then
		die(err)
	end
	log("host asset: " .. asset)

	if IS_WINDOWS then
		if not run("where curl >NUL 2>&1") then
			die("curl not found on PATH")
		end
	elseif not run("command -v curl >/dev/null 2>&1") then
		die("curl not found on PATH")
	end

	local expected = fetch_expected_digest(asset)
	log("expected sha256: " .. expected)

	rm_rf(STAGING)
	mkdir_p(STAGING)

	local url = "https://github.com/" .. REPO .. "/releases/download/" .. RELEASE_TAG .. "/" .. asset
	local dl = STAGING .. "/" .. asset
	log("downloading " .. url)
	if not run('curl -fsSL --connect-timeout 10 --max-time 600 -o "' .. dl .. '" "' .. url .. '"') then
		rm_rf(STAGING)
		die("download failed: " .. url)
	end

	local actual = sha256_file(dl)
	if not actual then
		rm_rf(STAGING)
		die("no SHA-256 tool found (need shasum, sha256sum, or certutil)")
	end
	if actual ~= expected then
		rm_rf(STAGING)
		die("SHA-256 mismatch for " .. asset .. "\n  expected: " .. expected .. "\n  actual:   " .. actual)
	end
	log("digest verified")

	if not extract(dl, STAGING) then
		rm_rf(STAGING)
		die("extraction failed for " .. asset)
	end
	if not file_exists(STAGING .. "/" .. BINNAME) or not file_exists(STAGING .. "/types/lunet.lua") then
		rm_rf(STAGING)
		die("archive layout check failed: expected " .. BINNAME .. " and types/ at top level")
	end
	-- The archive itself is not part of the installed layout.
	os.remove(dl)
	if not IS_WINDOWS then
		run('chmod +x "' .. STAGING .. "/" .. BINNAME .. '"')
	end

	local marker = io.open(STAGING .. "/.install-sha256", "w")
	if not marker then
		rm_rf(STAGING)
		die("could not write install marker in " .. STAGING)
	end
	marker:write(expected .. "\n")
	marker:close()

	rm_rf(DEST)
	if not os.rename(STAGING, DEST) then
		rm_rf(STAGING)
		die("could not move " .. STAGING .. " into place at " .. DEST)
	end
	log("installed lunet " .. RELEASE_TAG .. " -> " .. DEST)
	print(DEST .. "/" .. BINNAME)
end

main()
