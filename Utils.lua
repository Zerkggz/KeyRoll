-- Ensure KeyRoll table exists
KeyRoll = KeyRoll or {}

-- Initialize account-wide saved variables
KeyRollGlobalDB = KeyRollGlobalDB or {}
KeyRollGlobalDB.guildCache = KeyRollGlobalDB.guildCache or {}
KeyRollGlobalDB.friendCache = KeyRollGlobalDB.friendCache or {}
KeyRollGlobalDB.myKeysCache = KeyRollGlobalDB.myKeysCache or {}
KeyRollGlobalDB.partyCache = KeyRollGlobalDB.partyCache or {}  -- Persist party cache
KeyRollGlobalDB.lastResetWeek = KeyRollGlobalDB.lastResetWeek or 0

-- Initialize per-character saved variables
KeyRollDB = KeyRollDB or {}
KeyRollDB.cache = KeyRollDB.cache or {}  -- Legacy, migrated to partyCache

-- Weekly reset detection and cache clearing
-- US/Oceanic: Tuesday 15:00 UTC
-- EU: Wednesday 04:00 UTC
local function GetCurrentWeek()
    local region = GetCurrentRegion()
    local resetDay, resetHour
    
    if region == 3 then  -- EU
        resetDay = 4
        resetHour = 4
    else  -- US/Oceanic
        resetDay = 3
        resetHour = 15
    end
    
    local serverTime = GetServerTime()
    local dateTable = date("*t", serverTime)
    
    -- Calculate weeks since epoch
    local daysSinceEpoch = math.floor(serverTime / 86400)
    local weeksSinceEpoch = math.floor(daysSinceEpoch / 7)
    
    -- Check if we've passed this week's reset
    if dateTable.wday < resetDay or (dateTable.wday == resetDay and dateTable.hour < resetHour) then
        weeksSinceEpoch = weeksSinceEpoch - 1
    end
    
    return weeksSinceEpoch
end

-- Check if we need to clear caches due to weekly reset
local currentWeek = GetCurrentWeek()
if KeyRollGlobalDB.lastResetWeek < currentWeek then
    -- New week! Clear guild and friend caches (keystones changed)
    local guildCount = 0
    for k in pairs(KeyRollGlobalDB.guildCache) do
        guildCount = guildCount + 1
        KeyRollGlobalDB.guildCache[k] = nil
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
    
    KeyRollGlobalDB.lastResetWeek = currentWeek
    
    if KeyRoll and KeyRoll.Debug then
        print("[KeyRoll] Weekly reset detected! Cleared caches:")
        print("  Guild keystones removed:", guildCount)
        print("  Friend keystones removed:", friendCount)
        print("  My Keys removed:", myKeysCount)
        print("  Party keystones removed:", partyCount)
    end
end

-- MIGRATION: Move old cache data (stored directly in KeyRollDB) to KeyRollDB.cache
-- This only runs once after the update
if not KeyRollDB._migrated then
    for k, v in pairs(KeyRollDB) do
        -- Skip known settings/metadata keys
        if k ~= "cache" and k ~= "Debug" and k ~= "_migrated" and type(v) == "table" and v.mapID then
            -- This looks like a keystone entry, migrate it
            KeyRollDB.cache[k] = v
            KeyRollDB[k] = nil
        end
    end
    KeyRollDB._migrated = true
end

-- Debug: Show what's in cache on load
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

-------------------------------------------------
-- Debug mode
-------------------------------------------------
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

-------------------------------------------------
-- Keystone roller flavor text
-------------------------------------------------
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

-------------------------------------------------
-- Get Current Party Members
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
-- Check if player is in your guild
-------------------------------------------------
local function IsGuildMember(playerName)
    if not IsInGuild() then return false end
    
    playerName = Ambiguate(playerName, "short")
    
    -- Check all guild members
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

-------------------------------------------------
-- Actually in a party
-------------------------------------------------
local function IsActuallyInParty()
    return IsInGroup() and GetNumSubgroupMembers() > 0
end

-------------------------------------------------
-- Is the party real
-------------------------------------------------
local function IsInRealParty()
    if not IsActuallyInParty() then return false end
    
    -- Exclude follower dungeons (solo with NPCs)
    if C_LFGInfo and C_LFGInfo.IsInLFGFollowerDungeon and C_LFGInfo.IsInLFGFollowerDungeon() then
        return false
    end
    
    -- Check if we're actually with real players
    local numRealPlayers = 0
    local playerName = UnitName("player")
    
    -- Count yourself
    if UnitIsPlayer("player") then
        numRealPlayers = numRealPlayers + 1
    end
    
    -- Count party members that are actual players (not NPCs)
    for i = 1, GetNumSubgroupMembers() do
        local unit = "party"..i
        if UnitExists(unit) and UnitIsPlayer(unit) then
            numRealPlayers = numRealPlayers + 1
        end
    end
    
    -- Must have 2-5 real players (including yourself)
    return numRealPlayers >= 2 and numRealPlayers <= 5
end

KeyRoll.IsInRealParty = IsInRealParty
KeyRoll.IsActuallyInParty = IsActuallyInParty
KeyRoll.GetCurrentPartyMembers = GetCurrentPartyMembers

-------------------------------------------------
-- Cache handling
-------------------------------------------------
local function RefreshStoredFrame()
    if storedFrame and storedFrame:IsShown() then
        storedFrame:Refresh()
    end
end

local function MarkCacheDirty(pruneNow)
    cacheNeedsPrune = true
end

-------------------------------------------------
-- Store current character's keystone in My Keys cache
-------------------------------------------------
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

    sender = Ambiguate(sender, "short")
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    -- Get class info for the player
    local _, class = UnitClass(sender)
    if not class then
        -- Try to get from party
        for i = 1, GetNumSubgroupMembers() do
            local unit = "party"..i
            if UnitExists(unit) and Ambiguate(UnitName(unit), "short") == sender then
                _, class = UnitClass(unit)
                break
            end
        end
    end

    cache[sender] = {
        name = sender,
        class = class,
        mapID = mapID,
        level = level,
        dungeon = dungeon,
        time = time(),
    }
    
    -- If this is the player's own key, also store in My Keys cache
    local playerName = Ambiguate(UnitName("player"), "short")
    if sender == playerName then
        StoreMyKey(mapID, level)
    end

    -- If this player is also a guild member, store in guild cache too
    if IsGuildMember(sender) then
        KeyRollGlobalDB.guildCache[sender] = {
            name = sender,
            class = class,
            mapID = mapID,
            level = level,
            dungeon = dungeon,
            time = time(),
            source = "party", -- Mark that this came from party, not Astral Keys
        }
        if IsDebug() then
            DebugPrint("Stored guild member keystone from party:", sender, dungeon, "+"..level)
        end
    end

    MarkCacheDirty()
    if IsInRealParty() and IsDebug() then
        DebugPrint("Stored keystone:", sender, dungeon, "+"..level)
    end

    RefreshStoredFrame()
end

local function StoreGuildKey(sender, mapID, level, class)
    if not sender or type(mapID) ~= "number" or mapID <= 0 or type(level) ~= "number" or level <= 0 then
        return
    end

    sender = Ambiguate(sender, "short")
    local dungeon = KeyRoll.GetDungeonNameByID(mapID) or ("Unknown (" .. tostring(mapID) .. ")")
    
    -- If class not provided, try to get from guild roster
    if not class and IsInGuild() then
        local numTotalMembers = GetNumGuildMembers()
        for i = 1, numTotalMembers do
            local name, _, _, _, classFileName = GetGuildRosterInfo(i)
            if name and Ambiguate(name, "short") == sender then
                class = classFileName
                break
            end
        end
    end

    KeyRollGlobalDB.guildCache[sender] = {
        name = sender,
        class = class,
        mapID = mapID,
        level = level,
        dungeon = dungeon,
        time = time(),
        source = "astralkeys", -- Mark that this came from Astral Keys
    }

    RefreshStoredFrame()
end

KeyRoll.StoreKey = StoreKey
KeyRoll.StoreGuildKey = StoreGuildKey

-------------------------------------------------
-- Cache pruning (explicit)
-------------------------------------------------
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
    
    -- Don't prune if lastPartyMembers is empty (just reloaded, don't know who left vs who was always there)
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
    
    -- Normal pruning: remove keys for people who WERE in party but now aren't
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
    
    -- Refresh UI if we pruned anything
    if prunedAny then
        RefreshStoredFrame()
    end
    
    DebugPrint("=== PruneCache done ===")
end

-------------------------------------------------
-- Get rollable keys (read-only!)
-------------------------------------------------
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

-------------------------------------------------
-- Debug solo keys
-------------------------------------------------
local function DebugSeed()
    cache["TestPlayer1"] = { name="TestPlayer1", mapID=503, level=12, time=time(), debug=true }
    cache["TestPlayer2"] = { name="TestPlayer2", mapID=505, level=15, time=time(), debug=true }
end

local function DebugClear()
    for name, key in pairs(cache) do
        if key.debug then cache[name] = nil end
    end
end

-------------------------------------------------
-- Stored frame with tabs
-------------------------------------------------
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

    -- Title
    storedFrame.TitleText:SetText("|cff00ff00KeyRoll|r |cffffffffKeystones|r")
    storedFrame.TitleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")

    -- Refresh button (next to close button)
    local refreshButton = CreateFrame("Button", nil, storedFrame)
    refreshButton:SetSize(24, 24)
    refreshButton:SetPoint("TOPRIGHT", storedFrame.CloseButton, "TOPLEFT", -2, 0)
    
    -- Custom texture for refresh icon (using built-in WoW textures)
    refreshButton:SetNormalTexture("Interface\\Buttons\\UI-RefreshButton")
    refreshButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    refreshButton:SetPushedTexture("Interface\\Buttons\\UI-RefreshButton")
    
    -- Make the pushed texture darker/offset for click feedback
    local pushedTex = refreshButton:GetPushedTexture()
    if pushedTex then
        pushedTex:SetVertexColor(0.5, 0.5, 0.5)
    end
    
    -- Enable button to depress when clicked
    refreshButton:SetButtonState("NORMAL")
    refreshButton:RegisterForClicks("LeftButtonUp")
    
    refreshButton:SetScript("OnClick", function(self)
        storedFrame:Refresh()
        -- Visual feedback
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Manual refresh triggered")
        end
    end)
    
    -- Tooltip
    refreshButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Refresh Keystones", 1, 1, 1)
        GameTooltip:AddLine("Click to manually update the keystone display", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    refreshButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Tab system with cleaner styling
    storedFrame.activeTab = "mykeys"  -- Default to My Keys tab
    storedFrame.tabs = {}

    local tabData = {
        {id="mykeys", label="My Keys", color={0.8, 0.2, 0.8}, x=10},      -- Purple
        {id="party", label="Party", color={0.2, 0.5, 0.9}, x=110},        -- Blue (Blizzard party color)
        {id="friends", label="Friends", color={0.9, 0.6, 0.2}, x=210},    -- Orange (Blizzard friends color)
        {id="guild", label="Guild", color={0.2, 0.8, 0.2}, x=310}         -- Green (Blizzard guild color)
    }

    for _, data in ipairs(tabData) do
        local tab = CreateFrame("Button", nil, storedFrame, "BackdropTemplate")
        tab:SetSize(95, 26)
        tab:SetPoint("TOPLEFT", data.x, -35)
        
        -- Simple backdrop
        tab:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        tab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
        tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
        
        -- Tab text
        tab.text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tab.text:SetPoint("CENTER", 0, 0)
        tab.text:SetText(data.label)
        tab.text:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        tab.text:SetTextColor(0.7, 0.7, 0.7)
        
        -- Store color for active state
        tab.activeColor = data.color
        
        -- Tab click handler
        tab:SetScript("OnClick", function()
            storedFrame.activeTab = data.id
            storedFrame:Refresh()
        end)
        
        -- Tab hover effects
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

    -- Key Roller tab (separate, on the right side) - Purple/Gold color
    local rollerTab = CreateFrame("Button", nil, storedFrame, "BackdropTemplate")
    rollerTab:SetSize(95, 26)
    rollerTab:SetPoint("TOPRIGHT", -10, -35)  -- Right side
    
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
    
    rollerTab.activeColor = {1.0, 0.8, 0.0}  -- Gold color
    
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

    -- Sort controls - all elements as FontStrings for baseline alignment
    local sortY = -70
    
    -- "Sort by:" label
    storedFrame.sortLabel = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    storedFrame.sortLabel:SetPoint("TOPLEFT", 15, sortY)
    storedFrame.sortLabel:SetText("Sort by:")
    storedFrame.sortLabel:SetTextColor(0.7, 0.7, 0.7)
    
    storedFrame.sortMode = "level"
    storedFrame.sortButtons = {}
    
    -- Level button (clickable FontString)
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
    
    -- First pipe
    local pipe1 = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pipe1:SetPoint("TOPLEFT", 102, sortY)
    pipe1:SetText("|")
    pipe1:SetTextColor(0.4, 0.4, 0.4)
    
    -- Character button
    local nameBtn = CreateFrame("Button", nil, storedFrame)
    nameBtn:SetSize(60, 14)  -- Wider to fit "Character"
    nameBtn:SetPoint("TOPLEFT", 114, sortY)  -- More space after pipe
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
    
    -- Second pipe - further right
    local pipe2 = storedFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pipe2:SetPoint("TOPLEFT", 178, sortY)
    pipe2:SetText("|")
    pipe2:SetTextColor(0.4, 0.4, 0.4)
    
    -- Dungeon button
    local dungeonBtn = CreateFrame("Button", nil, storedFrame)
    dungeonBtn:SetSize(50, 14)
    dungeonBtn:SetPoint("TOPLEFT", 190, sortY)  -- Adjusted for new pipe2 position
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

    -- Content area background
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

    -- Scroll frame
    storedFrame.scrollFrame = CreateFrame("ScrollFrame", nil, storedFrame, "UIPanelScrollFrameTemplate")
    storedFrame.scrollFrame:SetPoint("TOPLEFT", storedFrame.contentBg, "TOPLEFT", 8, -8)
    storedFrame.scrollFrame:SetPoint("BOTTOMRIGHT", storedFrame.contentBg, "BOTTOMRIGHT", -25, 8)

    storedFrame.content = CreateFrame("Frame", nil, storedFrame.scrollFrame)
    storedFrame.scrollFrame:SetScrollChild(storedFrame.content)

    -- Styled rows with unlimited capacity (dynamically created)
    storedFrame.rows = {}
    storedFrame.rowHeight = 24
    storedFrame.rowGap = 2
    storedFrame.rowWidth = 450

    -- Function to create a row on demand
    function storedFrame:CreateRow(index)
        local row = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
        row:SetSize(self.rowWidth, self.rowHeight)
        row:SetPoint("TOPLEFT", 0, -(index-1) * (self.rowHeight + self.rowGap))
        
        -- All rows get a background for better separation
        row:SetBackdrop({
            bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = false,
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })
        
        -- Alternating colors for better visual separation
        if index % 2 == 0 then
            row:SetBackdropColor(0.08, 0.08, 0.08, 0.9)
        else
            row:SetBackdropColor(0.12, 0.12, 0.12, 0.9)
        end
        row:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.5)
        
        -- Row text with better font
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetSize(self.rowWidth - 16, self.rowHeight)
        row.text:SetJustifyH("LEFT")
        row.text:SetFont("Fonts\\FRIZQT__.TTF", 12)
        
        self.rows[index] = row
        return row
    end

    -- Refresh function
    function storedFrame:Refresh()
        if IsDebug() then
            DebugPrint("=== Refresh() called ===")
            DebugPrint("Current activeTab:", self.activeTab or "nil")
        end
        
        -- Update tab appearances
        for id, tab in pairs(self.tabs) do
            if id == self.activeTab then
                -- Active tab: colored background and border
                tab:SetBackdropColor(tab.activeColor[1] * 0.3, tab.activeColor[2] * 0.3, tab.activeColor[3] * 0.3, 0.9)
                tab:SetBackdropBorderColor(tab.activeColor[1], tab.activeColor[2], tab.activeColor[3], 1)
                tab.text:SetTextColor(1, 1, 1)
            else
                -- Inactive tab: dark background
                tab:SetBackdropColor(0.1, 0.1, 0.1, 0.9)
                tab:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                tab.text:SetTextColor(0.7, 0.7, 0.7)
            end
        end
        
        -- Update sort button appearances
        for id, btn in pairs(self.sortButtons) do
            if id == self.sortMode then
                btn.text:SetTextColor(0.2, 1, 0.2)  -- Bright green for active
            else
                btn.text:SetTextColor(0.6, 0.6, 0.6)  -- Gray for inactive
            end
        end
        
        -- Hide all rows
        for _, row in ipairs(self.rows) do row:Hide() end
        
        -- Get appropriate data based on active tab
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
            for _, key in pairs(KeyRollGlobalDB.guildCache) do
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
            -- Use global directly instead of local variable
            for _, key in pairs(KeyRollGlobalDB.friendCache) do
                table.insert(keys, key)
            end
        elseif self.activeTab == "roller" then
            -- Key Roller tab - show roll button and last result
            self.content:SetSize(self.rowWidth, 200)
            
            -- Create roll button if it doesn't exist
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
                self.rollButton:SetBackdropColor(0.8, 0.6, 0.0, 0.9)  -- Gold
                self.rollButton:SetBackdropBorderColor(1.0, 0.8, 0.0, 1)
                
                -- Button text
                self.rollButton.text = self.rollButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
                self.rollButton.text:SetPoint("CENTER")
                self.rollButton.text:SetText("Roll Keys")
                self.rollButton.text:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
                
                -- Click handler
                self.rollButton:SetScript("OnClick", function()
                    if not KeyRoll.IsInRealParty() and not KeyRoll.IsDebug() then
                        KeyRoll.SendMessage("KeyRoll commands are disabled outside a real party.", {localOnly=true})
                        return
                    end
                    
                    -- Execute roll
                    KeyRoll.PruneCache()
                    local rollKeys = GetRollableKeys()
                    
                    if #rollKeys == 0 then
                        KeyRoll.SendMessage("No rollable keys available.", {localOnly=false})
                        self.rollResult:SetText("|cffff0000No party keystones available to roll!|r")
                        return
                    end
                    
                    -- Show flavor text
                    local rollMsg = ROLL_MESSAGES[math.random(#ROLL_MESSAGES)]
                    KeyRoll.SendMessage(rollMsg)
                    self.rollResult:SetText("|cffaaaaaa" .. rollMsg .. "|r")
                    
                    -- Delayed result
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
                        
                        -- Update UI result with class color
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
                
                -- Hover effects
                self.rollButton:SetScript("OnEnter", function()
                    self.rollButton:SetBackdropColor(1.0, 0.7, 0.0, 1.0)
                end)
                self.rollButton:SetScript("OnLeave", function()
                    self.rollButton:SetBackdropColor(0.8, 0.6, 0.0, 0.9)
                end)
                
                -- Result text below button
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
            return
        end
        
        -- Hide roller button/result when not on roller tab
        if self.rollButton then
            self.rollButton:Hide()
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
        
        -- Sort based on selected mode
        if self.sortMode == "level" then
            table.sort(keys, function(a,b)
                if a.level ~= b.level then
                    return a.level > b.level  -- Highest first
                end
                return a.name < b.name
            end)
        elseif self.sortMode == "name" then
            table.sort(keys, function(a,b)
                return a.name < b.name  -- Alphabetical
            end)
        elseif self.sortMode == "dungeon" then
            table.sort(keys, function(a,b)
                local dungeonA = a.dungeon or KeyRoll.GetDungeonNameByID(a.mapID) or ""
                local dungeonB = b.dungeon or KeyRoll.GetDungeonNameByID(b.mapID) or ""
                if dungeonA ~= dungeonB then
                    return dungeonA < dungeonB  -- Alphabetical
                end
                return a.level > b.level  -- Then by level
            end)
        end
        
        local totalHeight = #keys * (self.rowHeight + self.rowGap)
        self.content:SetSize(self.rowWidth, totalHeight)

        -- Display keys with color coding - create rows as needed
        for index, data in ipairs(keys) do
            -- Create row if it doesn't exist
            if not self.rows[index] then
                self:CreateRow(index)
            end
            
            local row = self.rows[index]
            if row then
                local text
                local levelColor
                
                -- Color code by key level
                if data.level >= 20 then
                    levelColor = "|cffff00ff" -- Purple for 20+
                elseif data.level >= 15 then
                    levelColor = "|cffff8000" -- Orange for 15-19
                elseif data.level >= 10 then
                    levelColor = "|cff0070dd" -- Blue for 10-14
                else
                    levelColor = "|cff1eff00" -- Green for <10
                end
                
                -- Get class color for player name
                local nameColor = "|cffffffff" -- Default white
                if data.class then
                    local classColor = C_ClassColor.GetClassColor(data.class)
                    if classColor then
                        nameColor = classColor:GenerateHexColorMarkup()
                    end
                end
                
                -- Format with class-colored name
                text = string.format(
                    "%s%s|r - %s %s+%d|r",
                    nameColor,
                    data.name,
                    data.dungeon or KeyRoll.GetDungeonNameByID(data.mapID) or ("Unknown (" .. tostring(data.mapID) .. ")"),
                    levelColor,
                    data.level
                )
                row.text:SetText(text)
                row:Show()
            end
        end
        
        -- Hide unused rows
        for i = #keys + 1, #self.rows do
            if self.rows[i] then
                self.rows[i]:Hide()
            end
        end
        
        -- Show "No keys" message if empty
        if #keys == 0 then
            local row = self.rows[1]
            if row then
                local msg
                if self.activeTab == "party" then
                    msg = "|cffaaaaaa No party keystones found. Ask players to link keys.|r"
                elseif self.activeTab == "guild" then
                    msg = "|cffaaaaaa No guild keystones found.\nInvite guild members to party or have them install Astral Keys.|r"
                elseif self.activeTab == "friends" then
                    msg = "|cffaaaaaa No friend keystones found.\nFriends must have a keystone addon installed (Astral Keys, BigWigs, DBM, etc.)|r"
                end
                row.text:SetText(msg)
                row:Show()
            end
        end
    end
end

-------------------------------------------------
-- Safe send
-------------------------------------------------
local function SendMessage(text, opts)
    opts = opts or {}
    local localOnly = opts.localOnly or false

    -- Always print locally if forced, not in a real party, or debug mode
    if localOnly or not IsInRealParty() or KeyRoll.Debug then
        print(KeyRoll.PREFIX, text)
    else
        -- Only send to party if in a real party and not forced local
        SendChatMessage(text, "PARTY")
    end
end

-------------------------------------------------
-- Slash commands
-------------------------------------------------
SLASH_KEYROLL1 = "/keyroll"
SLASH_KEYROLL2 = "/kr"
SlashCmdList["KEYROLL"] = function(msg)
    msg = (msg or ""):lower()

    -- Default: Open stored frame (when no arguments)
    if msg == "" then
        if not KeyRoll.StoredFrame then KeyRoll.CreateStoredFrame() end
        KeyRoll.StoredFrame:Show()
        KeyRoll.StoredFrame:Refresh()
        return
    end

    -- Roll subcommand
    if msg == "roll" then
        -- Handle roll at the end of this function
        msg = "roll"  -- Mark for processing below
    
    -- List subcommand
    elseif msg == "list" then
        -- Handle list later in the function
        msg = "list"  -- Mark for processing below
    
    -- Capture subcommand
    elseif msg == "capture" then
        KeyRoll.ManualCapture()
        return
    
    -- Clear subcommand
    elseif msg == "clear" then
        -- Fully wipe the party cache only (not guild or friend caches)
        for name in pairs(cache) do
            cache[name] = nil
        end
        KeyRoll.SendMessage("Party cache cleared. All party keystones removed.", {localOnly=true})
        KeyRoll.SendMessage("(Guild and Friend keystones are not affected)", {localOnly=true})
        
        -- Refresh stored frame if shown
        if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
            KeyRoll.StoredFrame:Refresh()
        end
        return
    
    -- Help subcommand
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

    -- Debug commands
    elseif msg:find("^debug") then
		local arg = msg:match("^debug%s*(%S*)") or ""

		if arg == "" then
			-- Toggle debug mode (does not persist)
			KeyRoll.Debug = not KeyRoll.Debug
			local state = KeyRoll.Debug and "enabled" or "disabled"
			KeyRoll.SendMessage("Debug mode " .. state .. ".", {localOnly=true})

			-- Clear debug keys if turning off
			if not KeyRoll.Debug then
				KeyRoll.DebugClear()
			end

		elseif arg == "seed" then
			-- Seed debug keys
			KeyRoll.DebugSeed()
			KeyRoll.SendMessage("Debug keys added.", {localOnly=true})

			-- Refresh stored frame if shown
			if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
				KeyRoll.StoredFrame:Refresh()
			end

		elseif arg == "clear" then
			-- Clear debug keys
			KeyRoll.DebugClear()
			KeyRoll.SendMessage("Debug keys cleared.", {localOnly=true})

			-- Refresh stored frame if shown
			if KeyRoll.StoredFrame and KeyRoll.StoredFrame:IsShown() then
				KeyRoll.StoredFrame:Refresh()
			end

		elseif arg == "cache" then
			-- Dump raw cache for debugging
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
			-- Dump entire KeyRollDB for debugging
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
			-- Show guild cache stats
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
			-- Show friend cache stats
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
			-- Show raw KeyRollGlobalDB
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
			-- Show debug help
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
	
	-- Unrecognized command
	else
		KeyRoll.SendMessage('Command not recognized. Type "/kr help" to view accepted commands.', {localOnly=true})
		return
	end

    -- Not in party check only applies for roll and list commands
    if msg == "list" or msg == "roll" then
        if not KeyRoll.IsInRealParty() and not KeyRoll.IsDebug() then
            KeyRoll.SendMessage("KeyRoll commands are disabled outside a real party.", {localOnly=true})
            return
        end
    end

    -- List keys (read-only) - PARTY KEYS ONLY
	if msg == "list" then
		KeyRoll.PruneCache()
		local keys = GetRollableKeys()  -- Gets party keys only

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
	
	-- Announce flavor text
    KeyRoll.SendMessage(ROLL_MESSAGES[math.random(#ROLL_MESSAGES)])

    C_Timer.After(1.5, function()
        local keysNow = GetRollableKeys()
        if #keysNow == 0 then
            KeyRoll.SendMessage("No rollable keys available.", {localOnly=true})
            return
        end
		
		-- Pick a random key to roll
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
KeyRoll.IsDebug = IsDebug
KeyRoll.DebugPrint = DebugPrint
KeyRoll.MarkCacheDirty = MarkCacheDirty
KeyRoll.StoreKey = StoreKey
KeyRoll.StoreMyKey = StoreMyKey
KeyRoll.StoreGuildKey = StoreGuildKey
KeyRoll.GetDungeonNameByID = GetDungeonNameByID
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