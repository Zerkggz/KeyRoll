KeyRoll = KeyRoll or {}

KeyRollGlobalDB = KeyRollGlobalDB or {}
KeyRollGlobalDB.guildCaches = KeyRollGlobalDB.guildCaches or {}
KeyRollGlobalDB.friendCache = KeyRollGlobalDB.friendCache or {}
KeyRollGlobalDB.myKeysCache = KeyRollGlobalDB.myKeysCache or {}
KeyRollGlobalDB.partyCache = KeyRollGlobalDB.partyCache or {}
KeyRollGlobalDB.lastResetTime = KeyRollGlobalDB.lastResetTime or 0

KeyRollDB = KeyRollDB or {}
KeyRollDB.cache = KeyRollDB.cache or {}

-- Migrate old single guildCache to per-guild structure
local currentGuild = GetGuildInfo("player")
if KeyRollGlobalDB.guildCache and not KeyRollGlobalDB._guildCacheMigrated then
    local oldGuildName = KeyRollGlobalDB.lastGuildName or currentGuild
    if oldGuildName then
        KeyRollGlobalDB.guildCaches[oldGuildName] = KeyRollGlobalDB.guildCaches[oldGuildName] or {}
        local migratedCount = 0
        for k, v in pairs(KeyRollGlobalDB.guildCache) do
            KeyRollGlobalDB.guildCaches[oldGuildName][k] = v
            migratedCount = migratedCount + 1
        end
        
        if KeyRoll and KeyRoll.Debug and migratedCount > 0 then
            print("[KeyRoll] Migrated", migratedCount, "keystones from old structure to guild:", oldGuildName)
        end
    end
    KeyRollGlobalDB._guildCacheMigrated = true
end

-- Set up guild-specific cache pointer
local noguildCache = {}  -- Local-only empty table for guildless characters (not persisted)
if currentGuild then
    KeyRollGlobalDB.guildCaches[currentGuild] = KeyRollGlobalDB.guildCaches[currentGuild] or {}
    KeyRollGlobalDB.guildCache = KeyRollGlobalDB.guildCaches[currentGuild]
else
    KeyRollGlobalDB.guildCache = noguildCache
end

-- Weekly reset: US/Oceanic Tue 15:00 UTC, EU Wed 04:00 UTC
local function GetNextResetTime()
    local region = GetCurrentRegion()
    local serverTime = GetServerTime()
    local d = date("*t", serverTime)
    local resetHour, resetDay
    
    if region == 3 then  -- EU
        resetDay = 4   -- Wednesday
        resetHour = 4  -- 04:00 UTC
    else  -- US/Oceanic
        resetDay = 3    -- Tuesday
        resetHour = 15  -- 15:00 UTC
    end
    
    local daysUntilReset
    if d.wday > resetDay then
        daysUntilReset = 7 - (d.wday - resetDay)
    elseif d.wday < resetDay then
        daysUntilReset = resetDay - d.wday
    else
        daysUntilReset = (d.hour < resetHour and 0 or 7)
    end
    
    local nextReset = serverTime + (daysUntilReset * 86400) + ((resetHour - d.hour) * 3600) - (d.min * 60) - d.sec
    
    return nextReset
end

local function CheckAndClearWeeklyReset()
    local serverTime = GetServerTime()
    
    if not KeyRollGlobalDB.lastResetTime or KeyRollGlobalDB.lastResetTime == 0 then
        KeyRollGlobalDB.lastResetTime = GetNextResetTime()
        if KeyRoll.Debug then
            print("[KeyRoll Debug] Initialized next reset time:", date("%Y-%m-%d %H:%M:%S", KeyRollGlobalDB.lastResetTime))
        end
        return
    end
    
    if KeyRoll.Debug then
        print("[KeyRoll Debug] === Weekly Reset Check ===")
        print("[KeyRoll Debug] Server time:", date("%Y-%m-%d %H:%M:%S", serverTime))
        print("[KeyRoll Debug] Next reset time:", date("%Y-%m-%d %H:%M:%S", KeyRollGlobalDB.lastResetTime))
    end
    
    if serverTime >= KeyRollGlobalDB.lastResetTime then
        local totalGuildCount = 0
        for guildName, guildCache in pairs(KeyRollGlobalDB.guildCaches) do
            for k in pairs(guildCache) do
                totalGuildCount = totalGuildCount + 1
                guildCache[k] = nil
            end
        end
        
        local friendCount = 0
        for k in pairs(KeyRollGlobalDB.friendCache) do
            friendCount = friendCount + 1
            KeyRollGlobalDB.friendCache[k] = nil
        end
        
        local myKeysCount = 0
        for k in pairs(KeyRollGlobalDB.myKeysCache) do
            myKeysCount = myKeysCount + 1
            KeyRollGlobalDB.myKeysCache[k] = nil
        end
        
        local partyCount = 0
        for k in pairs(KeyRollGlobalDB.partyCache) do
            partyCount = partyCount + 1
            KeyRollGlobalDB.partyCache[k] = nil
        end
        
        KeyRollGlobalDB.lastResetTime = GetNextResetTime()
        
        if KeyRoll.Debug then
            print("[KeyRoll] Weekly reset detected! Cleared caches:")
            print("  Guild keystones removed:", totalGuildCount)
            print("  Friend keystones removed:", friendCount)
            print("  My Keys removed:", myKeysCount)
            print("  Party keystones removed:", partyCount)
            print("  Next reset:", date("%Y-%m-%d %H:%M:%S", KeyRollGlobalDB.lastResetTime))
        end
    end
end

CheckAndClearWeeklyReset()
KeyRoll.CheckAndClearWeeklyReset = CheckAndClearWeeklyReset

-- Migrate old cache data stored directly in KeyRollDB to KeyRollDB.cache
if not KeyRollDB._migrated then
    for k, v in pairs(KeyRollDB) do
        if k ~= "cache" and k ~= "Debug" and k ~= "_migrated" and type(v) == "table" and v.mapID then
            KeyRollDB.cache[k] = v
            KeyRollDB[k] = nil
        end
    end
    KeyRollDB._migrated = true
end

if KeyRoll and KeyRoll.Debug then
    print("[KeyRoll] Cache on load:")
    local count = 0
    for k, v in pairs(KeyRollDB.cache) do
        count = count + 1
        print("  -", k, "debug="..tostring(v.debug))
    end
    if count == 0 then
        print("  (empty)")
    end
    
    print("[KeyRoll] Guild cache on load:")
    local guildCount = 0
    for k, v in pairs(KeyRollGlobalDB.guildCache) do
        guildCount = guildCount + 1
        print("  -", k, "source="..tostring(v.source))
    end
    if guildCount == 0 then
        print("  (empty)")
    end
end

local cache = KeyRollGlobalDB.partyCache
local friendCache = KeyRollGlobalDB.friendCache
local lastPartyMembers = {}
local cacheNeedsPrune = false
local storedFrame
local KEY_REQUEST_COOLDOWN = 5
local lastKeyRequestTime = 0

local function IsDebug()
    return KeyRoll.Debug == true
end

local function DebugPrint(...)
    if IsDebug() then
        print("|cff00ffff[KeyRoll Debug]|r", ...)
    end
end

KeyRoll.IsDebug = IsDebug
KeyRoll.DebugPrint = DebugPrint

local ROLL_MESSAGES = {
    "Shaking the keystone bag...",
    "Consulting the ancient key spirits...",
    "Rolling for pain and glory...",
    "Deciding our fate...",
    "Throwing the keys on the floor...",
    "Letting fate take the wheel...",
    "Spinning the dungeon roulette...",
    "Asking the healer what they deserve...",
    "Calculating optimal suffering...",
    "The keys are whispering...",
}

local WIN_MESSAGES = {
    "The keys have spoken:",
    "Destiny chooses:",
    "Tonight we suffer in:",
    "Prepare yourselves for:",
    "The wheel stops on:",
    "The dungeon gods demand:",
    "Your fate is sealed:",
    "Blame RNG, but it's:",
    "Congratulations, it's:",
    "Hope you like:",
}

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

local function IsGuildMember(playerName)
    if not IsInGuild() then return false end
    
    playerName = Ambiguate(playerName, "short")
    
    local numTotalMembers = GetNumGuildMembers()
    for i = 1, numTotalMembers do
        local name = GetGuildRosterInfo(i)
        if name then
            name = Ambiguate(name, "short")
            if name == playerName then
                return true
            end
        end
    end
    
    return false
end

local function IsActuallyInParty()
    return IsInGroup() and GetNumSubgroupMembers() > 0
end

local function IsInRealParty()
    if not IsActuallyInParty() then return false end
    
    if C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon and C_LFGInfo.IsInLFGFollowerDungeon() then
        return false
    end
    
    local numRealPlayers = 0
    
    if UnitIsPlayer("player") then
        numRealPlayers = numRealPlayers + 1
    end
    
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party"..i
        if UnitExists(unit) and UnitIsPlayer(unit) then
            numRealPlayers = numRealPlayers + 1
        end
    end
    
    return numRealPlayers >= 2 and numRealPlayers <= 5
end

KeyRoll.IsInRealParty = IsInRealParty
KeyRoll.IsActuallyInParty = IsActuallyInParty
KeyRoll.GetCurrentPartyMembers = GetCurrentPartyMembers

local function RefreshStoredFrame()
    if storedFrame and storedFrame:IsShown() then
        storedFrame:Refresh()
    end
end

local function MarkCacheDirty(pruneNow)
    cacheNeedsPrune = true
end

local function StoreMyKey(mapID, level)
    if type(mapID) ~= "number" or mapID <= 0 or type(level) ~= "number" or level <= 0 then
        return
    end
    
    local playerName = Ambiguate(UnitName("player"), "short")
    local realmName = GetRealmName()
    local fullName = playerName .. "-" .. realmName
    local _, class = UnitClass("player")
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    KeyRollGlobalDB.myKeysCache[fullName] = {
        name = playerName,
        realm = realmName,
        fullName = fullName,
        class = class,
        mapID = mapID,
        level = level,
        dungeon = dungeon,
        time = time(),
    }
    
    if IsDebug() then
        local count = 0
        for _ in pairs(KeyRollGlobalDB.myKeysCache) do count = count + 1 end
        DebugPrint("Stored My Key:", fullName, dungeon, "+"..level, "(" .. count .. " total)")
    end
    
    RefreshStoredFrame()
end

local function StoreKey(sender, mapID, level)
    if not sender or type(mapID) ~= "number" or mapID <= 0 or type(level) ~= "number" or level <= 0 then
        return
    end

    local fullName = sender
    local shortName = Ambiguate(sender, "short")
    local realm = sender:match("%-(.+)$")
    
    -- If no realm in sender, try to get from party unit
    if not realm then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party"..i
            if UnitExists(unit) then
                local unitName, unitRealm = UnitFullName(unit)
                if unitName and Ambiguate(unitName, "short") == shortName and unitRealm and unitRealm ~= "" then
                    realm = unitRealm
                    fullName = shortName .. "-" .. realm
                    break
                end
            end
        end
    end
    
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    local _, class = UnitClass(sender)
    if not class then
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party"..i
            if UnitExists(unit) and Ambiguate(UnitName(unit), "short") == shortName then
                _, class = UnitClass(unit)
                break
            end
        end
    end

    cache[shortName] = {
        name = shortName,
        fullName = fullName,
        realm = realm,
        class = class,
        mapID = mapID,
        level = level,
        dungeon = dungeon,
        time = time(),
    }
    
    local playerName = Ambiguate(UnitName("player"), "short")
    if shortName == playerName then
        StoreMyKey(mapID, level)
    end

    if IsGuildMember(shortName) then
        KeyRollGlobalDB.guildCache[shortName] = {
            name = shortName,
            fullName = fullName,
            realm = realm,
            class = class,
            mapID = mapID,
            level = level,
            dungeon = dungeon,
            time = time(),
            source = "party",
        }
        if IsDebug() then
            DebugPrint("Stored guild member keystone from party:", shortName, dungeon, "+"..level)
        end
    end

    MarkCacheDirty()
    if IsInRealParty() and IsDebug() then
        DebugPrint("Stored keystone:", shortName, dungeon, "+"..level)
    end

    RefreshStoredFrame()
end

local function StoreGuildKey(sender, mapID, level, class)
    if not sender or type(mapID) ~= "number" or mapID <= 0 or type(level) ~= "number" or level <= 0 then
        return
    end
    
    KeyRollGlobalDB.guildCaches = KeyRollGlobalDB.guildCaches or {}
    local currentGuild = GetGuildInfo("player")
    if currentGuild then
        KeyRollGlobalDB.guildCaches[currentGuild] = KeyRollGlobalDB.guildCaches[currentGuild] or {}
        KeyRollGlobalDB.guildCache = KeyRollGlobalDB.guildCaches[currentGuild]
    else
        return
    end

    local fullName = sender
    local shortName = Ambiguate(sender, "short")
    local realm = sender:match("%-(.+)$")
    
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    if not class and IsInGuild() then
        local numTotalMembers = GetNumGuildMembers()
        for i = 1, numTotalMembers do
            local name, _, _, _, classFileName = GetGuildRosterInfo(i)
            if name and Ambiguate(name, "short") == shortName then
                class = classFileName
                break
            end
        end
    end

    KeyRollGlobalDB.guildCache[shortName] = {
        name = shortName,
        fullName = fullName,
        realm = realm,
        class = class,
        mapID = mapID,
        level = level,
        dungeon = dungeon,
        time = time(),
        source = "astralkeys",
    }
    
    -- Check if this person is a Battle.net friend and add to friend cache
    local isBNetFriend = false
    local _, numBNetOnline = BNGetNumFriends()
    for i = 1, numBNetOnline do
        local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
        if accountInfo and accountInfo.gameAccountInfo then
            local characterName = accountInfo.gameAccountInfo.characterName
            if characterName and Ambiguate(characterName, "short") == shortName then
                isBNetFriend = true
                break
            end
        end
    end
    
    if isBNetFriend then
        KeyRollGlobalDB.friendCache[shortName] = {
            name = shortName,
            fullName = fullName,
            realm = realm,
            class = class,
            mapID = mapID,
            level = level,
            dungeon = dungeon,
            time = time(),
            source = "guild",
        }
    end

    RefreshStoredFrame()
end

KeyRoll.StoreKey = StoreKey
KeyRoll.StoreGuildKey = StoreGuildKey

local function FormatCharacterName(nameOrData)
    local _, currentRealm = UnitFullName("player")
    
    local name, realm
    
    if type(nameOrData) == "table" then
        name = nameOrData.name
        realm = nameOrData.realm
        if not realm and nameOrData.fullName then
            realm = nameOrData.fullName:match("%-(.+)$")
        end
    else
        local fullName = nameOrData
        name, realm = fullName:match("^([^%-]+)%-(.+)$")
        if not name then
            name = fullName
            realm = nil
        end
    end
    
    if realm and realm ~= currentRealm then
        return string.format("%s |cff888888(%s)|r", name, realm)
    else
        return name
    end
end

KeyRoll.FormatCharacterName = FormatCharacterName

local function IsCharacterOnline(charName, tabType)
    local shortName = Ambiguate(charName, "short")
    
    if tabType == "mykeys" then
        local playerName = Ambiguate(UnitName("player"), "short")
        if shortName == playerName then
            return true
        end
        return false
    end
    
    if tabType == "party" then
        if UnitExists("player") and Ambiguate(UnitName("player"), "short") == shortName then
            return true
        end
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party"..i
            if UnitExists(unit) and Ambiguate(UnitName(unit), "short") == shortName then
                return true
            end
        end
        return false
    end
    
    if tabType == "guild" and IsInGuild() then
        local playerName = Ambiguate(UnitName("player"), "short")
        if shortName == playerName then
            return true
        end
        
        -- Battle.net friend status is more reliable than guild roster for online checks
        local _, numBNetOnline = BNGetNumFriends()
        if numBNetOnline then
            for i = 1, numBNetOnline do
                local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
                if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
                    local characterName = accountInfo.gameAccountInfo.characterName
                    if characterName and Ambiguate(characterName, "short") == shortName then
                        return true
                    end
                end
            end
        end
        
        -- Fall back to guild roster
        local numTotal = GetNumGuildMembers()
        for i = 1, numTotal do
            local name, _, _, _, _, _, _, online = GetGuildRosterInfo(i)
            if name and Ambiguate(name, "short") == shortName then
                return online == true
            end
        end
        return false
    end
    
    if tabType == "friends" then
        local _, numBNetOnline = BNGetNumFriends()
        if not numBNetOnline then
            return true
        end
        
        for i = 1, numBNetOnline do
            local accountInfo = C_BattleNet.GetFriendAccountInfo(i)
            if accountInfo and accountInfo.gameAccountInfo and accountInfo.gameAccountInfo.isOnline then
                local characterName = accountInfo.gameAccountInfo.characterName
                if characterName then
                    local friendShortName = Ambiguate(characterName, "short")
                    if friendShortName == shortName then
                        return true
                    end
                end
            end
        end
        return false
    end
    
    return true
end

KeyRoll.IsCharacterOnline = IsCharacterOnline

local function PruneCache()
    local members = GetCurrentPartyMembers()
    
    DebugPrint("=== PruneCache called ===")
    DebugPrint("Current party members:")
    for name in pairs(members) do
        DebugPrint("  -", name)
    end
    DebugPrint("Last known party members:")
    for name in pairs(lastPartyMembers) do
        DebugPrint("  -", name)
    end
    DebugPrint("Cached keystones:")
    for name, key in pairs(cache) do
        DebugPrint("  -", name, "debug="..tostring(key.debug))
    end
    
    -- Don't prune if we have no previous party data (just reloaded)
    local hadPreviousMembers = false
    for _ in pairs(lastPartyMembers) do
        hadPreviousMembers = true
        break
    end
    
    if not hadPreviousMembers then
        lastPartyMembers = members
        cacheNeedsPrune = false
        DebugPrint("No previous party data (likely just reloaded) - skipping prune, initializing party list")
        DebugPrint("=== PruneCache done (skipped) ===")
        return
    end
    
    -- Remove keys for people who were in party but now aren't
    local prunedAny = false
    for name, key in pairs(cache) do
        if not key.debug and lastPartyMembers[name] and not members[name] then
            cache[name] = nil
            prunedAny = true
            DebugPrint("Pruned keystone for", name, "(was in party, now left)")
        end
    end
    lastPartyMembers = members
    cacheNeedsPrune = false
    
    if prunedAny then
        RefreshStoredFrame()
    end
    
    DebugPrint("=== PruneCache done ===")
end

local function GetRollableKeys()
    local keys = {}
    local playerName = Ambiguate(UnitName("player"), "short")

    for _, key in pairs(cache) do
        if key and (not key.debug or KeyRoll.IsDebug() or key.name == playerName) then
            table.insert(keys, key)
        end
    end

    return keys
end

local function DebugSeed()
    cache["TestPlayer1"] = { name="TestPlayer1", mapID=503, level=12, time=time(), debug=true }
    cache["TestPlayer2"] = { name="TestPlayer2", mapID=505, level=15, time=time(), debug=true }
end

local function DebugClear()
    for name, key in pairs(cache) do
        if key.debug then cache[name] = nil end
    end
end

local function CreateStoredFrame()
    if storedFrame then return end

    storedFrame = CreateFrame("Frame", "KeyRollStoredFrame", UIParent, "BasicFrameTemplateWithInset")
    KeyRoll.StoredFrame = storedFrame

    storedFrame:SetSize(525, 400)
    storedFrame:SetPoint("CENTER")
    storedFrame:SetMovable(true)
    storedFrame:EnableMouse(true)
    storedFrame:RegisterForDrag("LeftButton")
    storedFrame:SetScript("OnDragStart", storedFrame.StartMoving)
    storedFrame:SetScript("OnDragStop", storedFrame.StopMovingOrSizing)

    storedFrame.TitleText:SetText("|cff00ff00KeyRoll|r |cffffffffKeystones|r")
    storedFrame.TitleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

    local refreshButton = CreateFrame("Button", nil, storedFrame)
    refreshButton:SetSize(24, 24)
    refreshButton:SetPoint("TOPRIGHT", storedFrame.CloseButton, "TOPLEFT", -2, 0)
    
    refreshButton:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    refreshButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    refreshButton:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    
    local pushedTex = refreshButton:GetPushedTexture()
    if pushedTex then
        pushedTex:SetVertexColor(0.5, 0.5, 0.5)
    end
    
    refreshButton:SetButtonState("NORMAL")
    refreshButton:RegisterForClicks("LeftButtonUp")
    
    refreshButton:SetScript("OnClick", function(self)
        storedFrame:Refresh()
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Manual refresh triggered")
        end
    end)
    
    refreshButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh Keystones", 1, 1, 1)
        GameTooltip:AddLine("Click to manually update the keystone display", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    refreshButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    storedFrame.activeTab = "mykeys"
    storedFrame.tabs = {}

    local tabData = {
        {id="mykeys", label="My Keys", color={0.8, 0.2, 0.8}, x=10},
        {id="party", label="Party", color={0.2, 0.5, 0.9}, x=110},
        {id="friends", label="Friends", color={0.9, 0.6, 0.2}, x=210},
        {id="guild", label="Guild", color={0.2, 0.8, 0.2}, x=310}
    }

    for _, data in ipairs(tabData) do
        local tab = CreateFrame("Button", nil, storedFrame, "BackdropTemplate")
        tab:SetSize(95, 26)
        tab:SetPoint("TOPLEFT", data.x, -35)
        
        tab:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        tab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER", 0, 0)
        tab.text:SetText(data.label)
        tab.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        tab.text:SetTextColor(0.7, 0.7, 0.7)
        
        tab.activeColor = data.color
        
        tab:SetScript("OnClick", function()
            storedFrame.activeTab = data.id
            storedFrame:Refresh()
        end)
        
        tab:SetScript("OnEnter", function()
            if storedFrame.activeTab ~= data.id then
                tab:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
                tab.text:SetTextColor(1, 1, 1)
            end
        end)
        tab:SetScript("OnLeave", function()
            if storedFrame.activeTab ~= data.id then
                tab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end)
        
        storedFrame.tabs[data.id] = tab
    end

    local rollerTab = CreateFrame("Button", nil, storedFrame, "BackdropTemplate")
    rollerTab:SetSize(95, 26)
    rollerTab:SetPoint("TOPRIGHT", -10, -35)
    
    rollerTab:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    rollerTab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
    rollerTab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    
    rollerTab.text = rollerTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rollerTab.text:SetPoint("CENTER", 0, 0)
    rollerTab.text:SetText("Key Roller")
    rollerTab.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    rollerTab.text:SetTextColor(0.7, 0.7, 0.7)
    
    rollerTab.activeColor = {1.0, 0.8, 0.0}
    
    rollerTab:SetScript("OnClick", function()
        storedFrame.activeTab = "roller"
        storedFrame:Refresh()
    end)
    
    rollerTab:SetScript("OnEnter", function()
        if storedFrame.activeTab ~= "roller" then
            rollerTab:SetBackdropColor(0.2, 0.2, 0.2, 0.9)
            rollerTab.text:SetTextColor(1, 1, 1)
        end
    end)
    rollerTab:SetScript("OnLeave", function()
        if storedFrame.activeTab ~= "roller" then
            rollerTab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
            rollerTab.text:SetTextColor(0.7, 0.7, 0.7)
        end
    end)
    
    storedFrame.tabs["roller"] = rollerTab

    local sortY = -70
    
    storedFrame.sortLabel = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    storedFrame.sortLabel:SetPoint("TOPLEFT", 15, sortY)
    storedFrame.sortLabel:SetText("Sort by:")
    storedFrame.sortLabel:SetTextColor(0.7, 0.7, 0.7)
    
    storedFrame.sortMode = "level"
    storedFrame.sortButtons = {}
    
    local levelBtn = CreateFrame("Button", nil, storedFrame)
    levelBtn:SetSize(32, 14)
    levelBtn:SetPoint("TOPLEFT", 64, sortY)
    levelBtn.text = levelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    levelBtn.text:SetAllPoints()
    levelBtn.text:SetJustifyH("CENTER")
    levelBtn.text:SetJustifyV("TOP")
    levelBtn.text:SetText("Level")
    levelBtn.text:SetTextColor(0.6, 0.6, 0.6)
    levelBtn:SetScript("OnClick", function() storedFrame.sortMode = "level"; storedFrame:Refresh() end)
    levelBtn:SetScript("OnEnter", function() if storedFrame.sortMode ~= "level" then levelBtn.text:SetTextColor(1, 1, 1) end end)
    levelBtn:SetScript("OnLeave", function() if storedFrame.sortMode ~= "level" then levelBtn.text:SetTextColor(0.6, 0.6, 0.6) end end)
    storedFrame.sortButtons["level"] = levelBtn
    
    storedFrame.sortPipes = {}
    
    local pipe1 = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pipe1:SetPoint("TOPLEFT", 102, sortY)
    pipe1:SetText("|")
    pipe1:SetTextColor(0.4, 0.4, 0.4)
    table.insert(storedFrame.sortPipes, pipe1)
    
    local nameBtn = CreateFrame("Button", nil, storedFrame)
    nameBtn:SetSize(60, 14)
    nameBtn:SetPoint("TOPLEFT", 114, sortY)
    nameBtn.text = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    nameBtn.text:SetAllPoints()
    nameBtn.text:SetJustifyH("CENTER")
    nameBtn.text:SetJustifyV("TOP")
    nameBtn.text:SetText("Character")
    nameBtn.text:SetTextColor(0.6, 0.6, 0.6)
    nameBtn:SetScript("OnClick", function() storedFrame.sortMode = "name"; storedFrame:Refresh() end)
    nameBtn:SetScript("OnEnter", function() if storedFrame.sortMode ~= "name" then nameBtn.text:SetTextColor(1, 1, 1) end end)
    nameBtn:SetScript("OnLeave", function() if storedFrame.sortMode ~= "name" then nameBtn.text:SetTextColor(0.6, 0.6, 0.6) end end)
    storedFrame.sortButtons["name"] = nameBtn
    
    local pipe2 = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pipe2:SetPoint("TOPLEFT", 178, sortY)
    pipe2:SetText("|")
    pipe2:SetTextColor(0.4, 0.4, 0.4)
    table.insert(storedFrame.sortPipes, pipe2)
    
    local dungeonBtn = CreateFrame("Button", nil, storedFrame)
    dungeonBtn:SetSize(50, 14)
    dungeonBtn:SetPoint("TOPLEFT", 190, sortY)
    dungeonBtn.text = dungeonBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dungeonBtn.text:SetAllPoints()
    dungeonBtn.text:SetJustifyH("CENTER")
    dungeonBtn.text:SetJustifyV("TOP")
    dungeonBtn.text:SetText("Dungeon")
    dungeonBtn.text:SetTextColor(0.6, 0.6, 0.6)
    dungeonBtn:SetScript("OnClick", function() storedFrame.sortMode = "dungeon"; storedFrame:Refresh() end)
    dungeonBtn:SetScript("OnEnter", function() if storedFrame.sortMode ~= "dungeon" then dungeonBtn.text:SetTextColor(1, 1, 1) end end)
    dungeonBtn:SetScript("OnLeave", function() if storedFrame.sortMode ~= "dungeon" then dungeonBtn.text:SetTextColor(0.6, 0.6, 0.6) end end)
    storedFrame.sortButtons["dungeon"] = dungeonBtn

    storedFrame.contentBg = CreateFrame("Frame", nil, storedFrame, "BackdropTemplate")
    storedFrame.contentBg:SetPoint("TOPLEFT", 15, -88)
    storedFrame.contentBg:SetPoint("BOTTOMRIGHT", -15, 15)
    storedFrame.contentBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    storedFrame.contentBg:SetBackdropColor(0.05, 0.05, 0.05, 0.8)
    storedFrame.contentBg:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    storedFrame.scrollFrame = CreateFrame("ScrollFrame", nil, storedFrame, "UIPanelScrollFrameTemplate")
    storedFrame.scrollFrame:SetPoint("TOPLEFT", storedFrame.contentBg, "TOPLEFT", 8, -8)
    storedFrame.scrollFrame:SetPoint("BOTTOMRIGHT", storedFrame.contentBg, "BOTTOMRIGHT", -25, 8)

    storedFrame.content = CreateFrame("Frame", nil, storedFrame.scrollFrame)
    storedFrame.scrollFrame:SetScrollChild(storedFrame.content)

    storedFrame.rows = {}
    storedFrame.rowHeight = 24
    storedFrame.rowGap = 2
    storedFrame.rowWidth = 450

    function storedFrame:CreateRow(index)
        local row = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
        row:SetSize(self.rowWidth, self.rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index-1) * (self.rowHeight + self.rowGap))
        
        row:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        
        if index % 2 == 0 then
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        else
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        end
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetSize(self.rowWidth - 16, self.rowHeight)
        row.text:SetJustifyH("LEFT")
        row.text:SetFont("Fonts\\FRIZQT__.TTF", 12)
        
        self.rows[index] = row
        return row
    end

    function storedFrame:Refresh()
        KeyRollGlobalDB.guildCaches = KeyRollGlobalDB.guildCaches or {}
        
        local currentGuild = GetGuildInfo("player")
        if currentGuild then
            KeyRollGlobalDB.guildCaches[currentGuild] = KeyRollGlobalDB.guildCaches[currentGuild] or {}
            KeyRollGlobalDB.guildCache = KeyRollGlobalDB.guildCaches[currentGuild]
        else
            KeyRollGlobalDB.guildCache = {}
        end
        
        if IsDebug() then
            DebugPrint("=== Refresh() called ===")
            DebugPrint("Current activeTab:", self.activeTab or "nil")
        end
        
        for id, tab in pairs(self.tabs) do
            if id == self.activeTab then
                tab:SetBackdropColor(tab.activeColor[1] * 0.3, tab.activeColor[2] * 0.3, tab.activeColor[3] * 0.3, 0.9)
                tab:SetBackdropBorderColor(tab.activeColor[1], tab.activeColor[2], tab.activeColor[3], 1)
                tab.text:SetTextColor(1, 1, 1)
            else
                tab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end
        
        for id, btn in pairs(self.sortButtons) do
            if id == self.sortMode then
                btn.text:SetTextColor(0.2, 1, 0.2)
            else
                btn.text:SetTextColor(0.6, 0.6, 0.6)
            end
        end
        
        if self.activeTab == "roller" then
            if self.sortLabel then self.sortLabel:Hide() end
            for _, btn in pairs(self.sortButtons) do
                if btn then btn:Hide() end
            end
            if self.sortPipes then
                for _, pipe in ipairs(self.sortPipes) do
                    if pipe then pipe:Hide() end
                end
            end
        else
            if self.sortLabel then self.sortLabel:Show() end
            for _, btn in pairs(self.sortButtons) do
                if btn then btn:Show() end
            end
            if self.sortPipes then
                for _, pipe in ipairs(self.sortPipes) do
                    if pipe then pipe:Show() end
                end
            end
        end
        
        for _, row in ipairs(self.rows) do row:Hide() end
        
        local keys = {}
        if self.activeTab == "mykeys" then
            if IsDebug() then
                DebugPrint("=== Loading My Keys Tab ===")
                local count = 0
                for name, key in pairs(KeyRollGlobalDB.myKeysCache) do
                    count = count + 1
                    DebugPrint("  Found:", name, "-", key.dungeon, "+" .. key.level)
                end
                DebugPrint("Total My Keys in cache:", count)
            end
            for _, key in pairs(KeyRollGlobalDB.myKeysCache) do
                table.insert(keys, key)
            end
        elseif self.activeTab == "party" then
            keys = GetRollableKeys()
        elseif self.activeTab == "guild" then
            if IsDebug() then
                DebugPrint("=== Loading Guild Tab ===")
                local guildName = GetGuildInfo("player")
                if guildName then
                    DebugPrint("Current guild:", guildName)
                else
                    DebugPrint("Not in a guild")
                end
                
                if KeyRollGlobalDB.guildCaches then
                    DebugPrint("Available guild caches:")
                    for gName, gCache in pairs(KeyRollGlobalDB.guildCaches) do
                        local count = 0
                        for _ in pairs(gCache) do count = count + 1 end
                        DebugPrint("  ", gName, "has", count, "keys")
                    end
                else
                    DebugPrint("WARNING: KeyRollGlobalDB.guildCaches is nil!")
                end
                
                if KeyRollGlobalDB.guildCache then
                    local currentCacheCount = 0
                    for _ in pairs(KeyRollGlobalDB.guildCache) do currentCacheCount = currentCacheCount + 1 end
                    DebugPrint("Displaying", currentCacheCount, "keys from current cache")
                else
                    DebugPrint("WARNING: KeyRollGlobalDB.guildCache is nil!")
                end
            end
            
            for _, key in pairs(KeyRollGlobalDB.guildCache or {}) do
                table.insert(keys, key)
            end
        elseif self.activeTab == "friends" then
            if IsDebug() then
                DebugPrint("=== Loading Friends Tab ===")
                DebugPrint("Local friendCache has", #friendCache, "entries (length)")
                local localCount = 0
                for k in pairs(friendCache) do
                    localCount = localCount + 1
                end
                DebugPrint("Local friendCache has", localCount, "entries (pairs)")
                
                local globalCount = 0
                for k in pairs(KeyRollGlobalDB.friendCache) do
                    globalCount = globalCount + 1
                end
                DebugPrint("Global KeyRollGlobalDB.friendCache has", globalCount, "entries")
                
                DebugPrint("friendCache == KeyRollGlobalDB.friendCache?", friendCache == KeyRollGlobalDB.friendCache)
                
                if globalCount > 0 then
                    DebugPrint("Entries in KeyRollGlobalDB.friendCache:")
                    for name, key in pairs(KeyRollGlobalDB.friendCache) do
                        DebugPrint("  ", name, "-", key.dungeon, "+" .. key.level)
                    end
                end
            end
            for _, key in pairs(KeyRollGlobalDB.friendCache) do
                table.insert(keys, key)
            end
        elseif self.activeTab == "roller" then
            self.content:SetSize(self.rowWidth, 200)
            
            if not self.rollButton then
                self.rollButton = CreateFrame("Button", nil, self.content, "BackdropTemplate")
                self.rollButton:SetSize(200, 50)
                self.rollButton:SetPoint("TOP", 0, -20)
                
                self.rollButton:SetBackdrop({
                    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
                    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = false,
                    edgeSize = 16,
                    insets = { left = 4, right = 4, top = 4, bottom = 4 }
                })
                self.rollButton:SetBackdropColor(0.8, 0.6, 0.0, 0.9)
                self.rollButton:SetBackdropBorderColor(1.0, 0.8, 0.0, 1)
                
                self.rollButton.text = self.rollButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                self.rollButton.text:SetPoint("CENTER")
                self.rollButton.text:SetText("Roll Keys")
                self.rollButton.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
                
                self.rollButton:SetScript("OnClick", function()
                    if not KeyRoll.IsInRealParty() and not KeyRoll.IsDebug() then
                        KeyRoll.SendMessage("KeyRoll commands are disabled outside a real party.", {localOnly=true})
                        return
                    end
                    
                    KeyRoll.PruneCache()
                    local rollKeys = GetRollableKeys()
                    
                    if #rollKeys == 0 then
                        KeyRoll.SendMessage("No rollable keys available.", {localOnly=false})
                        self.rollResult:SetText("|cffff0000No party keystones available to roll!|r")
                        return
                    end
                    
                    local rollMsg = ROLL_MESSAGES[math.random(#ROLL_MESSAGES)]
                    KeyRoll.SendMessage(rollMsg)
                    self.rollResult:SetText("|cffaaaaaa" .. rollMsg .. "|r")
                    
                    C_Timer.After(1.5, function()
                        local keysNow = GetRollableKeys()
                        if #keysNow == 0 then
                            KeyRoll.SendMessage("No rollable keys available.")
                            self.rollResult:SetText("|cffff0000No keys available!|r")
                            return
                        end
                        
                        local chosen = keysNow[math.random(#keysNow)]
                        local winMsg = WIN_MESSAGES[math.random(#WIN_MESSAGES)]
                        local dungeonName = chosen.dungeon or KeyRoll.GetDungeonNameByID(chosen.mapID) or "Unknown"
                        
                        KeyRoll.SendMessage(string.format("%s %s - %s +%d", winMsg, chosen.name, dungeonName, chosen.level))
                        
                        local nameColor = "|cffffffff"
                        if chosen.class then
                            local classColor = C_ClassColor.GetClassColor(chosen.class)
                            if classColor then
                                nameColor = classColor:GenerateHexColorMarkup()
                            end
                        end
                        
                        local levelColor
                        if chosen.level >= 20 then
                            levelColor = "|cffff00ff"
                        elseif chosen.level >= 15 then
                            levelColor = "|cffff8000"
                        elseif chosen.level >= 10 then
                            levelColor = "|cff0070dd"
                        else
                            levelColor = "|cff1eff00"
                        end
                        
                        self.rollResult:SetText(string.format(
                            "|cffffd700%s|r\n%s%s|r - %s %s+%d|r",
                            winMsg,
                            nameColor,
                            chosen.name,
                            dungeonName,
                            levelColor,
                            chosen.level
                        ))
                    end)
                end)
                
                self.rollButton:SetScript("OnEnter", function()
                    self.rollButton:SetBackdropColor(1.0, 0.7, 0.0, 1.0)
                end)
                self.rollButton:SetScript("OnLeave", function()
                    self.rollButton:SetBackdropColor(0.8, 0.6, 0.0, 0.9)
                end)
                
                self.rollResult = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                self.rollResult:SetPoint("TOP", 0, -90)
                self.rollResult:SetSize(self.rowWidth - 40, 100)
                self.rollResult:SetJustifyH("CENTER")
                self.rollResult:SetJustifyV("TOP")
                self.rollResult:SetFont("Fonts\\FRIZQT__.TTF", 14)
                self.rollResult:SetText("|cffaaaaaa Press the button to roll a random party keystone!|r")
            end
            
            self.rollButton:Show()
            self.rollResult:Show()
            
            if self.emptyMessage then
                self.emptyMessage:Hide()
            end
            
            return
        end
        
        -- Hide roll button/result when not on roller tab
        if self.rollButton then
            self.rollButton:Hide()
        end
        if self.rollResult then
            self.rollResult:Hide()
        end
        
        if IsDebug() then
            DebugPrint("Keys collected before sorting:", #keys)
            if #keys > 0 then
                for i, key in ipairs(keys) do
                    DebugPrint("  Key " .. i .. ":", key.name, key.dungeon, "+" .. key.level)
                end
            end
        end
        
        if self.sortMode == "level" then
            table.sort(keys, function(a,b)
                if a.level ~= b.level then
                    return a.level > b.level
                end
                return a.name < b.name
            end)
        elseif self.sortMode == "name" then
            table.sort(keys, function(a,b)
                return a.name < b.name
            end)
        elseif self.sortMode == "dungeon" then
            table.sort(keys, function(a,b)
                local dungeonA = a.dungeon or KeyRoll.GetDungeonNameByID(a.mapID) or ""
                local dungeonB = b.dungeon or KeyRoll.GetDungeonNameByID(b.mapID) or ""
                if dungeonA ~= dungeonB then
                    return dungeonA < dungeonB
                end
                return a.level > b.level
            end)
        end
        
        local totalHeight = #keys * (self.rowHeight + self.rowGap)
        
        if #keys == 0 then
            totalHeight = 200
        end
        
        self.content:SetSize(self.rowWidth, totalHeight)

        for index, data in ipairs(keys) do
            if not self.rows[index] then
                self:CreateRow(index)
            end
            
            local row = self.rows[index]
            if row then
                local text
                local levelColor
                
                if data.level >= 20 then
                    levelColor = "|cffff00ff"
                elseif data.level >= 15 then
                    levelColor = "|cffff8000"
                elseif data.level >= 10 then
                    levelColor = "|cff0070dd"
                else
                    levelColor = "|cff1eff00"
                end
                
                local nameColor = "|cffffffff"
                if data.class then
                    local classColor = C_ClassColor.GetClassColor(data.class)
                    if classColor then
                        nameColor = classColor:GenerateHexColorMarkup()
                    end
                end
                
                local displayName = KeyRoll.FormatCharacterName(data)
                
                text = string.format(
                    "%s%s|r - %s %s+%d|r",
                    nameColor,
                    displayName,
                    data.dungeon or KeyRoll.GetDungeonNameByID(data.mapID) or ("Unknown (" .. tostring(data.mapID) .. ")"),
                    levelColor,
                    data.level
                )
                row.text:SetText(text)
                
                local isOnline = KeyRoll.IsCharacterOnline(data.name, self.activeTab)
                if isOnline then
                    row:SetAlpha(1.0)
                else
                    row:SetAlpha(0.4)
                end
                
                row:Show()
            end
        end
        
        for i = #keys + 1, #self.rows do
            if self.rows[i] then
                self.rows[i]:Hide()
            end
        end
        
        if not self.emptyMessage then
            self.emptyMessage = self.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            self.emptyMessage:SetPoint("TOP", 0, -50)
            self.emptyMessage:SetSize(self.rowWidth - 40, 100)
            self.emptyMessage:SetJustifyH("CENTER")
            self.emptyMessage:SetJustifyV("TOP")
            self.emptyMessage:SetFont("Fonts\\FRIZQT__.TTF", 14)
        end
        
        if #keys == 0 then
            local msg
            if self.activeTab == "party" then
                msg = "|cffaaaaaa No party keystones found. Ask players to link keys.|r"
            elseif self.activeTab == "guild" then
                if IsInGuild() then
                    msg = "|cffaaaaaa No guild keystones found.\nInvite guild members to party or have them install KeyRoll.|r"
                else
                    msg = "|cffaaaaaa Join a guild to see guild member keystones.|r"
                end
            elseif self.activeTab == "friends" then
                msg = "|cffaaaaaa No friend keystones found.\nFriends must have a keystone addon installed (Astral Keys, BigWigs, DBM, etc.)|r"
            end
            
            self.emptyMessage:SetText(msg)
            self.emptyMessage:Show()
        else
            self.emptyMessage:Hide()
        end
    end
end

local function SendMessage(text, opts)
    opts = opts or {}
    local localOnly = opts.localOnly or false

    if localOnly or not IsInRealParty() or KeyRoll.Debug then
        print(KeyRoll.PREFIX, text)
    else
        SendChatMessage(text, "PARTY")
    end
end

SLASH_KEYROLL1 = "/keyroll"
SLASH_KEYROLL2 = "/kr"
SlashCmdList["KEYROLL"] = function(msg)
    msg = (msg or ""):lower()

    if msg == "" then
        if not KeyRoll.StoredFrame then KeyRoll.CreateStoredFrame() end
        KeyRoll.CheckAndClearWeeklyReset()
        KeyRoll.StoredFrame:Show()
        KeyRoll.StoredFrame:Refresh()
        return
    end

    if msg == "roll" then
        -- Handled at the end of this function
    
    elseif msg == "list" then
        -- Handled at the end of this function
    
    elseif msg == "capture" then
        KeyRoll.ManualCapture()
        return
    
    elseif msg == "clear" then
        for name in pairs(cache) do
            cache[name] = nil
        end
        KeyRoll.SendMessage("Party cache cleared. All party keystones removed.", {localOnly=true})
        KeyRoll.SendMessage("(Guild and Friend keystones are not affected)", {localOnly=true})
        
        if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
            KeyRoll.StoredFrame:Refresh()
        end
        return
    
    elseif msg == "help" then
        KeyRoll.SendMessage("|cff00ff00=== KeyRoll Commands ===|r", {localOnly=true})
        KeyRoll.SendMessage(" ", {localOnly=true})
        KeyRoll.SendMessage("|cffffffffMain Commands:|r", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr|r or |cff00ff00/keyroll|r - Open keystone viewer UI", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr roll|r - Roll a random party keystone", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr list|r - List all party keystones in chat", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr capture|r - Manually capture keystones", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr clear|r - Clear party cache (not guild/friends)", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr help|r - Show this help message", {localOnly=true})
        KeyRoll.SendMessage(" ", {localOnly=true})
        KeyRoll.SendMessage("|cffffffffDebug Commands:|r", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug|r - Toggle debug mode on/off", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug seed|r - Add test keystones", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug clear|r - Remove test keystones", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug cache|r - Dump party cache", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug guild|r - Show guild cache stats", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug db|r - Dump KeyRollDB", {localOnly=true})
        KeyRoll.SendMessage("  |cff00ff00/kr debug globaldb|r - Dump KeyRollGlobalDB", {localOnly=true})
        KeyRoll.SendMessage(" ", {localOnly=true})
        KeyRoll.SendMessage("|cffaaaaaa(Party = current group, Guild = all guild members, Friends = Battle.net friends)|r", {localOnly=true})
        return

    elseif msg:find("^debug") then
		local arg = msg:match("^debug%s*(%S*)") or ""

		if arg == "" then
			KeyRoll.Debug = not KeyRoll.Debug
			local state = KeyRoll.Debug and "enabled" or "disabled"
			KeyRoll.SendMessage("Debug mode " .. state .. ".", {localOnly=true})

			if not KeyRoll.Debug then
				KeyRoll.DebugClear()
			end

		elseif arg == "seed" then
			KeyRoll.DebugSeed()
			KeyRoll.SendMessage("Debug keys added.", {localOnly=true})

			if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
				KeyRoll.StoredFrame:Refresh()
			end

		elseif arg == "clear" then
			KeyRoll.DebugClear()
			KeyRoll.SendMessage("Debug keys cleared.", {localOnly=true})

			if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
				KeyRoll.StoredFrame:Refresh()
			end

		elseif arg == "cache" then
			KeyRoll.SendMessage("=== RAW CACHE DUMP ===", {localOnly=true})
			local count = 0
			for name, key in pairs(cache) do
				count = count + 1
				KeyRoll.SendMessage(string.format(
					"[%d] %s: mapID=%s level=%s debug=%s dungeon=%s",
					count, name, tostring(key.mapID), tostring(key.level), 
					tostring(key.debug), tostring(key.dungeon)
				), {localOnly=true})
			end
			if count == 0 then
				KeyRoll.SendMessage("Cache is empty!", {localOnly=true})
			end
			KeyRoll.SendMessage("===================", {localOnly=true})

		elseif arg == "db" then
			KeyRoll.SendMessage("=== KeyRollDB DUMP ===", {localOnly=true})
			KeyRoll.SendMessage("KeyRollDB.Debug = " .. tostring(KeyRollDB.Debug), {localOnly=true})
			KeyRoll.SendMessage("KeyRollDB._migrated = " .. tostring(KeyRollDB._migrated), {localOnly=true})
			KeyRoll.SendMessage("KeyRollDB.cache entries:", {localOnly=true})
			local count = 0
			for k, v in pairs(KeyRollDB.cache or {}) do
				count = count + 1
				KeyRoll.SendMessage("  " .. k, {localOnly=true})
			end
			if count == 0 then
				KeyRoll.SendMessage("  (none)", {localOnly=true})
			end
			KeyRoll.SendMessage("===================", {localOnly=true})

		elseif arg == "guild" then
			KeyRoll.SendMessage("=== GUILD CACHE ===", {localOnly=true})
			local akCount = 0
			local partyCount = 0
			for name, key in pairs(KeyRollGlobalDB.guildCache) do
				if key.source == "astralkeys" then
					akCount = akCount + 1
				elseif key.source == "party" then
					partyCount = partyCount + 1
				end
			end
			local total = akCount + partyCount
			KeyRoll.SendMessage(string.format("Total: %d (%d from Astral Keys, %d from party)", total, akCount, partyCount), {localOnly=true})
			if total > 0 then
				KeyRoll.SendMessage("Recent guild keys:", {localOnly=true})
				local displayCount = 0
				for name, key in pairs(KeyRollGlobalDB.guildCache) do
					if displayCount < 5 then
						local source = key.source == "astralkeys" and "[AK]" or "[Party]"
						KeyRoll.SendMessage(string.format("  %s %s - %s +%d", source, name, key.dungeon, key.level), {localOnly=true})
						displayCount = displayCount + 1
					end
				end
				if total > 5 then
					KeyRoll.SendMessage(string.format("  ... and %d more. Use /keyroll stored to see all.", total - 5), {localOnly=true})
				end
			end
			KeyRoll.SendMessage("===================", {localOnly=true})
		
		elseif arg == "friends" then
			KeyRoll.SendMessage("=== FRIEND CACHE ===", {localOnly=true})
			local total = 0
			for name, key in pairs(KeyRollGlobalDB.friendCache) do
				total = total + 1
			end
			KeyRoll.SendMessage(string.format("Total: %d", total), {localOnly=true})
			if total > 0 then
				KeyRoll.SendMessage("Friend keystones:", {localOnly=true})
				local displayCount = 0
				for name, key in pairs(KeyRollGlobalDB.friendCache) do
					if displayCount < 10 then
						KeyRoll.SendMessage(string.format("  %s - %s +%d (source: %s)", name, key.dungeon, key.level, key.source or "?"), {localOnly=true})
						displayCount = displayCount + 1
					end
				end
				if total > 10 then
					KeyRoll.SendMessage(string.format("  ... and %d more. Use /keyroll stored to see all.", total - 10), {localOnly=true})
				end
			end
			KeyRoll.SendMessage("===================", {localOnly=true})
		
		elseif arg == "globaldb" then
			KeyRoll.SendMessage("=== KeyRollGlobalDB ===", {localOnly=true})
			KeyRoll.SendMessage("KeyRollGlobalDB.guildCache:", {localOnly=true})
			local count = 0
			for k, v in pairs(KeyRollGlobalDB.guildCache) do
				count = count + 1
				KeyRoll.SendMessage(string.format("  [%d] %s - %s +%d (source: %s)", count, k, v.dungeon or "?", v.level or 0, v.source or "?"), {localOnly=true})
			end
			if count == 0 then
				KeyRoll.SendMessage("  (empty)", {localOnly=true})
			end
			
			KeyRoll.SendMessage("KeyRollGlobalDB.friendCache:", {localOnly=true})
			local friendCount = 0
			for k, v in pairs(KeyRollGlobalDB.friendCache) do
				friendCount = friendCount + 1
				KeyRoll.SendMessage(string.format("  [%d] %s - %s +%d (source: %s)", friendCount, k, v.dungeon or "?", v.level or 0, v.source or "?"), {localOnly=true})
			end
			if friendCount == 0 then
				KeyRoll.SendMessage("  (empty)", {localOnly=true})
			end
			KeyRoll.SendMessage("===================", {localOnly=true})

		else
			KeyRoll.SendMessage("Debug commands:", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug           (toggle)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug seed      (add debug keys)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug clear     (remove debug keys)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug cache     (dump cache table)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug db        (dump KeyRollDB)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug guild     (show guild cache stats)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug friends   (show friend cache stats)", {localOnly=true})
			KeyRoll.SendMessage("  /kr debug globaldb  (dump KeyRollGlobalDB)", {localOnly=true})
		end

		return
	
	else
		KeyRoll.SendMessage('Command not recognized. Type "/kr help" to view accepted commands.', {localOnly=true})
		return
	end

    -- Party-only check for roll and list commands
    if msg == "list" or msg == "roll" then
        if not KeyRoll.IsInRealParty() and not KeyRoll.IsDebug() then
            KeyRoll.SendMessage("KeyRoll commands are disabled outside a real party.", {localOnly=true})
            return
        end
    end

	if msg == "list" then
		KeyRoll.PruneCache()
		local keys = GetRollableKeys()

		if #keys == 0 then
			KeyRoll.SendMessage("No party keystones known. Ask players to link keys.", {localOnly=true})
			return
		end

		KeyRoll.SendMessage("Party keystones:")
		for _, key in ipairs(keys) do
			local dungeonName = key.dungeon or KeyRoll.GetDungeonNameByID(key.mapID) or ("Unknown (" .. tostring(key.mapID) .. ")")
			KeyRoll.SendMessage(string.format(
				" %s - %s +%d",
				key.name,
				dungeonName,
				key.level
			))
		end
		return
	end

    -- Roll keys
    KeyRoll.PruneCache()
	local keys = GetRollableKeys()
    if #keys == 0 then
        KeyRoll.SendMessage("No rollable keys available.", {localOnly=true})
        return
    end
	
    KeyRoll.SendMessage(ROLL_MESSAGES[math.random(#ROLL_MESSAGES)])

    C_Timer.After(1.5, function()
        local keysNow = GetRollableKeys()
        if #keysNow == 0 then
            KeyRoll.SendMessage("No rollable keys available.", {localOnly=true})
            return
        end
		
        local chosen = keysNow[math.random(#keysNow)]
		local winMsg = WIN_MESSAGES[math.random(#WIN_MESSAGES)]
		KeyRoll.SendMessage(string.format(
			"%s %s - %s +%d",
			winMsg,
			chosen.name,
			chosen.dungeon or KeyRoll.GetDungeonNameByID(chosen.mapID) or ("Unknown (" .. tostring(chosen.mapID) .. ")"),
			chosen.level
		))
    end)
end

KeyRoll.KEY_REQUEST_COOLDOWN = KEY_REQUEST_COOLDOWN
KeyRoll.lastKeyRequestTime = lastKeyRequestTime
KeyRoll.MarkCacheDirty = MarkCacheDirty
KeyRoll.StoreKey = StoreKey
KeyRoll.StoreMyKey = StoreMyKey
KeyRoll.StoreGuildKey = StoreGuildKey
KeyRoll.PruneCache = PruneCache
KeyRoll.GetRollableKeys = GetRollableKeys
KeyRoll.SendMessage = SendMessage
KeyRoll.CreateStoredFrame = CreateStoredFrame
KeyRoll.DebugSeed = DebugSeed
KeyRoll.DebugClear = DebugClear
KeyRoll.IsInRealParty = IsInRealParty
KeyRoll.IsActuallyInParty = IsActuallyInParty
KeyRoll.GetCurrentPartyMembers = GetCurrentPartyMembers
KeyRoll.IsGuildMember = IsGuildMember