local PREFIX = "|cff00ff00[KeyRoll]|r"

KeyRollDB = KeyRollDB or {}
local cache = KeyRollDB
local lastRequestZone
local lastPartyMembers = {}
local KEY_REQUEST_COOLDOWN = 5
local lastKeyRequestTime = 0
local pendingKeyRequest = false

-------------------------------------------------
-- Debug mode
-------------------------------------------------
KeyRollDB_Debug = KeyRollDB_Debug or false
local function IsDebug()
    return KeyRollDB_Debug == true
end

local function DebugPrint(msg, ...)
    if IsDebug() then
        print("|cff00ff00[KeyRoll Debug]|r", msg, ...)
    end
end

local function GetDungeonName(mapID)
    if not mapID then
        return IsDebug() and "Unknown Dungeon" or "?"
    end

    local name = C_ChallengeMode.GetMapUIInfo(mapID)
    if name then
        return name
    end

    return IsDebug() and "Unknown Dungeon" or "?"
end


-------------------------------------------------
-- Addon keystone broadcasters
-------------------------------------------------
local ADDON_PREFIXES = {
    ["BigWigs"] = true,
    ["BigWigsKey"] = true,
    ["DBM"] = true,
    ["DBM-Key"] = true,
    ["AngryKeystones"] = true,
    ["MDT"] = true,
	["LibKS"] = true,
}

-------------------------------------------------
-- Flavor text
-------------------------------------------------
local ROLL_MESSAGES = {
    "Shaking the keystone bag...",
    "Consulting the ancient key spirits...",
    "Rolling for pain and glory...",
    "Deciding our fate...",
}

local WIN_MESSAGES = {
    "The keys have spoken!",
    "Destiny chooses:",
    "Tonight we suffer in:",
    "Prepare yourselves for:",
}

-------------------------------------------------
-- Party utilities
-------------------------------------------------
local function GetCurrentPartyMembers()
    local members = {}
    local playerName = Ambiguate(UnitName("player"), "short")
    members[playerName] = true
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party"..i
        if UnitExists(unit) then
            local name = Ambiguate(UnitName(unit), "short")
            members[name] = true
        end
    end
    return members
end

-------------------------------------------------
-- Cache handling
-------------------------------------------------
local function StoreKey(sender, mapID, level)
    if not sender or not mapID or not level or level <= 0 then return end
    sender = Ambiguate(sender, "short")
    cache[sender] = { name = sender, mapID = mapID, level = level, time = time() }
end

local function PruneCache()
    local members = GetCurrentPartyMembers()

    for name, key in pairs(cache) do
        if not key.debug and lastPartyMembers[name] and not members[name] then
            cache[name] = nil
            DebugPrint("Pruned keystone for", name)
        end
    end
	lastPartyMembers = members
end

local function GetRollableKeys()
    PruneCache()
    local keys = {}
    if cache then
        for _, key in pairs(cache) do
            if key and not key.debug then
                table.insert(keys, key)
            end
        end
    end
    return keys
end

-------------------------------------------------
-- Debug solo keys
-------------------------------------------------
local function DebugSeed()
    cache["TestPlayer1"] = {
        name = "TestPlayer1",
        mapID = 2367,
        level = 12,
        time = time(),
        debug = true,
    }

    cache["TestPlayer2"] = {
        name = "TestPlayer2",
        mapID = 2370,
        level = 15,
        time = time(),
        debug = true,
    }

    DebugPrint("Seeded fake keystones")
end

local function DebugClear()
    for name, key in pairs(cache) do
        if key.debug then
            cache[name] = nil
        end
    end
    DebugPrint("Cleared debug keystones")
end

-------------------------------------------------
-- Keystone parsing
-------------------------------------------------
local function ParseKeystone(prefix, message, sender)
	if InCombatLockdown() then return end
    if type(message) ~= "string" or not sender then return end
    sender = Ambiguate(sender, "short")

    local mapID, level

    -- Party chat links
    if not prefix or not ADDON_PREFIXES[prefix] then
        mapID, level = message:match("Hkeystone:(%d+):(%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
        if mapID and level and level > 0 then
            StoreKey(sender, mapID, level)
            DebugPrint("Captured keystone from party chat link:", sender, mapID, level)
        end
        return
    end

    -- LibKS format: level,mapID,...
    if prefix == "LibKS" then
        level, mapID = message:match("^(%d+),(%d+)")
        level, mapID = tonumber(level), tonumber(mapID)
    else
        -- BigWigs / MDT / DBM-Key fallback formats
        mapID, level =
            message:match("KEYSTONE:(%d+):(%d+)") or
            message:match("map=(%d+).+level=(%d+)") or
            message:match("(%d+):(%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    end

    if mapID and level and level > 0 then
        StoreKey(sender, mapID, level)
        DebugPrint("Stored keystone from addon:", sender, mapID, level)
    end
end

-------------------------------------------------
-- Request keystones from addons
-------------------------------------------------
local function RequestPartyKeystones()
    if not IsInGroup() and not KeyRollDB_Debug then return end
    local zoneID = C_Map.GetBestMapForUnit("player")
    lastRequestZone = zoneID

    DebugPrint("Requesting party keystones...")

    C_ChatInfo.SendAddonMessage("BigWigs", "REQUEST_KEYS", "PARTY")
    C_ChatInfo.SendAddonMessage("BigWigsKey", "REQUEST", "PARTY")
    C_ChatInfo.SendAddonMessage("DBM", "KEY_REQUEST", "PARTY")
    C_ChatInfo.SendAddonMessage("DBM-Key", "REQUEST", "PARTY")
    C_ChatInfo.SendAddonMessage("AngryKeystones", "REQUEST", "PARTY")
    C_ChatInfo.SendAddonMessage("MDT", "REQUEST_KEYS", "PARTY")
end

local function RequestPartyKeystonesSafe()

    if InCombatLockdown() then
        if not pendingKeyRequest then
            DebugPrint("In combat – deferring keystone request")
            pendingKeyRequest = true
            C_Timer.After(1, RequestPartyKeystonesSafe)
        end
        return
    end

    local now = GetTime()
    local elapsed = now - lastKeyRequestTime

    if elapsed < KEY_REQUEST_COOLDOWN then
        if not pendingKeyRequest then
            pendingKeyRequest = true
            local delay = KEY_REQUEST_COOLDOWN - elapsed
            DebugPrint("Rate limited – retrying in", string.format("%.1f", delay), "seconds")
            C_Timer.After(delay, RequestPartyKeystonesSafe)
        end
        return
    end

    pendingKeyRequest = false
    lastKeyRequestTime = now
    RequestPartyKeystones()
end

-------------------------------------------------
-- Safe send
-------------------------------------------------
local function SafeSend(text, localOnly)
    if localOnly then
        print(PREFIX, text)
    elseif IsInGroup() then
        SendChatMessage(text, "PARTY")
    else
        print(PREFIX, text)
    end
end

local function SendFlavor(text)
    if IsInGroup() then
        SendChatMessage(text, "PARTY")
    else
        print(PREFIX, text)
    end
end

-------------------------------------------------
-- Manual capture
-------------------------------------------------
local function ManualCapture(silent)
    if not IsInGroup() and not KeyRollDB_Debug then
        if not silent then
            print(PREFIX, "You must be in a party to capture keys.")
        end
        return
    end

    if not silent then
        SafeSend("Requesting party keystones...")
    end

    DebugPrint("Manually capturing party keys...")
    RequestPartyKeystonesSafe()

end

-------------------------------------------------
-- Event frame
-------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("CHAT_MSG_PARTY")
frame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
    if event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = arg1, arg2, arg3, arg4
        if not message or not sender then return end
        if IsDebug() then
            DebugPrint("Received addon message:", prefix, message, "from", sender)
        end
        ParseKeystone(prefix, message, sender)
        return
    end

    if event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER" then
        local message, sender = arg1, arg2
        if not message or not sender then return end

        if InCombatLockdown() then return end

        if type(message) == "string" and message:find("Hkeystone:%d+:%d+") then
            if IsDebug() then
                DebugPrint("Received party keystone message:", message, "from", sender)
            end
            ParseKeystone(nil, message, sender)
        end
        return
    end

    if event == "GROUP_ROSTER_UPDATE" then
		if not next(lastPartyMembers) then
			lastPartyMembers = GetCurrentPartyMembers()
			return
		end
        PruneCache()
        RequestPartyKeystonesSafe()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RequestPartyKeystonesSafe()
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        DebugPrint("Dungeon completed – updating party keystones")
        PruneCache()
        RequestPartyKeystonesSafe()

        C_Timer.After(30, function()
            ManualCapture(true)
        end)
        return
    end
end)

-------------------------------------------------
-- Slash commands
-------------------------------------------------
SLASH_KEYROLL1 = "/keyroll"
SlashCmdList["KEYROLL"] = function(msg)
    msg = msg and msg:lower() or ""

    if msg == "capture" then		
        ManualCapture()
        return
    end

    local keys = GetRollableKeys()

    if msg == "list" then
        if #keys == 0 then
            SafeSend("No party keystones known. Ask players to link keys.", true)
            return
        end
        SafeSend("Party keystones:")
		for _, key in ipairs(keys) do
			local dungeon = GetDungeonName(key.mapID)
			SafeSend(string.format(" %s — %s +%d", key.name, dungeon, key.level))
		end
        return
    end
	
	if msg:find("^debug") then
    local arg = msg:match("^debug%s*(%S*)")

    if arg == "on" then
        KeyRollDB_Debug = true
        print(PREFIX, "Debug mode enabled.")

    elseif arg == "off" then
        KeyRollDB_Debug = false
        DebugClear()
        print(PREFIX, "Debug mode disabled.")

    elseif arg == "seed" then
        DebugSeed()
        print(PREFIX, "Debug keys added.")

    elseif arg == "clear" then
        DebugClear()
        print(PREFIX, "Debug keys cleared.")

    else
        print(PREFIX, "Debug commands:")
        print("  /keyroll debug on")
        print("  /keyroll debug off")
        print("  /keyroll debug seed")
        print("  /keyroll debug clear")
    end

    return
end

	if #keys == 0 then
		SafeSend("No party keystones known. Ask players to link keys.", true)
		return
	end

	local rollMessage = ROLL_MESSAGES[math.random(#ROLL_MESSAGES)]
	SendFlavor(rollMessage)

	C_Timer.After(1.5, function()
		local chosen = keys[math.random(#keys)]
		local dungeon = GetDungeonName(chosen.mapID)
		local winMessage = WIN_MESSAGES[math.random(#WIN_MESSAGES)]
		SendFlavor(winMessage .. string.format(" %s +%d (from %s)", dungeon, chosen.level, chosen.name))
	end)
end
