-- TanaanTracker: Core.lua
local ADDON_NAME = ...
TanaanTracker = TanaanTracker or {}
TanaanTrackerDB = TanaanTrackerDB or {}
TanaanTrackerCharDB = TanaanTrackerCharDB or {}

-------------------------------------------------------------
-- Realm-based data separation (per-realm SavedVariables)
-------------------------------------------------------------
local currentRealm = GetRealmName() or "Unknown"
TanaanTracker.activeRealm = GetRealmName() or "Unknown"

-- Ensure top-level SavedVariables exist
if type(TanaanTrackerDB) ~= "table" then TanaanTrackerDB = {} end
if type(TanaanTrackerDB.realms) ~= "table" then TanaanTrackerDB.realms = {} end

-- Ensure this realm’s subtable exists (never overwrite existing data)
if type(TanaanTrackerDB.realms[currentRealm]) ~= "table" then
    TanaanTrackerDB.realms[currentRealm] = {}
end

-- always resolve the live realm table (lag / odd load order proof)
function TanaanTracker:RealmDB()
    local realm = TanaanTracker.activeRealm or GetRealmName() or "Unknown"
    if type(TanaanTrackerDB.realms) ~= "table" then
        TanaanTrackerDB.realms = {}
    end
    if type(TanaanTrackerDB.realms[realm]) ~= "table" then
        TanaanTrackerDB.realms[realm] = {}
    end
    return TanaanTrackerDB.realms[realm]
end

-- Returns whichever realm the user is viewing in the dropdown
function TanaanTracker:ViewedRealmDB()
    local realm = TanaanTracker.currentRealmView or TanaanTracker.activeRealm or GetRealmName() or "Unknown"
    if type(TanaanTrackerDB.realms) ~= "table" then return {} end
    return TanaanTrackerDB.realms[realm] or {}
end


-------------------------------------------------------------
-- Backward compatibility shim for pre-realm data
-- (copies old flat keys into this realm table; never deletes)
-------------------------------------------------------------
for rareName in pairs(TanaanTracker.rares or {}) do
    local oldValue = TanaanTrackerDB[rareName]
    if type(oldValue) == "number" and not TanaanTracker:RealmDB()[rareName] then
        TanaanTracker:RealmDB()[rareName] = oldValue
        -- do NOT nil the old key; harmless to leave for old clients
    end
end

-------------------------------------------------------------
-- Event frame
-------------------------------------------------------------
local EF = CreateFrame("Frame")
EF:RegisterEvent("PLAYER_LOGIN")
EF:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
EF:RegisterEvent("LOOT_OPENED")
EF:RegisterEvent("CHAT_MSG_ADDON")

-------------------------------------------------------------
-- Per-character daily kill tracking
-------------------------------------------------------------
function TanaanTracker.GetCharKey()
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName() or "Unknown"
    return name .. "-" .. realm
end

function TanaanTracker.GetServerDayKey()
    local now = GetServerTime()
    return math.floor(now / 86400)
end

function TanaanTracker.MarkCharKillToday(rareName)
    if not rareName then return end
    local realmOffset = (date("!%m") >= "03" and date("!%m") < "11") and 2 or 1
    local nowUTC = time(date("!*t"))
    local realmTime = nowUTC + (realmOffset * 3600)

    local dateTbl = date("!*t", realmTime)
    local resetHour = 6
    if dateTbl.hour < resetHour then
        local yesterday = time(date("*t", realmTime - 86400))
        dateTbl = date("!*t", yesterday)
    end

    local key = string.format("%04d-%02d-%02d", dateTbl.year, dateTbl.month, dateTbl.day)
    local charKey = UnitName("player") .. "-" .. GetRealmName()

    TanaanTrackerDB.charKills = TanaanTrackerDB.charKills or {}
    TanaanTrackerDB.charKills[charKey] = TanaanTrackerDB.charKills[charKey] or {}
    TanaanTrackerDB.charKills[charKey][key] = TanaanTrackerDB.charKills[charKey][key] or {}
    TanaanTrackerDB.charKills[charKey][key][rareName] = true
end

function TanaanTracker.CharKilledToday(rareName)
    if not rareName then return false end
    local realmOffset = (date("!%m") >= "03" and date("!%m") < "11") and 2 or 1
    local nowUTC = time(date("!*t"))
    local realmTime = nowUTC + (realmOffset * 3600)

    local dateTbl = date("!*t", realmTime)
    local resetHour = 7
    if dateTbl.hour < resetHour then
        local yesterday = time(date("*t", realmTime - 86400))
        dateTbl = date("!*t", yesterday)
    end

    local key = string.format("%04d-%02d-%02d", dateTbl.year, dateTbl.month, dateTbl.day)
    local charKey = UnitName("player") .. "-" .. GetRealmName()

    local kills = TanaanTrackerDB.charKills and TanaanTrackerDB.charKills[charKey] and TanaanTrackerDB.charKills[charKey][key]
    return kills and kills[rareName] or false
end

-------------------------------------------------------------
-- Locals / State
-------------------------------------------------------------
local WRITE_THROTTLE = 5
local lastWrite = {}
local alerted = {}

-------------------------------------------------------------
-- Alerts (5m warning text and sound + 1m local)
-------------------------------------------------------------
local function MaybeAlert(rareName, remaining)
    if not remaining or remaining <= 0 then
        alerted[rareName] = nil
        return
    end

    local lastAlert = alerted[rareName]

    -- only track within 5 min window
    if remaining > 300 then
        alerted[rareName] = nil
        return
    end

    local minutes = math.floor(remaining / 60)

    local function ColoredName(name)
        return string.format("|cffffd100%s|r", name)
    end

    local function ShowCenterMessage(msg)
        if not TanaanTrackerAlertFrame then
            local f = CreateFrame("Frame", "TanaanTrackerAlertFrame", UIParent)
            f:SetSize(800, 100)
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 150)

            local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
            text:SetAllPoints()
            text:SetJustifyH("CENTER")
            text:SetTextColor(1, 0.5, 0, 1)
            text:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
            f.text = text

            f.fade = f:CreateAnimationGroup()
            local fade = f.fade:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0)
            fade:SetDuration(2.5)
            fade:SetStartDelay(4)
            fade:SetSmoothing("OUT")
            f.fade:SetScript("OnFinished", function() f:Hide() end)
            TanaanTrackerAlertFrame = f
        end

        local f = TanaanTrackerAlertFrame
        f.text:SetText(msg)
        f:SetAlpha(1)
        f:Show()
        f.fade:Stop()
        f.fade:Play()
    end

    -------------------------------------------------
    -- helper: Are we in combat with a known rare?
    -------------------------------------------------
    local function IsFightingRare()
        if not UnitAffectingCombat("player") then return false end
        local rares = TanaanTracker.rares
        if not rares then return false end

        local function checkUnit(u)
            local n = UnitName(u)
            return n and rares[n]
        end

        if checkUnit("target") or checkUnit("focus") then return true end
        for i = 1, 4 do
            if checkUnit("boss" .. i) then return true end
        end
        return false
    end

    -------------------------------------------------
    -- 5-minute warning: only fire once, only if not in rare combat
    -------------------------------------------------
    if not lastAlert and remaining <= 300 and remaining > 240 then
        alerted[rareName] = 5

        local msg = string.format("%s respawns in ~5 minutes!", ColoredName(rareName))
        ShowCenterMessage(msg)
        print("|cffffd200[TanaanTracker]|r " .. msg)

        if not IsFightingRare() then
            PlaySoundFile("Sound\\interface\\alarmclockwarning2.ogg", "Master")
        end

    -------------------------------------------------
    -- 1-minute warning: once only, no sound
    -------------------------------------------------
    elseif lastAlert ~= 1 and remaining <= 60 and remaining > 0 then
        alerted[rareName] = 1
        local msg = string.format("%s respawns in ~1 minute!", ColoredName(rareName))
        print("|cffffd200[TanaanTracker]|r " .. msg)
    end
end

TanaanTracker._MaybeAlert = MaybeAlert

-------------------------------------------------------------
-- Background Alert Runner (UI-independent)
-------------------------------------------------------------
local bgAlertFrame = CreateFrame("Frame")
local elapsed = 0
bgAlertFrame:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 60 then return end
    elapsed = 0

    if not TanaanTracker.rares then return end
    local now = GetServerTime()

    for rareName, data in pairs(TanaanTracker.rares) do
        local lastKill = TanaanTracker:RealmDB()[rareName]
        if lastKill and type(lastKill) == "number" then
            local remaining = (lastKill + (data.respawn or 3600)) - now
            if remaining > 0 and remaining <= 300 then
                if TanaanTracker._MaybeAlert then
                    TanaanTracker._MaybeAlert(rareName, remaining)
                end
            end
        end
    end
end)

-------------------------------------------------------------
-- Debug & Utility
-------------------------------------------------------------
function TanaanTracker:DebugPrint(...)
    if TanaanTrackerDB.debug then print("|cFF00FFFF[TanaanTracker DEBUG]|r", ...) end
end

function TanaanTracker:GetServerNow() return GetServerTime() end

local function safeTimeAgo(sec)
    if not sec or type(sec) ~= "number" then return "?" end
    local diff = TanaanTracker:GetServerNow() - sec
    if diff < 60 then return string.format("%ds ago", diff)
    elseif diff < 3600 then return string.format("%dm ago", math.floor(diff/60))
    else return string.format("%dh %dm ago", math.floor(diff/3600), math.floor((diff%3600)/60)) end
end

local function formatCountdown(sec)
    if not sec or sec <= 0 then return "0s" end
    local h = math.floor(sec/3600)
    local m = math.floor((sec%3600)/60)
    local s = sec % 60
    if h > 0 then return string.format("%dh %dm %ds", h, m, s)
    elseif m > 0 then return string.format("%dm %ds", m, s)
    else return string.format("%ds", s) end
end

local function safeFormatTime(t)
    if not t or type(t) ~= "number" or t <= 0 then return "?" end
    local utc = date("!*t", t)
    local function lastSunday(year, month)
        local d = time({year = year, month = month + 1, day = 0, hour = 12})
        local wd = tonumber(date("!%w", d))
        return d - (wd * 86400)
    end

    local year = utc.year
    local dstStart = lastSunday(year, 3) + 2 * 3600
    local dstEnd   = lastSunday(year, 10) + 3 * 3600
    local isDST = (t >= dstStart and t < dstEnd)
    local offset = isDST and 2 * 3600 or 1 * 3600
    local cetTime = t + offset
    local ct = date("!*t", cetTime)
    local hour = ct.hour
    local ampm = "AM"
    if hour >= 12 then ampm = "PM"; if hour > 12 then hour = hour - 12 end
    elseif hour == 0 then hour = 12 end
    return string.format("%d:%02d%s", hour, ct.min, ampm)
end

local function announce(msg, where)
    where = (where or ""):lower()
    if where == "say" then SendChatMessage(msg, "SAY")
    elseif where == "yell" then SendChatMessage(msg, "YELL")
    elseif where == "guild" then SendChatMessage(msg, "GUILD")
    elseif where == "party" then SendChatMessage(msg, "PARTY")
    elseif where == "raid" then SendChatMessage(msg, "RAID")
    else print("|cffffd200[TanaanTracker]|r " .. msg) end
end

function TanaanTracker:RunSlash(text)
    local editBox = ChatEdit_ChooseBoxForSend(DEFAULT_CHAT_FRAME)
    if not editBox then return end
    ChatEdit_ActivateChat(editBox)
    editBox:SetText(text)
    ChatEdit_OnEnterPressed(editBox)
end

TanaanTracker.safeTimeAgo = safeTimeAgo
TanaanTracker.formatCountdown = formatCountdown
TanaanTracker.safeFormatTime = safeFormatTime
TanaanTracker.announce = announce

-------------------------------------------------------------
-- UI updater ticker
-------------------------------------------------------------
local uiTicker = 0
local updater = CreateFrame("Frame")
updater:SetScript("OnUpdate", function(_, elapsed)
    uiTicker = uiTicker + elapsed
    if uiTicker >= (TanaanTracker.UI_UPDATE_INTERVAL or 1) then
        uiTicker = 0
        if TanaanTracker.mainFrame and TanaanTracker.mainFrame:IsShown() and TanaanTracker.UpdateUI then
            TanaanTracker.UpdateUI()
        end
    end
end)

-------------------------------------------------------------
-- Slash Command /tan
-------------------------------------------------------------
SLASH_TAN1 = "/tan"
SlashCmdList["TAN"] = function(msg)
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = (cmd or ""):lower()

    -------------------------------------------------
    -- HELP COMMAND
    -------------------------------------------------
    if cmd == "help" or cmd == "?" then
        print("|cff66c0f4TanaanTracker|r |cffffff00Available Commands:|r")
        print("  |cff66c0f4/tan|r - Toggle the UI")
        print("  |cff66c0f4/tan <rare name>|r - Print spawn for a specific rare")
        print("  |cff66c0f4/tan <channel>|r - Announce all timers to: say, yell, guild, party, raid")
        print("  |cff66c0f4/tan ver or version|r - Show the addon version")
        print("  |cff66c0f4/tsync|r - Manual on-demand sync (guild/party/whisper)")
        print(" ")
        print("|cffaaaaaaTip:|r Type |cffffff00/tan reset confirm|r to safely clear all data.")
        return
    end

    -------------------------------------------------
    -- VERSION COMMAND
    -------------------------------------------------
    if cmd == "ver" or cmd == "version" then
        local ver = GetAddOnMetadata("TanaanTracker", "Version") or "unknown"
        print(string.format("|cff66ff66[TanaanTracker]|r version: |cffffff00%s|r", ver))
        return
    end

    -------------------------------------------------
    -- RESET COMMAND (with confirmation)
    -------------------------------------------------
    if cmd == "reset" then
        if arg ~= "confirm" then
            print("|cffffd200Tanaan Tracker|r: This will |cffff0000DELETE ALL TIMER DATA|r across all realms!")
            print("Type |cff66c0f4/tan reset confirm|r to proceed.")
            return
        end

        local keepAuto = TanaanTrackerDB and TanaanTrackerDB.autoAnnounce or false
        TanaanTrackerDB = {
            realms = {},
            autoAnnounce = keepAuto,
            debug = false,
        }

        print("|cffffd200Tanaan Tracker|r: All timer data has been fully reset.")
        if keepAuto then
            print("|cffaaaaaa(auto-announce setting preserved)|r")
        end

        if TanaanTracker.mainFrame then
            TanaanTracker.mainFrame:Hide()
            C_Timer.After(0.1, function()
                TanaanTracker.mainFrame:Show()
                if TanaanTracker.UpdateUI then
                    TanaanTracker.UpdateUI()
                end
            end)
        elseif TanaanTracker.UpdateUI then
            TanaanTracker.UpdateUI()
        end
        return
    end

    -------------------------------------------------
    -- RARE LOOKUP
    -------------------------------------------------
    local rares = TanaanTracker.rares
    local raresOrder = TanaanTracker.raresOrder
    local rareName
    for name, data in pairs(rares) do
        if cmd == name:lower() then rareName = name; break end
        if data.aliases then
            for _, alias in ipairs(data.aliases) do
                if cmd == alias:lower() then rareName = name; break end
            end
        end
        if rareName then break end
    end

    if rareName then
        local t = TanaanTracker:RealmDB()[rareName]
        if t and type(t) == "number" then
            local remaining = (t + rares[rareName].respawn) - TanaanTracker:GetServerNow()
            if remaining < 0 then remaining = 0 end
            local msgOut = string.format("%s: next respawn ~%s (killed at %s)",
                rareName, TanaanTracker.formatCountdown(remaining), TanaanTracker.safeFormatTime(t))
            if arg ~= "" then TanaanTracker.announce(msgOut, arg) else print(msgOut) end
        else
            print(rareName .. ": no data yet")
        end
        return
    end

    -------------------------------------------------
    -- CHANNEL ANNOUNCEMENTS
    -------------------------------------------------
    local validChannels = { say=true, yell=true, guild=true, party=true, raid=true }
    if cmd ~= "" and validChannels[cmd] then
        for _, name in ipairs(raresOrder) do
            local t = TanaanTracker:RealmDB()[name]
            if t and type(t) == "number" then
                local remaining = (t + rares[name].respawn) - TanaanTracker:GetServerNow()
                if remaining < 0 then remaining = 0 end
                local msgOut = string.format("%s: next respawn ~%s", name, TanaanTracker.formatCountdown(remaining))
                TanaanTracker.announce(msgOut, cmd)
            end
        end
        return
    end

    -------------------------------------------------
    -- DEFAULT: TOGGLE WINDOW (no argument)
    -------------------------------------------------
    if cmd == "" then
        if not TanaanTracker.mainFrame and TanaanTracker.CreateMainFrame then
            TanaanTracker.CreateMainFrame()
        end
        if not TanaanTracker.mainFrame then return end

        if TanaanTracker.mainFrame:IsShown() then
            TanaanTracker.mainFrame:Hide()
        else
            TanaanTracker.mainFrame:Show()
            if TanaanTracker.UpdateUI then TanaanTracker.UpdateUI() end
        end
        return
    end

    -------------------------------------------------
    -- UNKNOWN COMMAND HANDLER
    -------------------------------------------------
    print("|cffff0000Unknown command:|r " .. cmd)
    print("Type |cff66c0f4/tan help|r for a list of available commands.")
end



-------------------------------------------------------------
-- Combat Log + Loot tracking
-------------------------------------------------------------
local function handleCombatLog(...)
    local _, subevent, _, _, _, _, _, destGUID, destName = ...

    if not destGUID or not subevent then return end

    -- only care about unit deaths
    if subevent ~= "UNIT_DIED" and subevent ~= "PARTY_KILL" then return end

    -- extract NPC ID from GUID
    local npcId = tonumber(destGUID:match("-(%d+)-%x+$"))
    if not npcId then return end

    local rares = TanaanTracker.rares
    for rareName, data in pairs(rares) do
        if data.id == npcId then
            local now = TanaanTracker:GetServerNow()
            local last = lastWrite[rareName] or 0
            if (now - last) < WRITE_THROTTLE then return end

            -- save kill time to DB
            TanaanTracker:RealmDB()[rareName] = now
            TanaanTracker.MarkCharKillToday(rareName)

            -- auto announce to guild
            if TanaanTrackerDB.autoAnnounce and IsInGuild() then
                local msg = string.format("%s down — respawn ~%dm", rareName, data.respawn / 60)
                SendChatMessage(msg, "GUILD")
            end

            lastWrite[rareName] = now
            print(string.format("|cffff0000%s killed!|r Respawn timer started (%d min).", rareName, data.respawn / 60))

            TanaanTracker:DebugPrint("Saved time for", rareName, now)

            -- sync and update UI
            if TanaanTracker.SendGuildSync then
                TanaanTracker.SendGuildSync(rareName, now)
            end
            if TanaanTracker.UpdateUI then
                TanaanTracker.UpdateUI()
            end
            break
        end
    end
end


local function handleLootOpened()
    local target = UnitName("target")
    if not target or type(target) ~= "string" then return end
    local rares = TanaanTracker.rares
    for rareName, data in pairs(rares) do
        if target:find(rareName, 1, true) then
            local now = TanaanTracker:GetServerNow()
            local last = lastWrite[rareName] or 0
            if (now - last) < WRITE_THROTTLE then return end
            -- save kill time to DB
            TanaanTracker:RealmDB()[rareName] = now
            lastWrite[rareName] = now
            -- mark character kill
            if TanaanTracker.MarkCharKillToday then
                TanaanTracker.MarkCharKillToday(rareName)
            end
            -- local message
            print(string.format("|cff00ff00Looted %s!|r Respawn timer started (%d min).", rareName, data.respawn / 60))
            -- sync and update UI
            if TanaanTracker.SendGuildSync then
                TanaanTracker.SendGuildSync(rareName, now)
            end
            if TanaanTracker.UpdateUI then
                TanaanTracker.UpdateUI()
            end

            TanaanTracker:DebugPrint("Saved time via loot for", rareName, now)
            return
        end
    end
end


EF:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        TanaanTrackerDB.debug = TanaanTrackerDB.debug or false
        TanaanTracker:DebugPrint("Loaded for realm:", currentRealm)
        if TanaanTracker.CreateMinimapButton then TanaanTracker.CreateMinimapButton() end
        if TanaanTracker.CreateMainFrame then TanaanTracker.CreateMainFrame() end
    elseif event == "CHAT_MSG_ADDON" then
        if TanaanTracker.OnAddonMessage then TanaanTracker.OnAddonMessage(...) end
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        handleCombatLog(...)
    elseif event == "LOOT_OPENED" then
        handleLootOpened()
    end
end)
