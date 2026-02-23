local function CaptureMyKeystone()
    if not C_Container then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Container API not available.")
        end
        return false
    end

    local playerName = Ambiguate(UnitName("player"), "short")
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

    if mapID and level then
        KeyRoll.StoreKey(playerName, mapID, level)
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Captured from bag:", KeyRoll.GetDungeonNameByID(mapID), "+" .. level)
        end
        
        if IsInGuild() then
            local _, class = UnitClass("player")
            local fullPlayerName, realm = UnitFullName("player")
            if fullPlayerName and realm and realm ~= "" then
                fullPlayerName = fullPlayerName .. "-" .. realm
            else
                fullPlayerName = playerName
            end
            
            if KeyRoll.StoreGuildKey then
                KeyRoll.StoreGuildKey(fullPlayerName, mapID, level, class)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("Stored in guild cache")
                end
            end
            
            if KeyRoll.BroadcastKeystoneToGuild then
                KeyRoll.BroadcastKeystoneToGuild()
            end
        end
        
        if KeyRoll.IsInRealParty() and KeyRoll.BroadcastKeystoneToParty then
            KeyRoll.BroadcastKeystoneToParty()
        end
        if KeyRoll.BroadcastKeystoneToFriends then
            KeyRoll.BroadcastKeystoneToFriends()
        end
        
        return true
    end

    return false
end

local function AutoCapturePartyKeys()
    C_Timer.After(0.5, function()
        KeyRoll.RequestPartyKeystones(false, true)
    end)

    C_Timer.After(1, function()
        if KeyRoll.PruneCache then
            KeyRoll.PruneCache()
        end
    end)
end

local function ManualCapture()
    local gotOwnKey = CaptureMyKeystone()

    if gotOwnKey then
        KeyRoll.SendMessage("Your keystone captured.", {localOnly=true})
    else
        KeyRoll.SendMessage("No keystone found in your bags.", {localOnly=true})
    end

    if IsInGroup() then
        KeyRoll.SendMessage("Requesting keystones from party members...", {localOnly=true})
        KeyRoll.RequestPartyKeystones(true)
    end
    
    if KeyRoll.RequestFriendKeystones then
        KeyRoll.SendMessage("Requesting keystones from online friends...", {localOnly=true})
        KeyRoll.RequestFriendKeystones()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("BAG_UPDATE")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

local loginCaptureComplete = false
local lastBagUpdateTime = 0
local BAG_UPDATE_THROTTLE = 10

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        C_Timer.After(2, function()
            if not loginCaptureComplete and C_Container then
                CaptureMyKeystone()
                loginCaptureComplete = true

                AutoCapturePartyKeys()
                
                if IsInGuild() and KeyRoll.RequestGuildKeystonesFromAddon then
                    C_Timer.After(3, function()
                        KeyRoll.RequestGuildKeystonesFromAddon()
                    end)
                end
            end
        end)

    elseif event == "GROUP_ROSTER_UPDATE" then
        AutoCapturePartyKeys()
        KeyRoll.MarkCacheDirty()
        
        if KeyRoll.BroadcastKeystoneToFriends then
            C_Timer.After(1, function()
                KeyRoll.BroadcastKeystoneToFriends()
            end)
        end
        if KeyRoll.BroadcastKeystoneToParty then
            C_Timer.After(1, function()
                if KeyRoll.IsInRealParty() then
                    KeyRoll.BroadcastKeystoneToParty()
                end
            end)
        end
        
        if IsInGuild() then
            if KeyRoll.BroadcastKeystoneToGuild then
                C_Timer.After(1, function()
                    KeyRoll.BroadcastKeystoneToGuild()
                end)
            end
            if KeyRoll.RequestGuildKeystonesFromAddon then
                C_Timer.After(2, function()
                    KeyRoll.RequestGuildKeystonesFromAddon()
                end)
            end
        end

    elseif event == "ZONE_CHANGED_NEW_AREA" then
        C_Timer.After(0.5, function()
            AutoCapturePartyKeys()
            KeyRoll.MarkCacheDirty()
            
            if KeyRoll.BroadcastKeystoneToFriends then
                C_Timer.After(1, function()
                    KeyRoll.BroadcastKeystoneToFriends()
                end)
            end
            if KeyRoll.BroadcastKeystoneToParty then
                C_Timer.After(1, function()
                    if KeyRoll.IsInRealParty() then
                        KeyRoll.BroadcastKeystoneToParty()
                    end
                end)
            end
            
            if IsInGuild() then
                if KeyRoll.BroadcastKeystoneToGuild then
                    C_Timer.After(1, function()
                        KeyRoll.BroadcastKeystoneToGuild()
                    end)
                end
                if KeyRoll.RequestGuildKeystonesFromAddon then
                    C_Timer.After(2, function()
                        KeyRoll.RequestGuildKeystonesFromAddon()
                    end)
                end
            end
        end)

    elseif event == "BAG_UPDATE" then
        if C_Container then
            local now = GetTime()
            if now - lastBagUpdateTime >= BAG_UPDATE_THROTTLE then
                lastBagUpdateTime = now
                CaptureMyKeystone()
            end
        end

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        if KeyRoll.IsDebug() then
            KeyRoll.DebugPrint("Dungeon completed - scheduling keystone update in 30 seconds")
        end
        
        KeyRoll.PruneCache()
        AutoCapturePartyKeys()

        C_Timer.After(30, function()
            if KeyRoll.IsDebug() then
                KeyRoll.DebugPrint("30 seconds elapsed - capturing new keystones")
            end
            ManualCapture()
        end)
    end
end)


KeyRoll.CaptureMyKeystone = CaptureMyKeystone
KeyRoll.ManualCapture = ManualCapture
KeyRoll.AutoCapturePartyKeys = AutoCapturePartyKeys