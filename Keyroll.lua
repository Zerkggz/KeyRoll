local PREFIX = "|cff00ff00[KeyRoll]|r"

KeyRollDB = KeyRollDB or {}
local cache = KeyRollDB
local lastRequestZone
local lastPartyMembers = {}

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
    for _, key in pairs(cache) do
        table.insert(keys, key)
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
local function ParseAddonKeystone(prefix, message, sender)
    if type(message) ~= "string" or not sender then return end
    sender = Ambiguate(sender, "short")

    local mapID, level

    -- LibKS format: level,mapID,...
    if prefix == "LibKS" then
        level, mapID = message:match("^(%d+),(%d+)")
        level, mapID = tonumber(level), tonumber(mapID)

    -- BigWigs / MDT / DBM-Key fallback formats
    else
        mapID, level =
            message:match("KEYSTONE:(%d+):(%d+)") or
            message:match("map=(%d+).+level=(%d+)") or
            message:match("(%d+):(%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    end

    if mapID and level and level > 0 then
        StoreKey(sender, mapID, level)
        DebugPrint("Stored keystone:", sender, mapID, level)
    end
end

-------------------------------------------------
-- Request keystones from addons
-------------------------------------------------
local function RequestPartyKeystones()
    if not IsInGroup() and not DEBUG_MODE then return end
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
local function ManualCapture()
    if not IsInGroup() and not DEBUG_MODE then
        print(PREFIX, "You must be in a party to capture keys.")
        return
    end
	SafeSend("Requesting party keystones...")
    DebugPrint("Manually capturing party keys...")
    RequestPartyKeystones()
end



-------------------------------------------------
-- Event frame
-------------------------------------------------
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

frame:SetScript("OnEvent", function(_, event, prefix, message, _, sender)
    if event == "CHAT_MSG_ADDON" then
        if IsDebug() then DebugPrint("Received addon message:", prefix, message, "from", sender) end
        ParseAddonKeystone(prefix, message, sender)
        return
    end

    -- Only prune when someone leaves or joins
    if event == "GROUP_ROSTER_UPDATE" then
        PruneCache()
        RequestPartyKeystones()
        return
    end

    -- Refresh keys when entering world or changing zones (like when leaving a dungeon)
    if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        RequestPartyKeystones()
        return
    end

    -- Update cache at dungeon completion
    if event == "CHALLENGE_MODE_COMPLETED" then
        DebugPrint("Dungeon completed – updating party keystones")
        PruneCache()             -- remove any members who left mid-dungeon
        RequestPartyKeystones()  -- refresh keys from current party
		C_Timer.After(30, function()
			ManualCapture()  -- safely requests keys again
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

    -- Default roll
	if #keys == 0 then
		SafeSend("No party keystones known. Ask players to link keys.", true)
		return
	end

	-- Pick a random flavor message safely
	local rollMessage = ROLL_MESSAGES[math.random(#ROLL_MESSAGES)]
	SendFlavor(rollMessage)

	C_Timer.After(1.5, function()
		local chosen = keys[math.random(#keys)]
		local dungeon = GetDungeonName(chosen.mapID)
		local winMessage = WIN_MESSAGES[math.random(#WIN_MESSAGES)]
		SendFlavor(winMessage .. string.format(" %s +%d (from %s)", dungeon, chosen.level, chosen.name))
	end)
end
