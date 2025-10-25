-- TanaanTracker: Sync.lua
TanaanTracker = TanaanTracker or {}

-------------------------------------------------
-- CONFIG
-------------------------------------------------
local SYNC_PREFIX         = "TanaanTracker"
local SYNC_THROTTLE       = 3
local SYNC_REPLY_INTERVAL = 0.20
local lastSent = {}
local lastSyncTime = 0

-------------------------------------------------
-- SAFE PREFIX REGISTER (post-login)
-------------------------------------------------
local function TryRegisterPrefix()
    if type(RegisterAddonMessagePrefix) == "function" then
        RegisterAddonMessagePrefix(SYNC_PREFIX)
    end
end

-- login hook: register prefix, then request guild sync (with safer delay)
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    -- wait a bit for prefix registration + guild channel ready
    C_Timer.After(2, function()
        TryRegisterPrefix()

        -- delay slightly more to ensure other guildies' addons are ready, lag compensation goes brrrr
        C_Timer.After(math.random(5, 10), function()
            if TanaanTracker.RequestGuildSync and (GetServerTime() - lastSyncTime > 30) then
                lastSyncTime = GetServerTime()

                local loginRealm = GetRealmName() or "Unknown Realm"
                TanaanTracker._syncRealmAtLogin = loginRealm

                local oldRealmDB = TanaanTracker.RealmDB
                TanaanTracker.RealmDB = function()
                    return TanaanTrackerDB.realms[loginRealm]
                end

                TanaanTracker.RequestGuildSync()

                C_Timer.After(5, function()
                    TanaanTracker.RealmDB = oldRealmDB
                    TanaanTracker._syncRealmAtLogin = nil
                end)
            end
        end)
    end)
end)

-------------------------------------------------
-- RESPOND TO SYNC REQUESTS (now sends ALL realms)
-------------------------------------------------
function TanaanTracker.HandleSyncRequest(sender)
    if not IsInGuild() or sender == UnitName("player") then return end
    if not SendAddonMessage then return end
    if not TanaanTrackerDB or not TanaanTrackerDB.realms then return end

    print("|cff66ff66[TanaanTracker]|r Guild sync request from |cffffff00" ..
        (sender or "?") .. "|r — sending all realm data...")

    local i = 0
    for realmName, realmDB in pairs(TanaanTrackerDB.realms) do
        for rareName, t in pairs(realmDB) do
            if type(t) == "number" and rareName then
                i = i + 1
                local msg = string.format("SYNC|%s|%d|%s|%s",
                    rareName, t, UnitName("player") or "Unknown", realmName)
                C_Timer.After(SYNC_REPLY_INTERVAL * i, function()
                    SendAddonMessage(SYNC_PREFIX, msg, "GUILD")
                end)
            end
        end
    end
end

-- Broadcast my full (multi-realm) dataset to the guild
function TanaanTracker.BroadcastAllRealms(reason)
    if not IsInGuild() or not SendAddonMessage then return end
    if not TanaanTrackerDB or not TanaanTrackerDB.realms then return end

    local who = UnitName("player") or "Unknown"
    local i = 0
    for realmName, realmDB in pairs(TanaanTrackerDB.realms) do
        for rareName, t in pairs(realmDB) do
            if type(t) == "number" then
                i = i + 1
                local msg = string.format("SYNC|%s|%d|%s|%s", rareName, t, who, realmName)
                C_Timer.After(SYNC_REPLY_INTERVAL * i, function()
                    SendAddonMessage(SYNC_PREFIX, msg, "GUILD")
                end)
            end
        end
    end

    if TanaanTrackerDB.debug and reason == "SELF" then
        print("|cff66ff66[TanaanTracker]|r Sent my full dataset to guild (login broadcast).")
    end
end


-------------------------------------------------
-- SEND SYNC (broadcast on kill)
-------------------------------------------------
function TanaanTracker.SendGuildSync(rareName, timestamp)
    if not rareName or not timestamp then return end
    if not IsInGuild() or not SendAddonMessage then return end

    local now = GetServerTime()
    if lastSent[rareName] and (now - lastSent[rareName]) < SYNC_THROTTLE then
        return
    end
    lastSent[rareName] = now

    local sender = UnitName("player") or "Unknown"
    local realm = GetRealmName() or "Unknown"
    local msg = string.format("%s|%d|%s|%s", rareName, timestamp, sender, realm)
    SendAddonMessage(SYNC_PREFIX, msg, "GUILD")
end

-------------------------------------------------
-- RECEIVE SYNC  (accepts SYNC from any channel; REQ only from GUILD)
-------------------------------------------------
do
    local function IsSelf(sender)
        if not sender or sender == "" then return false end
        local myName = UnitName("player") or ""
        local myRealm = GetRealmName() or ""
        return sender == myName or sender == (myName .. "-" .. myRealm)
    end

    function TanaanTracker.OnAddonMessage(prefix, message, channel, sender)
        if prefix ~= SYNC_PREFIX then return end
        if not message or message == "" or IsSelf(sender) then return end

        local msgType = strsplit("|", message)

        -- 1) Guild REQ -> reply (manual /tsync REQ is handled in Sync_Manual.lua)
        if msgType == "REQ" then
            if channel == "GUILD" then
                local _, reqSender = strsplit("|", message)
                TanaanTracker.HandleSyncRequest(reqSender)
            end
            return
        end

        -------------------------------------------------
        -- 2) structured SYNC line (supports multi-realm + bidirectional)
        --    accept from ANY channel (GUILD/PARTY/RAID/INSTANCE_CHAT/WHISPER).
        -------------------------------------------------
        if msgType == "SYNC" then
            -- Format: SYNC|rareName|timestamp|origin|realmName
            local _, rareName, ts, origin, realmName = strsplit("|", message)
            local tnum = tonumber(ts)
            local rares = TanaanTracker.rares
            local targetRealm = realmName or GetRealmName() or "Unknown"

            if rareName and tnum and rares and rares[rareName] then
                TanaanTrackerDB.realms = TanaanTrackerDB.realms or {}
                TanaanTrackerDB.realms[targetRealm] = TanaanTrackerDB.realms[targetRealm] or {}
                local dbTarget = TanaanTrackerDB.realms[targetRealm]
                local old = dbTarget[rareName]

                if not old or tnum > old then
                    dbTarget[rareName] = tnum
                    print(string.format("|cff00ff00[TanaanTracker]|r Updated %s (%s) from %s.",
                        rareName, targetRealm, origin or sender))

                    if TanaanTracker.currentRealmView == targetRealm and TanaanTracker.UpdateUI then
                        TanaanTracker.UpdateUI()
                    end

                    -- progress tracker for auto-summaries
                    if TanaanTracker._syncStartTime then
                        TanaanTracker._syncGotUpdate = true
                        TanaanTracker._syncUpdatesCount = (TanaanTracker._syncUpdatesCount or 0) + 1
                    end
                end
            end
            return
        end

        -------------------------------------------------
        -- 3) Legacy fallback "<rare>|<ts>|<origin>|<realm>"
        --    accept from ANY channel; only send correction back to GUILD.
        -------------------------------------------------
        local rareName, ts, origin, realm = strsplit("|", message)
        local tnum = tonumber(ts)
        local rares = TanaanTracker.rares

        if rareName and tnum and rares and rares[rareName] then
            local targetRealm = realm or GetRealmName() or "Unknown"
            TanaanTrackerDB.realms = TanaanTrackerDB.realms or {}
            TanaanTrackerDB.realms[targetRealm] = TanaanTrackerDB.realms[targetRealm] or {}
            local dbTarget = TanaanTrackerDB.realms[targetRealm]
            local myTs = dbTarget[rareName]

            if not myTs or tnum > myTs then
                dbTarget[rareName] = tnum
                print(string.format("|cff00ff00[TanaanTracker]|r Updated %s (%s) from %s.",
                    rareName, targetRealm, origin or sender))
                if TanaanTracker.currentRealmView == targetRealm and TanaanTracker.UpdateUI then
                    TanaanTracker.UpdateUI()
                end
                if TanaanTracker._syncStartTime then
                    TanaanTracker._syncGotUpdate = true
                    TanaanTracker._syncUpdatesCount = (TanaanTracker._syncUpdatesCount or 0) + 1
                end

            elseif myTs and myTs > (tnum + 5) and channel == "GUILD" then
                -- Only correct back on guild channel (avoid noise on party/raid/instance/whisper)
                local me = UnitName("player") or "Unknown"
                local msgBack = string.format("SYNC|%s|%d|%s|%s", rareName, myTs, me, targetRealm)
                C_Timer.After(0.1, function()
                    SendAddonMessage(SYNC_PREFIX, msgBack, "GUILD")
                end)
            end
        end
    end
end



-------------------------------------------------
-- REQUEST GUILD SYNC
-------------------------------------------------
function TanaanTracker.RequestGuildSync()
    if not IsInGuild() or not SendAddonMessage then return end
    local who = UnitName("player") or "Unknown"

    -- Ask others to send their data
    SendAddonMessage(SYNC_PREFIX, "REQ|" .. who, "GUILD")
    print("|cff66ff66[TanaanTracker]|r Requesting guild sync...")

    -- Track whether we received any updates within 5 seconds
    TanaanTracker._syncStartTime = GetTime()
    TanaanTracker._syncGotUpdate = false
    TanaanTracker._syncUpdatesCount = 0

    -- After 5 seconds, summarize sync result
    C_Timer.After(5, function()
        if TanaanTracker._syncGotUpdate then
            print(string.format("|cff66ff66[TanaanTracker]|r %d timer%s updated from guild.",
                TanaanTracker._syncUpdatesCount,
                TanaanTracker._syncUpdatesCount == 1 and "" or "s"))
        else
            print("|cff66ff66[TanaanTracker]|r No data to sync — already up to date!")
        end
        TanaanTracker._syncStartTime = nil
        TanaanTracker._syncGotUpdate = nil
        TanaanTracker._syncUpdatesCount = nil
    end)

    -- Also send my data so guildies with empty DB get populated immediately
    -- (small delay lets other clients finish prefix/event init)
    C_Timer.After(1.0 + math.random(), function()
        if TanaanTracker.BroadcastAllRealms then
            TanaanTracker.BroadcastAllRealms("SELF")
        end
    end)
end

