Name = "keystone-update"
NamePretty = "Update"
Description = "Keystone OS release status and update actions"
Icon = "software-update-available"
HideFromProviderlist = true
History = false
FixedOrder = true

local function json_decode(value)
    if jsonDecode ~= nil then
        return jsonDecode(value)
    end

    if jsonDecodes ~= nil then
        return jsonDecodes(value)
    end

    return nil
end

local function command_path(name)
    return name
end

-- %VALUE% is interpolated inside single quotes, so every activation value
-- emitted by `ks menu update entries` MUST be shell-safe under single-quote
-- rules: no single quotes, backslashes, or unescaped control characters.
-- `ks menu update` enforces this on the producer side (stable tokens +
-- URL allowlist); dispatch also re-validates URL payloads defensively.
Action = command_path("ks") .. " menu update dispatch '%VALUE%'"

function GetEntries()
    local handle = io.popen(command_path("ks") .. " menu update entries 2>/dev/null")
    if not handle then
        return {}
    end

    local payload = handle:read("*a") or ""
    handle:close()

    if payload == "" then
        return {}
    end

    local ok, entries = pcall(json_decode, payload)
    if not ok or type(entries) ~= "table" then
        return {}
    end

    return entries
end
