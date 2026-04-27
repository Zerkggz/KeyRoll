KeyRoll = KeyRoll or {}
KeyRollDB = KeyRollDB or {}
KeyRoll.Debug = false
KeyRoll.PREFIX = "|cff00ff00[KeyRoll]|r"

local guildRosterLoaded = false

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GUILD_ROSTER_UPDATE")

frame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "KeyRoll" then
        if IsInGuild() then
            C_GuildInfo.GuildRoster()
        end
        self:UnregisterEvent("ADDON_LOADED")
        
    elseif event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() then
            C_Timer.After(2, function()
                C_GuildInfo.GuildRoster()
            end)
        end
        
    elseif event == "GUILD_ROSTER_UPDATE" then
        if not guildRosterLoaded and IsInGuild() then
            guildRosterLoaded = true
            if KeyRoll.CaptureMyKeystone then
                C_Timer.After(0.5, function()
                    KeyRoll.CaptureMyKeystone()
                end)
            end
        end
    end
end)