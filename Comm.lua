-------------------------------------------------
-- Request party keystones (best-effort)
-------------------------------------------------
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
        ["AngryKeystones"]="REQUEST", ["MDT"]="REQUEST_KEYS"
    }

    for prefix, msg in pairs(addons) do
        pcall(C_ChatInfo.SendAddonMessage, prefix, msg, "PARTY")
    end
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Sent keystone requests to party (6 addon prefixes)")
    end
end

-------------------------------------------------
-- Handle received keystones
-------------------------------------------------
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

    -- Try parsing as item link
    local itemID = message:match("|Hitem:(%d+):")
    if itemID and tonumber(itemID) == 151086 then  -- Updated for Midnight (was 180653 in TWW)
        local dungeon, keyLevel = message:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
        if safeStore(KeyRoll.GetDungeonIDByName(dungeon), keyLevel) then return end
    end

    -- Try AceSerializer
    if LibStub then
        local AceSerializer = LibStub("AceSerializer-3.0", true)
        if AceSerializer then
            local success, decoded = AceSerializer:Deserialize(message)
            if success and type(decoded) == "table" and #decoded >= 2 then
                if safeStore(decoded[1], decoded[2]) then return end
            end
        end
    end

    -- Regex fallbacks for known addon prefixes
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
        -- Keystone Roll-Call uses LibKeystoneCommunication
        -- Format appears to be comma-separated with mapID somewhere in the message
        -- Example from error logs: "1,153-07468DE1,Atriana-Gnomeregan,120,1,11,Fatal Nemesis,440,438,114,353,12,353,0,4,..."
        -- The numbers after character data might be keystone info
        -- Try to find two reasonable numbers (mapID 1-999, level 1-40)
        for num1, num2 in message:gmatch("(%d+)[%s,:|%-](%d+)") do
            local testMapID, testLevel = tonumber(num1), tonumber(num2)
            if testMapID and testMapID > 0 and testMapID < 1000 and testLevel and testLevel > 0 and testLevel <= 40 then
                mapID, level = testMapID, testLevel
                break
            end
        end
    elseif prefix == "AstralKeys" or prefix == "KeystoneManager" then
        -- These addons likely use similar formats
        -- Try common patterns: "mapID:level" or "mapID,level" or "mapID level"
        mapID, level = message:match("(%d+)[%s,:](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "OpenRaidLib" or prefix == "ORL" then
        -- Open Raid Library (used by Details!)
        -- Format unknown, try generic number pattern
        mapID, level = message:match("(%d+)[%s,:|%-](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "KeystoneAnnounce" then
        -- Keystone Announce format unknown, try generic
        mapID, level = message:match("(%d+)[%s,:](%d+)")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "BigWigs" or prefix == "BigWigsKey" then
        mapID, level = message:match("KEYSTONE[:=](%d+):(%d+)")
                     or message:match("map=(%d+).+level=(%d+)")
                     or message:match("^(%d+):(%d+)$")
        mapID, level = tonumber(mapID), tonumber(level)
    elseif prefix == "EQKS" then
        -- BigWigs Keystone format: often "mapID:level" or similar
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

    -- Track unknown prefixes for debug
    if not knownPrefixes[prefix] then
        -- Try generic number patterns as a last resort
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

-------------------------------------------------
-- AceComm registration (spontaneous only)
-------------------------------------------------
local AceComm = LibStub("AceComm-3.0", true)
local AceSerializer = LibStub("AceSerializer-3.0", true)
if not AceComm or not AceSerializer then
    print(KeyRoll.PREFIX, "Error: Ace3 libraries failed to load!")
    return
end

local KeyRollComm = {}

function KeyRollComm:OnCommReceived(prefix, message, distribution, sender)
    -- Parse KeyRoll GUILD messages for guild keystone tracking
    if prefix == "KeyRoll" and distribution == "GUILD" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== KeyRoll GUILD Message ===")
            KeyRoll.DebugPrint("From:", sender)
            KeyRoll.DebugPrint("Message:", message)
        end
        
        -- Format: "UPDATE:CharName:CLASS:mapID:level"
        local msgType, name, class, mapID, level = message:match("^(%w+):([^:]+):([^:]+):(%d+):(%d+)")
        if msgType == "UPDATE" and name and mapID and level then
            mapID, level = tonumber(mapID), tonumber(level)
            if mapID and level then
                KeyRoll.StoreGuildKey(name, mapID, level, class)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("KeyRoll update:", name, "has", KeyRoll.GetDungeonNameByID(mapID) or "Unknown", "+"..level)
                end
            end
        end
        
        -- Format: "REQUEST" - someone is asking for keystones
        if message == "REQUEST" then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("KeyRoll guild request received, sending our keystone")
            end
            -- Broadcast our keystone if we have one
            KeyRoll.BroadcastKeystoneToGuild()
        end
        
        return
    end
    
    -- Parse AstralKeys GUILD messages for friend/guild keystone tracking
    if prefix == "AstralKeys" and distribution == "GUILD" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("=== AstralKeys GUILD Message ===")
            KeyRoll.DebugPrint("From:", sender)
            KeyRoll.DebugPrint("Raw message length:", #message)
            KeyRoll.DebugPrint("First 200 chars:", message:sub(1, 200))
        end
        
        -- Parse updateV9: single keystone update
        -- Format: updateV9 Name-Realm:CLASS:mapID:level:???:???:???
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
        
        -- Parse sync6: bulk keystone sync
        -- Format: sync6 Player1:CLASS:mapID:level:???:???:???:???_Player2:..._Player3:...
        local syncMatch = message:match("^sync6%s+(.+)")
        if syncMatch then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("AstralKeys sync: parsing bulk keystones")
            end
            -- Split by underscore to get individual player entries
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
    
    -- Only process PARTY messages for party keystone capture
    if distribution ~= "PARTY" then return end
    
    HandleReceivedKeystone(prefix, message, sender)
    -- NO REQUEST_KEYS reply logic: requests are best-effort only
end

local ADDON_KEYROLL_PREFIXES = {
    ["KeyRoll"]=true,  -- My addon for broadcasting
    ["BigWigs"]=true, ["BigWigsKey"]=true, ["DBM"]=true, ["DBM-Key"]=true,
    ["AngryKeystones"]=true, ["MDT"]=true, ["LibKS"]=true,
    ["AstralKeys"]=true,  -- Astral Keys & Keystone Manager
    ["KCLib"]=true,  -- Keystone Roll-Call
    ["OpenRaidLib"]=true, ["ORL"]=true,  -- Open Raid Library (Details!)
    ["KeystoneAnnounce"]=true,
    ["EQKS"]=true,  -- BigWigs Keystone Sharing (EuropaQKeystone)
}

for prefix in pairs(ADDON_KEYROLL_PREFIXES) do
    AceComm:RegisterComm(prefix, function(...) KeyRollComm:OnCommReceived(...) end)
end

-------------------------------------------------
-- Generic addon message listener
-------------------------------------------------
local genericFrame = CreateFrame("Frame")
genericFrame:RegisterEvent("CHAT_MSG_ADDON")

genericFrame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    -- Only process PARTY addon messages (not RAID/GUILD to avoid spam)
    if distribution ~= "PARTY" then return end
    
    -- Only process if in a real party
    if not KeyRoll.IsInRealParty() then return end
    
    -- Skip if this is one we're already handling via AceComm
    if ADDON_KEYROLL_PREFIXES[prefix] then return end
    
    -- Try to handle any message that might contain keystone data
    if message and type(message) == "string" and #message > 0 then
        -- Look for patterns that suggest keystone data:
        -- 1. Two numbers separated by common delimiters
        -- 2. First number (mapID) should be 1-1000
        -- 3. Second number (level) should be 1-40
        local num1, num2 = message:match("(%d+)[%s,:|%-_](%d+)")
        if num1 and num2 then
            local mapID, level = tonumber(num1), tonumber(num2)
            -- Validate ranges to avoid false positives
            if mapID and mapID > 0 and mapID < 1000 and level and level > 0 and level <= 40 then
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("Found potential keystone in generic message - MapID:", mapID, "Level:", level)
                end
                -- Try to parse it through the normal handler
                HandleReceivedKeystone(prefix, message, sender)
            end
        end
    end
end)

-------------------------------------------------
-- Chat monitoring for keystone links
-------------------------------------------------
local chatFrame = CreateFrame("Frame")
chatFrame:RegisterEvent("CHAT_MSG_PARTY")
chatFrame:RegisterEvent("CHAT_MSG_PARTY_LEADER")
chatFrame:RegisterEvent("CHAT_MSG_GUILD")
chatFrame:RegisterEvent("CHAT_MSG_OFFICER")

chatFrame:SetScript("OnEvent", function(_, event, message, sender)
    -- Validate parameters exist
    if not message or not sender then
        return
    end
    
    -- Safely ambiguate sender name (can fail during tainted execution)
    local success, ambiguatedName = pcall(Ambiguate, sender, "short")
    if not success or not ambiguatedName then
        return
    end
    sender = ambiguatedName
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Chat received from:", sender, "Event:", event)
    end
    
    -- Check if message contains a keystone link
    if message:find("Keystone:") then
        -- Extract the keystone link
        local itemLink = message:match("(|c.-|h%[Keystone:.-%]|h|r)")
        if itemLink then
            -- Parse dungeon name and level
            local dungeonName, keyLevel = itemLink:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
            
            if dungeonName and keyLevel then
                local mapID = KeyRoll.GetDungeonIDByName(dungeonName)
                local level = tonumber(keyLevel)
                
                if mapID and level then
                    local isGuildMember = KeyRoll.IsGuildMember and KeyRoll.IsGuildMember(sender)
                    local isPartyChat = (event == "CHAT_MSG_PARTY" or event == "CHAT_MSG_PARTY_LEADER")
                    local isGuildChat = (event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER")
                    local inParty = KeyRoll.IsInRealParty()
                    
                    -- Party chat handling
                    if isPartyChat and inParty then
                        KeyRoll.StoreKey(sender, mapID, level)
                        if KeyRoll.IsDebug() then
                            KeyRoll.DebugPrint("Captured from party chat:", sender, dungeonName, "+"..level)
                        end
                        
                        -- Also store in guild cache if sender is a guild member
                        if isGuildMember then
                            KeyRoll.StoreGuildKey(sender, mapID, level)
                            if KeyRoll.IsDebug() then
                                KeyRoll.DebugPrint("Also stored in guild cache (guild member in party)")
                            end
                        end
                    end
                    
                    -- Guild chat handling
                    if isGuildChat and isGuildMember then
                        KeyRoll.StoreGuildKey(sender, mapID, level)
                        if KeyRoll.IsDebug() then
                            KeyRoll.DebugPrint("Captured from guild chat:", sender, dungeonName, "+"..level)
                        end
                        
                        -- Also store in party cache if in party together
                        if inParty then
                            -- Check if sender is actually in our current party
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

-------------------------------------------------
-- Battle.net friend monitoring (multi-addon support)
-------------------------------------------------
local bnetFrame = CreateFrame("Frame")
bnetFrame:RegisterEvent("BN_CHAT_MSG_ADDON")
bnetFrame:RegisterEvent("PLAYER_LOGIN")

-- Track registered prefixes for friends
local registeredBNetPrefixes = {}

-- Debug statistics
local friendMessageStats = {
    received = 0,
    parsed = 0,
    failed = 0,
}

bnetFrame:SetScript("OnEvent", function(_, event, prefix, message, distribution, sender)
    if event == "PLAYER_LOGIN" then
        -- Register for all known addon prefixes that might broadcast to friends
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
    
    -- BN_CHAT_MSG_ADDON
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
        -- Show hex dump of first 32 bytes to see exact format
        local hexDump = ""
        for i = 1, math.min(32, #message) do
            hexDump = hexDump .. string.format("%02X ", message:byte(i))
        end
        KeyRoll.DebugPrint("Hex dump (first 32 bytes):", hexDump)
        -- Check if it looks like a known format
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
    
    -- Try Astral Keys format first: "updateV8 CharName-Realm:Class:MapID:KeyLevel:WeeklyBest:Week:MplusScore:Faction"
    if prefix == "AstralKeys" then
        local updateVersion, data = message:match("^(%S+)%s+(.+)$")
        if updateVersion and data then
            charName, class, mapID, keyLevel = data:match("([^:]+):([^:]+):(%d+):(%d+)")
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("AstralKeys parse result - Name:", charName, "Class:", class, "MapID:", mapID, "Level:", keyLevel)
            end
        end
    end
    
    -- Try AceSerializer for cross-faction messages
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
    
    -- Try generic patterns for other addons
    if not mapID then
        -- LibKS, BigWigs, etc: "mapID level"
        mapID, keyLevel = message:match("(%d+)%s+(%d+)")
        if not mapID then
            -- DBM, AngryKeystones: "mapID:level"
            mapID, keyLevel = message:match("(%d+):(%d+)")
        end
        if mapID and KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Generic pattern parse result - MapID:", mapID, "Level:", keyLevel)
        end
    end
    
    -- Convert and validate
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
    
    -- Try to get character name if we don't have it
    if not charName then
        -- BNet sender format is like "BNet-Account-123"
        -- We need to look up their character name
        charName = sender -- Fallback to BNet ID if we can't get character name
        
        -- Try to extract from Astral Keys format in message
        local extractedName = message:match("([%w%-]+):")
        if extractedName and extractedName:find("%-") then
            charName = extractedName
        end
    end
    
    charName = Ambiguate(charName, "short")
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    -- Store in friend cache
    KeyRollGlobalDB.friendCache[charName] = {
        name = charName,
        class = class,  -- May be nil for non-Astral Keys
        mapID = mapID,
        level = keyLevel,
        dungeon = dungeon,
        time = time(),
        source = prefix:lower(),  -- Track which addon sent it
    }
    
    -- Also store in guild cache if friend is a guild member
    if KeyRoll.IsGuildMember and KeyRoll.IsGuildMember(charName) then
        KeyRoll.StoreGuildKey(charName, mapID, keyLevel, class)
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
    
    -- Refresh UI if shown
    if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
        KeyRoll.StoredFrame:Refresh()
    end
end)

-------------------------------------------------
-- Friend login detection
-------------------------------------------------
local friendLoginFrame = CreateFrame("Frame")
friendLoginFrame:RegisterEvent("BN_FRIEND_ACCOUNT_ONLINE")
friendLoginFrame:RegisterEvent("BN_FRIEND_INFO_CHANGED")

-- Track last request time per friend to avoid spam
local friendRequestTimes = {}
local FRIEND_REQUEST_COOLDOWN = 15  -- 15 seconds between requests per friend

friendLoginFrame:SetScript("OnEvent", function(_, event, bnetIDAccount)
    if not bnetIDAccount then return end
    
    -- Check cooldown for this specific friend
    local now = GetTime()
    local lastRequest = friendRequestTimes[bnetIDAccount] or 0
    if now - lastRequest < FRIEND_REQUEST_COOLDOWN then
        return
    end
    friendRequestTimes[bnetIDAccount] = now
    
    -- Get friend info
    local accountInfo = C_BattleNet.GetFriendAccountInfo(bnetIDAccount)
    if not accountInfo then return end
    
    -- Check if friend is online and in WoW
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
    
    -- Request keystones from all known addons via BNet
    local addons = {
        "AstralKeys", "LibKS", "BigWigs", "BigWigsKey",
        "DBM", "DBM-Key", "AngryKeystones", "MDT"
    }
    
    local sentCount = 0
    for _, prefix in ipairs(addons) do
        local success = pcall(function()
            BNSendGameData(bnetIDAccount, prefix, "REQUEST")
        end)
        
        if success then
            sentCount = sentCount + 1
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("  Sent REQUEST via", prefix)
            end
        elseif KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("  Failed to send via", prefix)
        end
    end
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Total requests sent:", sentCount .. "/" .. #addons)
    end
end)

-------------------------------------------------
-- Guild chat command system
-------------------------------------------------
local guildChatFrame = CreateFrame("Frame")
guildChatFrame:RegisterEvent("CHAT_MSG_GUILD")
guildChatFrame:RegisterEvent("CHAT_MSG_OFFICER")

-- Track when we send requests to avoid spam
local lastGuildRequestTime = 0
local GUILD_REQUEST_COOLDOWN = 15  -- 15 seconds between guild-wide requests

guildChatFrame:SetScript("OnEvent", function(_, event, message, sender)
    if not message then return end
    
    -- Check if someone is asking for keys
    local lowerMsg = message:lower()
    if lowerMsg == "!keys" or lowerMsg == "!key" or lowerMsg:match("^!keys%s") then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Guild keys request detected from:", sender)
        end
        
        -- Don't spam - respect cooldown
        local now = GetTime()
        if now - lastGuildRequestTime < GUILD_REQUEST_COOLDOWN then
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("Guild request on cooldown, ignoring")
            end
            return
        end
        lastGuildRequestTime = now
        
        -- Respond with our keystone if we have one
        if KeyRoll.CaptureMyKeystone then
            KeyRoll.CaptureMyKeystone()
        end
        
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Listening for guild keystone responses...")
        end
    end
end)

-------------------------------------------------
-- Request keystones from all online Battle.net friends
-------------------------------------------------
local function RequestFriendKeystones()
    local _, numBNetOnline = BNGetNumFriends()
    if numBNetOnline == 0 then
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
    
    -- Loop through all Battle.net friends
    for i = 1, BNGetNumFriends() do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
            local gameAccountInfo = accountInfo.gameAccountInfo
            
            -- Only request from friends playing WoW
            if gameAccountInfo.clientProgram == BNET_CLIENT_WOW then
                local bnetIDAccount = accountInfo.bnetAccountID
                
                -- Send request to all known addon prefixes
                for _, prefix in ipairs(addons) do
                    local success = pcall(function()
                        BNSendGameData(bnetIDAccount, prefix, "REQUEST")
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

-------------------------------------------------
-- Request keystones from guild via chat command
-------------------------------------------------
local function RequestGuildKeystones()
    if not IsInGuild() then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Not in a guild, cannot request guild keystones")
        end
        return false
    end
    
    -- Send the !keys command to guild chat
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

-- Export friend message stats for debugging
KeyRoll.GetFriendMessageStats = function()
    return friendMessageStats
end

-------------------------------------------------
-- Guild Broadcasting
-------------------------------------------------
local lastGuildBroadcast = 0
local GUILD_BROADCAST_COOLDOWN = 15  -- 15 seconds between broadcasts

local function BroadcastKeystoneToGuild()
    if not IsInGuild() then return end
    
    -- Throttle broadcasts
    local now = GetTime()
    if now - lastGuildBroadcast < GUILD_BROADCAST_COOLDOWN then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Guild broadcast on cooldown")
        end
        return
    end
    lastGuildBroadcast = now
    
    -- Get our current keystone from bag scan
    if not C_Container then return end
    
    local playerName = Ambiguate(UnitName("player"), "short")
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
    
    -- Broadcast if we have a keystone
    if mapID and level then
        local message = string.format("UPDATE:%s:%s:%d:%d", playerName, class or "UNKNOWN", mapID, level)
        AceComm:SendCommMessage("KeyRoll", message, "GUILD")
        
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Broadcasted to guild:", KeyRoll.GetDungeonNameByID(mapID), "+"..level)
        end
    end
end

-- Request keystones from all guild members running KeyRoll
local function RequestGuildKeystonesFromAddon()
    if not IsInGuild() then return end
    
    AceComm:SendCommMessage("KeyRoll", "REQUEST", "GUILD")
    
    if KeyRoll.IsDebug() then
        KeyRoll.DebugPrint("Sent KeyRoll REQUEST to guild")
    end
end

KeyRoll.BroadcastKeystoneToGuild = BroadcastKeystoneToGuild
KeyRoll.RequestGuildKeystonesFromAddon = RequestGuildKeystonesFromAddon