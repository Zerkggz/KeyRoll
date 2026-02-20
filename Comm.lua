local function GetCurrentKeystoneFromBags()
    if not C_Container then return nil, nil, nil, nil end
    
    local fullPlayerName, realm = UnitFullName("player")
    local playerName
    if fullPlayerName and realm and realm ~= "" then
        playerName = fullPlayerName .. "-" .. realm
    else
        playerName = Ambiguate(UnitName("player"), "short")
    end
    
    local _, class = UnitClass("player")
    local mapID, level
    
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        if numSlots and numSlots > 0 then
            for slot = 1, numSlots do
                local itemLink = C_Container.GetContainerItemLink(bag, slot)
                if itemLink and itemLink:find("Keystone:") then
                    local dungeonName, keyLevel = itemLink:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
                    if dungeonName and keyLevel then
                        mapID = KeyRoll.GetDungeonIDByName(dungeonName)
                        level = tonumber(keyLevel)
                        if mapID and level then break end
                    end
                end
            end
        end
        if mapID and level then break end
    end
    
    return playerName, class, mapID, level
end

local function RequestPartyKeystones(force, silent)
    silent = silent or false
    if not KeyRoll.IsInRealParty() and not (force and KeyRoll.IsDebug()) then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Skipping keystone request: not in a real party")
        end
        return
    end

    local now = GetTime()
    if now - (KeyRoll.lastKeyRequestTime or 0) < KeyRoll.KEY_REQUEST_COOLDOWN then return end
    KeyRoll.lastKeyRequestTime = now

    local addons = {
        ["BigWigs"]="REQUEST_KEYS", ["BigWigsKey"]="REQUEST",
        ["DBM"]="KEY_REQUEST", ["DBM-Key"]="REQUEST",
        ["AngryKeystones"]="REQUEST", ["MDT"]="REQUEST_KEYS",
        ["AstralKeys"]="REQUEST"
    }

    -- Re-check party state before sending (can change between check above and here)
    if KeyRoll.IsInRealParty() then
        for prefix, msg in pairs(addons) do
            pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "PARTY")
        end
    end
    
    KeyRoll.BroadcastKeystoneToParty()
    KeyRoll.BroadcastKeystoneToFriends()
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Sent keystone requests to party (7 addon prefixes)")
    end
end

local unknownPrefixCounts = {}

local function HandleReceivedKeystone(prefix, message, sender)
    if not message or not sender then return end
    sender = Ambiguate(sender, "short")
    message = tostring(message)

    local function safeStore(mapID, level)
        mapID = tonumber(mapID)
        level = tonumber(level)
        if mapID and mapID > 0 and level and level > 0 then
            KeyRoll.StoreKey(sender, mapID, level)
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("Captured keystone:", sender, KeyRoll.GetDungeonNameByID(mapID), "+"..level)
            end
            return true
        end
        return false
    end

    local itemID = message:match("|Hitem:(%d+):")
    if itemID and tonumber(itemID) == 151086 then
        local dungeon, keyLevel = message:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
        if safeStore(KeyRoll.GetDungeonIDByName(dungeon), keyLevel) then return end
    end

    if LibStub then
        local AceSerializer = LibStub("AceSerializer-3.0", true)
        if AceSerializer then
            local success, decoded = AceSerializer:Deserialize(message)
            if success and type(decoded) == "table" and #decoded >= 2 then
                if safeStore(decoded[1], decoded[2]) then return end
            end
        end
    end

    local mapID, level
    local knownPrefixes = {
        ["LibKS"]=true, ["BigWigs"]=true, ["BigWigsKey"]=true,
        ["DBM"]=true, ["DBM-Key"]=true,
        ["AngryKeystones"]=true, ["MDT"]=true,
    }

    if prefix == "LibKS" then
        -- LibKS format: level,mapID,rating (not mapID,level!)
        local keyLevel, dungeonIndex = message:match("(%d+),(%d+),%d+")
        mapID, level = tonumber(dungeonIndex), tonumber(keyLevel)
    elseif prefix == "KCLib" then
        for num1, num2 in message:gmatch("(%d+)[%s,:|%-](%d+)") do
            local testMapID, testLevel = tonumber(num1), tonumber(num2)
            if testMapID and testMapID > 0 and testMapID < 1000 and testLevel and testLevel > 0 and testLevel <= 40 then
                mapID, level = testMapID, testLevel
                break
            end
        end
    elseif prefix == "AstralKeys" or prefix == "KeystoneManager" then
        mapID, level = message:match("(%d+)[%s,:](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "OpenRaidLib" or prefix == "ORL" then
        mapID, level = message:match("(%d+)[%s,:|%-](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "KeystoneAnnounce" then
        mapID, level = message:match("(%d+)[%s,:](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "BigWigs" or prefix == "BigWigsKey" then
        mapID, level = message:match("KEYSTONE[:=](%d+):(%d+)")
                     or message:match("map=(%d+).+level=(%d+)")
                     or message:match("^(%d+):(%d+)$")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "EQKS" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== Parsing EQKS Message ===")
            KeyRoll.DebugPrint("Message type:", type(message))
            KeyRoll.DebugPrint("Message length:", message and #message or "nil")
            KeyRoll.DebugPrint("Raw message:", tostring(message))
            if message and #message > 0 then
                KeyRoll.DebugPrint("First 100 chars:", message:sub(1, 100))
            end
        end
        if message and message ~= "" then
            mapID, level = message:match("(%d+)[%s,:](%d+)")
        end
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("EQKS parse result - MapID:", mapID, "Level:", level)
        end
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "DBM" or prefix == "DBM-Key"
        or prefix == "AngryKeystones" or prefix == "MDT" then
        mapID, level = message:match("(%d+):(%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    end

    if safeStore(mapID, level) then return end

    if not knownPrefixes[prefix] then
        mapID, level = message:match("(%d+)[%s,:](%d+)")
        if mapID and level then
            mapID, level = tonumber(mapID), tonumber(level)
            if mapID and mapID > 0 and mapID < 1000 and level and level > 0 and level < 100 then
                if safeStore(mapID, level) then
                    if KeyRoll.IsDebug() then
                        KeyRoll.DebugPrint("Captured via generic pattern from", prefix)
                    end
                    return
                end
            end
        end
        
        unknownPrefixCounts[prefix] = (unknownPrefixCounts[prefix] or 0) + 1
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Unknown addon prefix:", prefix, "count:", unknownPrefixCounts[prefix], "from", sender, "raw message:", message)
        end
    end
end

local AceComm = LibStub("AceComm-3.0", true)
local AceSerializer = LibStub("AceSerializer-3.0", true)
if not AceComm or not AceSerializer then
    print(KeyRoll.PREFIX, "Error: Ace3 libraries failed to load!")
    return
end

local KeyRollComm = {}

function KeyRollComm:OnCommReceived(prefix, message, distribution, sender)
    if prefix == "KeyRoll" and distribution == "GUILD" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== KeyRoll GUILD Message ===")
            KeyRoll.DebugPrint("From:", sender)
            KeyRoll.DebugPrint("Message:", message)
        end
        
        local msgType, name, class, mapID, level = message:match("^(%w+):([^:]+):([^:]+):(%d+):(%d+)")
        if msgType == "UPDATE" and name and mapID and level then
            mapID, level = tonumber(mapID), tonumber(level)
            if mapID and level then
                KeyRoll.StoreGuildKey(sender, mapID, level, class)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("KeyRoll update:", sender, "has", KeyRoll.GetDungeonNameByID(mapID) or "Unknown", "+"..level)
                end
            end
        end
        
        if message == "REQUEST" then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("KeyRoll guild request received, sending our keystone")
            end
            KeyRoll.BroadcastKeystoneToGuild()
            KeyRoll.BroadcastKeystoneToFriends()
        end
        
        return
    end
    
    if prefix == "KeyRoll" and distribution == "PARTY" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== KeyRoll PARTY Message ===")
            KeyRoll.DebugPrint("From:", sender)
            KeyRoll.DebugPrint("Message:", message)
        end
        
        local msgType, name, class, mapID, level = message:match("^(%w+):([^:]+):([^:]+):(%d+):(%d+)")
        if msgType == "UPDATE" and name and mapID and level then
            mapID, level = tonumber(mapID), tonumber(level)
            if mapID and level then
                KeyRoll.StoreKey(sender, mapID, level)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("KeyRoll party update:", sender, "has", KeyRoll.GetDungeonNameByID(mapID) or "Unknown", "+"..level)
                end
            end
        end
        
        if message == "REQUEST" then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("KeyRoll party request received, sending our keystone")
            end
            KeyRoll.BroadcastKeystoneToParty()
            KeyRoll.BroadcastKeystoneToFriends()
        end
        
        return
    end
    
    -- AstralKeys GUILD messages
    if prefix == "AstralKeys" and distribution == "GUILD" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== AstralKeys GUILD Message ===")
            KeyRoll.DebugPrint("From:", sender)
            KeyRoll.DebugPrint("Raw message length:", #message)
            KeyRoll.DebugPrint("First 200 chars:", message:sub(1, 200))
        end
        
        -- Single update: "updateV9 Name-Realm:CLASS:mapID:level:???:???:???"
        local updateMatch = message:match("^updateV9%s+(.+)")
        if updateMatch then
            local name, class, mapID, level = updateMatch:match("([^:]+):([^:]+):(%d+):(%d+)")
            if name and mapID and level then
                mapID, level = tonumber(mapID), tonumber(level)
                KeyRoll.StoreGuildKey(name, mapID, level, class)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("AstralKeys update:", name, "has", KeyRoll.GetDungeonNameByID(mapID) or "Unknown", "+"..level)
                end
            end
        end
        
        -- Bulk sync: "sync6 Player1:CLASS:mapID:level:..._Player2:..._Player3:..."
        local syncMatch = message:match("^sync6%s+(.+)")
        if syncMatch then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("AstralKeys sync: parsing bulk keystones")
            end
            for playerData in syncMatch:gmatch("([^_]+)") do
                local name, class, mapID, level = playerData:match("([^:]+):([^:]+):(%d+):(%d+)")
                if name and mapID and level then
                    mapID, level = tonumber(mapID), tonumber(level)
                    KeyRoll.StoreGuildKey(name, mapID, level, class)
                    if KeyRoll.IsDebug() then
                        KeyRoll.DebugPrint("  -", name, "has", KeyRoll.GetDungeonNameByID(mapID) or "Unknown", "+"..level)
                    end
                end
            end
        end
        
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("================================")
        end
        
        return
    end
    
    if distribution ~= "PARTY" then return end
    
    HandleReceivedKeystone(prefix, message, sender)
end

local ADDON_KEYROLL_PREFIXES = {
    ["KeyRoll"]=true,
    ["BigWigs"]=true, ["BigWigsKey"]=true, ["DBM"]=true, ["DBM-Key"]=true,
    ["AngryKeystones"]=true, ["MDT"]=true, ["LibKS"]=true,
    ["AstralKeys"]=true,
    ["KCLib"]=true,
    ["OpenRaidLib"]=true, ["ORL"]=true,
    ["KeystoneAnnounce"]=true,
    ["EQKS"]=true,
}

for prefix in pairs(ADDON_KEYROLL_PREFIXES) do
    AceComm:RegisterComm(prefix, function(...) KeyRollComm:OnCommReceived(...) end)
end

local genericFrame = CreateFrame("Frame")
genericFrame:RegisterEvent("CHAT_MSG_ADDON")

genericFrame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    if distribution ~= "PARTY" then return end
    if not KeyRoll.IsInRealParty() then return end
    if ADDON_KEYROLL_PREFIXES[prefix] then return end
    
    if message and type(message) == "string" and #message > 0 then
        local num1, num2 = message:match("(%d+)[%s,:|%-_](%d+)")
        if num1 and num2 then
            local mapID, level = tonumber(num1), tonumber(num2)
            if mapID and mapID > 0 and mapID < 1000 and level and level > 0 and level <= 40 then
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("Found potential keystone in generic message - MapID:", mapID, "Level:", level)
                end
                HandleReceivedKeystone(prefix, message, sender)
            end
        end
    end
end)

local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_PARTY")
chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
chatFrame:RegisterEvent("CHAT_MSG_OFFICER")

chatFrame:SetScript("OnEvent", function(_, event, message, sender)
    if not message or not sender then
        return
    end
    
    sender = Ambiguate(sender, "short")
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Chat received from:", sender, "Event:", event)
    end
    
    if message:find("Keystone:") then
        local itemLink = message:match("(|c.-|h%[Keystone:.-%]|h|r)")
        if itemLink then
            local dungeonName, keyLevel = itemLink:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
            
            if dungeonName and keyLevel then
                local mapID = KeyRoll.GetDungeonIDByName(dungeonName)
                local level = tonumber(keyLevel)
                
                if mapID and level then
                    local isGuildMember = KeyRoll.IsGuildMember and KeyRoll.IsGuildMember(sender)
                    local isPartyChat = (event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER")
                    local isGuildChat = (event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER")
                    local inParty = KeyRoll.IsInRealParty()
                    
                    if isPartyChat and inParty then
                        KeyRoll.StoreKey(sender, mapID, level)
                        if KeyRoll.IsDebug() then
                            KeyRoll.DebugPrint("Captured from party chat:", sender, dungeonName, "+"..level)
                        end
                        
                        if isGuildMember then
                            KeyRoll.StoreGuildKey(sender, mapID, level)
                            if KeyRoll.IsDebug() then
                                KeyRoll.DebugPrint("Also stored in guild cache (guild member in party)")
                            end
                        end
                    end
                    
                    if isGuildChat and isGuildMember then
                        KeyRoll.StoreGuildKey(sender, mapID, level)
                        if KeyRoll.IsDebug() then
                            KeyRoll.DebugPrint("Captured from guild chat:", sender, dungeonName, "+"..level)
                        end
                        
                        if inParty then
                            local currentParty = KeyRoll.GetCurrentPartyMembers()
                            if currentParty and currentParty[sender] then
                                KeyRoll.StoreKey(sender, mapID, level)
                                if KeyRoll.IsDebug() then
                                    KeyRoll.DebugPrint("Also stored in party cache (guild member in current party)")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end)

local bnetFrame = CreateFrame("Frame")
bnetFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
bnetFrame:RegisterEvent("PLAYER_LOGIN")

local registeredBNetPrefixes = {}

local friendMessageStats = {
    received = 0,
    parsed = 0,
    failed = 0,
}

bnetFrame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    if event == "PLAYER_LOGIN" then
        local prefixes = {
            "AstralKeys", "LibKS", "BigWigs", "BigWigsKey", 
            "DBM", "DBM-Key", "AngryKeystones", "MDT"
        }
        for _, p in ipairs(prefixes) do
            C_ChatInfo.RegisterAddonMessagePrefix(p)
            registeredBNetPrefixes[p] = true
        end
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Registered Battle.net addon prefixes for friend keystones")
        end
        return
    end
    
    if not message or message == "" then 
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("BN_CHAT_MSG_ADDON: Empty message received")
        end
        return 
    end
    if not registeredBNetPrefixes[prefix] then 
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("BN_CHAT_MSG_ADDON: Unregistered prefix:", prefix)
        end
        return 
    end
    
    friendMessageStats.received = friendMessageStats.received + 1
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("=== BN Friend Message Received (#" .. friendMessageStats.received .. ") ===")
        KeyRoll.DebugPrint("Prefix:", prefix)
        KeyRoll.DebugPrint("Sender (BNet):", sender)
        KeyRoll.DebugPrint("Message length:", #message)
        KeyRoll.DebugPrint("First 200 chars:", message:sub(1, 200))
        local hexDump = ""
        for i = 1, math.min(32, #message) do
            hexDump = hexDump .. string.format("%02X ", message:byte(i))
        end
        KeyRoll.DebugPrint("Hex dump (first 32 bytes):", hexDump)
        if message:match("^%d+[%s,:]%d+") then
            KeyRoll.DebugPrint("Format: Looks like 'mapID separator level'")
        elseif message:match("^update") then
            KeyRoll.DebugPrint("Format: Looks like AstralKeys 'updateVX ...'")
        elseif message:byte(1) < 32 or message:byte(1) > 126 then
            KeyRoll.DebugPrint("Format: Binary/serialized data")
        else
            KeyRoll.DebugPrint("Format: Unknown text format")
        end
    end
    
    local charName, mapID, keyLevel, class
    
    -- Astral Keys format: "updateV8 CharName-Realm:Class:MapID:KeyLevel:..."
    if prefix == "AstralKeys" then
        local updateVersion, data = message:match("^(%S+)%s+(.+)$")
        if updateVersion and data then
            charName, class, mapID, keyLevel = data:match("([^:]+):([^:]+):(%d+):(%d+)")
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("AstralKeys parse result - Name:", charName, "Class:", class, "MapID:", mapID, "Level:", keyLevel)
            end
        end
    end
    
    if not mapID and LibStub then
        local AceSerializer = LibStub("AceSerializer-3.0", true)
        if AceSerializer then
            local success, decoded = AceSerializer:Deserialize(message)
            if success and type(decoded) == "table" and #decoded >= 2 then
                mapID = tonumber(decoded[1])
                keyLevel = tonumber(decoded[2])
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("AceSerializer parse result - MapID:", mapID, "Level:", keyLevel)
                end
            end
        end
    end
    
    if not mapID then
        mapID, keyLevel = message:match("(%d+)%s+(%d+)")
        if not mapID then
            mapID, keyLevel = message:match("(%d+):(%d+)")
        end
        if mapID and KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Generic pattern parse result - MapID:", mapID, "Level:", keyLevel)
        end
    end
    
    mapID = tonumber(mapID)
    keyLevel = tonumber(keyLevel)
    
    if not mapID or mapID <= 0 or not keyLevel or keyLevel <= 0 then
        friendMessageStats.failed = friendMessageStats.failed + 1
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("FAILED to parse friend keystone from prefix:", prefix)
            KeyRoll.DebugPrint("Final parsed values - MapID:", mapID, "Level:", keyLevel)
            KeyRoll.DebugPrint("Stats: Received:", friendMessageStats.received, "Parsed:", friendMessageStats.parsed, "Failed:", friendMessageStats.failed)
        end
        return
    end
    
    if not charName then
        charName = sender
        local extractedName = message:match("([%w%-]+):")
        if extractedName and extractedName:find("%-") then
            charName = extractedName
        end
    end
    
    local fullName = charName
    local shortName = Ambiguate(charName, "short")
    local realm = charName:match("%-(.+)$")
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    KeyRollGlobalDB.friendCache[shortName] = {
        name = shortName,
        fullName = fullName,
        realm = realm,
        class = class,
        mapID = mapID,
        level = keyLevel,
        dungeon = dungeon,
        time = time(),
        source = prefix:lower(),
    }
    
    if KeyRoll.IsGuildMember and KeyRoll.IsGuildMember(shortName) then
        KeyRoll.StoreGuildKey(fullName, mapID, keyLevel, class)
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Also stored in guild cache (friend is guild member)")
        end
    end
    
    friendMessageStats.parsed = friendMessageStats.parsed + 1
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("SUCCESS: Stored friend keystone")
        KeyRoll.DebugPrint("Character:", charName)
        KeyRoll.DebugPrint("Dungeon:", dungeon)
        KeyRoll.DebugPrint("Level: +"..keyLevel)
        KeyRoll.DebugPrint("Source:", prefix)
        KeyRoll.DebugPrint("Stats: Received:", friendMessageStats.received, "Parsed:", friendMessageStats.parsed, "Failed:", friendMessageStats.failed)
        KeyRoll.DebugPrint("Success rate:", string.format("%.1f%%", (friendMessageStats.parsed / friendMessageStats.received) * 100))
    end
    
    if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
        KeyRoll.StoredFrame:Refresh()
    end
end)

local friendLoginFrame = CreateFrame("Frame")
friendLoginFrame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
friendLoginFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")

local friendRequestTimes = {}
local FRIEND_REQUEST_COOLDOWN = 15

friendLoginFrame:SetScript("OnEvent", function(_, event, bnetIDAccount)
    if not bnetIDAccount then return end
    
    local now = GetTime()
    local lastRequest = friendRequestTimes[bnetIDAccount] or 0
    if now - lastRequest < FRIEND_REQUEST_COOLDOWN then
        return
    end
    friendRequestTimes[bnetIDAccount] = now
    
    local accountInfo = C_BattleNet.GetFriendAccountInfo(bnetIDAccount)
    if not accountInfo then return end
    
    if not accountInfo.gameAccountInfo or not accountInfo.gameAccountInfo.isOnline then
        return
    end
    
    local gameAccountInfo = accountInfo.gameAccountInfo
    if gameAccountInfo.clientProgram ~= BNET_CLIENT_WOW then
        return
    end
    
    if KeyRoll.IsDebug() then
        local charName = gameAccountInfo.characterName or "Unknown"
        local realmName = gameAccountInfo.realmName or ""
        local fullName = charName .. (realmName ~= "" and "-" .. realmName or "")
        KeyRoll.DebugPrint("=== Friend Came Online ===")
        KeyRoll.DebugPrint("Friend:", fullName)
        KeyRoll.DebugPrint("BNet Account ID:", bnetIDAccount)
        KeyRoll.DebugPrint("Client:", gameAccountInfo.clientProgram)
        KeyRoll.DebugPrint("Realm:", realmName)
    end
    
    local addons = {
        "AstralKeys", "LibKS", "BigWigs", "BigWigsKey",
        "DBM", "DBM-Key", "AngryKeystones", "MDT"
    }
    
    local sentCount = 0
    for _, addonPrefix in ipairs(addons) do
        local success = pcall(function()
            BNSendGameData(bnetIDAccount, addonPrefix, "REQUEST")
        end)
        
        if success then
            sentCount = sentCount + 1
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("  Sent REQUEST via", addonPrefix)
            end
        elseif KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("  Failed to send via", addonPrefix)
        end
    end
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Total requests sent:", sentCount .. "/" .. #addons)
    end
end)

-- Guild chat !keys command listener
local guildChatFrame = CreateFrame("Frame")
guildChatFrame:RegisterEvent("CHAT_MSG_GUILD")
guildChatFrame:RegisterEvent("CHAT_MSG_OFFICER")

local lastGuildRequestTime = 0
local GUILD_REQUEST_COOLDOWN = 15

guildChatFrame:SetScript("OnEvent", function(_, event, message, sender)
    if not message then return end
    
    local lowerMsg = message:lower()
    if lowerMsg == "!keys" or lowerMsg == "!key" or lowerMsg:match("^!keys%s") then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Guild keys request detected from:", sender)
        end
        
        local now = GetTime()
        if now - lastGuildRequestTime < GUILD_REQUEST_COOLDOWN then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("Guild request on cooldown, ignoring")
            end
            return
        end
        lastGuildRequestTime = now
        
        if KeyRoll.CaptureMyKeystone then
            KeyRoll.CaptureMyKeystone()
        end
        
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Listening for guild keystone responses...")
        end
    end
end)

local function RequestFriendKeystones()
    local numBNetTotal, numBNetOnline = BNGetNumFriends()
    if not numBNetOnline or numBNetOnline == 0 then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("No Battle.net friends online to request from")
        end
        return
    end
    
    local addons = {
        "AstralKeys", "LibKS", "BigWigs", "BigWigsKey",
        "DBM", "DBM-Key", "AngryKeystones", "MDT"
    }
    
    local requestCount = 0
    
    -- Use numBNetTotal for iteration, filter by isOnline inside the loop
    for i = 1, numBNetTotal do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local gameAccountInfo = accountInfo.gameAccountInfo
            
            if gameAccountInfo.clientProgram == BNET_CLIENT_WOW then
                local bnetIDAccount = accountInfo.bnetAccountID
                
                for _, addonPrefix in ipairs(addons) do
                    local success = pcall(function()
                        BNSendGameData(bnetIDAccount, addonPrefix, "REQUEST")
                    end)
                    
                    if success then
                        requestCount = requestCount + 1
                    end
                end
                
                if KeyRoll.IsDebug() then
                    local charName = gameAccountInfo.characterName or "Unknown"
                    KeyRoll.DebugPrint("Requested keystone from friend:", charName)
                end
            end
        end
    end
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Sent", requestCount, "keystone requests to online friends")
    end
end

local function RequestGuildKeystones()
    if not IsInGuild() then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Not in a guild, cannot request guild keystones")
        end
        return false
    end
    
    local success = pcall(function()
        SendChatMessage("!keys", "GUILD")
    end)
    
    if success then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Sent !keys request to guild chat")
        end
        return true
    else
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Failed to send !keys to guild chat")
        end
        return false
    end
end

KeyRoll.RequestPartyKeystones = RequestPartyKeystones
KeyRoll.RequestFriendKeystones = RequestFriendKeystones
KeyRoll.RequestGuildKeystones = RequestGuildKeystones
KeyRoll.HandleReceivedKeystone = HandleReceivedKeystone

KeyRoll.GetFriendMessageStats = function()
    return friendMessageStats
end

local lastGuildBroadcast = 0
local GUILD_BROADCAST_COOLDOWN = 15

local function BroadcastKeystoneToGuild()
    if not IsInGuild() then return end
    
    local now = GetTime()
    if now - lastGuildBroadcast < GUILD_BROADCAST_COOLDOWN then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Guild broadcast on cooldown")
        end
        return
    end
    lastGuildBroadcast = now
    
    local playerName, class, mapID, level = GetCurrentKeystoneFromBags()
    if not mapID or not level then return end
    
    local message = string.format("UPDATE:%s:%s:%d:%d", playerName, class or "UNKNOWN", mapID, level)
    AceComm:SendCommMessage("KeyRoll", message, "GUILD")
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Broadcasted to guild:", KeyRoll.GetDungeonNameByID(mapID), "+"..level)
    end
end

local function RequestGuildKeystonesFromAddon()
    if not IsInGuild() then return end
    
    AceComm:SendCommMessage("KeyRoll", "REQUEST", "GUILD")
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Sent KeyRoll REQUEST to guild")
    end
end

local lastPartyBroadcast = 0
local PARTY_BROADCAST_COOLDOWN = 5

local function BroadcastKeystoneToParty()
    if not KeyRoll.IsInRealParty() then return end
    
    local now = GetTime()
    if now - lastPartyBroadcast < PARTY_BROADCAST_COOLDOWN then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Party broadcast on cooldown")
        end
        return
    end
    lastPartyBroadcast = now
    
    local playerName, class, mapID, level = GetCurrentKeystoneFromBags()
    if not mapID or not level then return end
    
    local message = string.format("UPDATE:%s:%s:%d:%d", playerName, class or "UNKNOWN", mapID, level)
    AceComm:SendCommMessage("KeyRoll", message, "PARTY")
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Broadcasted to party:", KeyRoll.GetDungeonNameByID(mapID), "+"..level)
    end
end

local lastFriendBroadcast = 0
local FRIEND_BROADCAST_COOLDOWN = 30

local function BroadcastKeystoneToFriends()
    local now = GetTime()
    if now - lastFriendBroadcast < FRIEND_BROADCAST_COOLDOWN then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Friend broadcast on cooldown")
        end
        return
    end
    lastFriendBroadcast = now
    
    local playerName, class, mapID, level = GetCurrentKeystoneFromBags()
    if not mapID or not level then return end
    
    local message = string.format("UPDATE:%s:%s:%d:%d", playerName, class or "UNKNOWN", mapID, level)
    
    local _, numBNetOnline = BNGetNumFriends()
    for i = 1, numBNetOnline do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            BNSendGameData(accountInfo.bnetAccountID, "KeyRoll", message)
        end
    end
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Broadcasted to friends:", KeyRoll.GetDungeonNameByID(mapID), "+"..level)
    end
end

KeyRoll.BroadcastKeystoneToGuild = BroadcastKeystoneToGuild
KeyRoll.BroadcastKeystoneToParty = BroadcastKeystoneToParty
KeyRoll.BroadcastKeystoneToFriends = BroadcastKeystoneToFriends
KeyRoll.RequestGuildKeystonesFromAddon = RequestGuildKeystonesFromAddon