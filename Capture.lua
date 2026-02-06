-------------------------------------------------
-- Capture own keystone
-------------------------------------------------
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
                if itemLink then
                    -- Look for "Keystone:" in the link
                    if itemLink:find("Keystone:") then
                        -- Parse dungeon name and level from the link
                        local dungeonName, keyLevel = itemLink:match("%[Keystone:%s*(.-)%s*%((%d+)%)%]")
                        
                        if dungeonName and keyLevel then
                            mapID = KeyRoll.GetDungeonIDByName(dungeonName)
                            level = tonumber(keyLevel)
                            if mapID and level then break end
                        end
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
        
        -- Store in guild cache if we're in a guild
        if IsInGuild() then
            local _, class = UnitClass("player")
            if KeyRoll.StoreGuildKey then
                KeyRoll.StoreGuildKey(playerName, mapID, level, class)
                if KeyRoll.IsDebug() then
                    KeyRoll.DebugPrint("Stored in guild cache")
                end
            end
            
            -- Also broadcast to guild
            if KeyRoll.BroadcastKeystoneToGuild then
                KeyRoll.BroadcastKeystoneToGuild()
            end
        end
        
        return true
    end

    return false
end

-------------------------------------------------
-- Auto capture party keys
-------------------------------------------------
local function AutoCapturePartyKeys()
    KeyRoll.RequestPartyKeystones(false, true)
    
    -- After requesting keys, check if we need to prune
    -- Delay slightly to let requests complete
    C_Timer.After(1, function()
        if KeyRoll.PruneCache then
            KeyRoll.PruneCache()
        end
    end)
end

-------------------------------------------------
-- Manual capture
-------------------------------------------------
local function ManualCapture()
    local gotOwnKey = CaptureMyKeystone()

    if gotOwnKey then
        KeyRoll.SendMessage("Your keystone captured.", {localOnly=true})
    else
        KeyRoll.SendMessage("No keystone found in your bags.", {localOnly=true})
    end

    -- Request party keystones if in a group
    if IsInGroup() then
        KeyRoll.SendMessage("Requesting keystones from party members...", {localOnly=true})
        KeyRoll.RequestPartyKeystones(true)
    end
    
    -- Request friend keystones
    if KeyRoll.RequestFriendKeystones then
        KeyRoll.SendMessage("Requesting keystones from online friends...", {localOnly=true})
        KeyRoll.RequestFriendKeystones()
    end
end

-------------------------------------------------
-- Event handling
-------------------------------------------------
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
                
                -- Request keystones from guild members using KeyRoll
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
        
        -- Broadcast and request guild keystones when group changes
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
        -- Delay slightly to let party roster update after zone change
        C_Timer.After(0.5, function()
            AutoCapturePartyKeys()
            KeyRoll.MarkCacheDirty()
            
            -- Broadcast and request guild keystones after zone change
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
            -- Throttle bag scanning to prevent spam
            local now = GetTime()
            if now - lastBagUpdateTime >= BAG_UPDATE_THROTTLE then
                lastBagUpdateTime = now
                CaptureMyKeystone()
            end
        end

    elseif event == "CHALLENGE_MODE_COMPLETED" then
        -- Dungeon completed - update party keystones after 30 seconds (everyone gets new keys)
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