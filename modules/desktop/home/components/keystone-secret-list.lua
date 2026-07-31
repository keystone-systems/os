Name = "keystone-secret-list"
NamePretty = "Secrets"
Description = "Secrets in the selected category"
Icon = "dialog-password"
HideFromProviderlist = true
Parent = "keystone-secrets"
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
    local category = lastMenuValue("keystone-secrets") or ""
    if category == "" then
        return {}
    end

    local handle = io.popen(command_path("keystone-secrets-menu") .. " secrets-json " .. "'" .. category:gsub("'", "'\\''") .. "' 2>/dev/null")
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
