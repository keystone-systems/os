Name = "keystone-accounts"
NamePretty = "Accounts"
Description = "Configured mail and calendar accounts"
Icon = "mail-unread"
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

function GetEntries()
    local handle = io.popen(command_path("keystone-accounts-menu") .. " accounts-json 2>/dev/null")
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
