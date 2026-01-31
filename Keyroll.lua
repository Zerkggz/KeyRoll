local PREFIX = "|cff00ff00[KeyRoll]|r"
local CHANNEL = "KEYROLL_SYNC"

local ROLL_MESSAGES = {
    "Shaking the keystone bag...",
    "Consulting the ancient key spirits...",
    "Rolling for pain and glory...",
    "Deciding our fate..."
}

local WIN_MESSAGES = {
    "The keys have spoken!",
    "Destiny chooses:",
    "Tonight we suffer in:",    
}

local receivedKeys = {}

C_ChatInfo.RegisterAddonMessagePrefix(CHANNEL)

local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_ADDON")

-- Helper: get YOUR keystone safely (Midnight)
local function GetMyKeystone()
    local mapID = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local level = C_MythicPlus.GetOwnedKeystoneLevel()

    if mapID and level and level > 0 then
        return mapID, level
    end
end

frame:SetScript("OnEvent", function(_, _, prefix, message, _, sender)
    if prefix ~= CHANNEL then return end

    -- Someone is requesting keystones
    if message == "REQUEST" then
        local mapID, level = GetMyKeystone()
        if mapID and level then
            C_ChatInfo.SendAddonMessage(
                CHANNEL,
                mapID .. ":" .. level,
                IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
            )
        end
        return
    end

    -- Receiving a keystone
    local mapID, level = strsplit(":", message)
    mapID, level = tonumber(mapID), tonumber(level)

    if mapID and level and level > 0 then
        receivedKeys[sender] = {
            mapID = mapID,
            level = level,
            name = Ambiguate(sender, "short")
        }
    end
end)

SLASH_KEYROLL1 = "/keyroll"
SlashCmdList["KEYROLL"] = function()
    if not IsInGroup() then
        print(PREFIX .. " You must be in a party.")
        return
    end

    wipe(receivedKeys)

    -- Fun rolling message
    SendChatMessage(
        ROLL_MESSAGES[random(#ROLL_MESSAGES)],
        "PARTY"
    )

    -- Ask party for keys
    C_ChatInfo.SendAddonMessage(
        CHANNEL,
        "REQUEST",
        IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and "INSTANCE_CHAT" or "PARTY"
    )

    -- Add your own immediately
    local mapID, level = GetMyKeystone()
    if mapID and level then
        receivedKeys[UnitName("player")] = {
            mapID = mapID,
            level = level,
            name = UnitName("player")
        }
    end

    -- Roll after delay
    C_Timer.After(2, function()
        local keys = {}
        for _, key in pairs(receivedKeys) do
            table.insert(keys, key)
        end

        if #keys == 0 then
            print(PREFIX .. " No keystones received.")
            return
        end

        local chosen = keys[random(#keys)]
        local dungeonName = C_ChallengeMode.GetMapUIInfo(chosen.mapID) or "Unknown Dungeon"

        SendChatMessage(
            WIN_MESSAGES[random(#WIN_MESSAGES)] ..
            string.format(" %s +%d (from %s)", dungeonName, chosen.level, chosen.name),
            "PARTY"
        )
    end)
end
