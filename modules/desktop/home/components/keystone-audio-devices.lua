Name = "keystone-audio-devices"
NamePretty = "Audio devices"
Description = "Audio device defaults"
Icon = "audio-card"
HideFromProviderlist = true
Parent = "keystone-audio"
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

Action = command_path("keystone-audio-menu") .. " dispatch '%VALUE%'"

local function current_kind()
    return lastMenuValue("keystone-audio") or ""
end

function GetEntries()
    local kind = current_kind()
    if kind == "" then
        return {}
    end

    local handle = io.popen(command_path("keystone-audio-menu") .. " devices-json " .. "'" .. kind:gsub("'", "'\\''") .. "' 2>/dev/null")
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
