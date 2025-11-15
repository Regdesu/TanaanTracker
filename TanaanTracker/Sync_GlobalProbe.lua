-- TanaanTracker: Sync_GlobalProbe.lua
-- Global sync via /global chat probe + whisper sync using existing /tsync logic.

local TanaanTracker = TanaanTracker or {}

-------------------------------------------------
-- CONFIG
-------------------------------------------------
local SYNC_PREFIX          = "TanaanTracker"
local GLOBAL_CHANNEL_NAME  = "global"      
local COOLDOWN_SECONDS     = 3600          -- 1 hour between probes
local DISCOVERY_WINDOW     = 5.0           
local REPLY_THROTTLE       = 10.0         
local JITTER_MIN, JITTER_MAX = 0.3, 1.0    
local PROBE_TAG            = "#TT"

-------------------------------------------------
-- SAVED VAR DEFAULTS
-------------------------------------------------
TanaanTrackerDB = TanaanTrackerDB or {}
if TanaanTrackerDB.globalProbeLastAt == nil then
    TanaanTrackerDB.globalProbeLastAt = 0
end
if TanaanTrackerDB.globalProbeMessage == nil then
    TanaanTrackerDB.globalProbeMessage = "hi"
end
if TanaanTrackerDB.globalProbeConfirmed == nil then
    TanaanTrackerDB.globalProbeConfirmed = false
end

-------------------------------------------------
-- HELPERS
-------------------------------------------------
local function NowServer()
    return GetServerTime()
end

local function NowFrame()
    return GetTime()
end

local function MyName()
    return UnitName("player") or "Unknown"
end

local function MyRealm()
    return GetRealmName() or "Unknown Realm"
end

local function ShortName(full)
    if not full then return "" end
    local name = full:match("^[^%-]+")
    return name or full
end

local function PrintInfo(msg)
    print("|cff66ff66[TanaanTracker]|r " .. tostring(msg))
end

local function ProbeDebug(...)
    if not TanaanTrackerDB or not TanaanTrackerDB.debug then return end
    print("|cff00bfff[TanaanTracker:Probe DEBUG]|r", ...)
end

-- normalize realm names
local function CanonicalRealmName(raw)
    if not raw then return "" end
    raw = raw:lower()
    raw = raw:gsub("^%[(.-)%]%s*", "")
    raw = raw:gsub("%s+", "")
    return raw
end

-- return the user-chosen base text
local function EffectiveProbeMessage()
    local raw = TanaanTrackerDB.globalProbeMessage or "hi"
    raw = raw:gsub("|", "/")
    -- trim extremely long inputs
    if #raw > 120 then
        raw = raw:sub(1, 120)
    end
    return raw
end

--compute "freshness" for a given realm:
local function RealmFreshness(realmName)
    realmName = realmName or MyRealm()
    local rares  = TanaanTracker.rares
    local realms = TanaanTrackerDB and TanaanTrackerDB.realms
    if not rares or not realms then
        return 0, 0
    end

    local db = realms[realmName]
    if type(db) ~= "table" then
        return 0, 0
    end

    local maxTs, count = 0, 0
    for rareName in pairs(rares) do
        local ts = db[rareName]
        if type(ts) == "number" then
            count = count + 1
            if ts > maxTs then
                maxTs = ts
            end
        end
    end
    return maxTs, count
end

local function GetGlobalChannelId()
    local id = GetChannelName(GLOBAL_CHANNEL_NAME)
    if id and id > 0 then
        return id
    end
    return nil
end

-------------------------------------------------
-- OUTBOUND: POLL broadcast (GLOBAL chat)
--   send the user-chosen message + #TT tag
-------------------------------------------------
local function SendPoll()
    local chanId = GetGlobalChannelId()
    if not chanId then
        PrintInfo("You are not in channel '" .. GLOBAL_CHANNEL_NAME .. "'. Type |cffffff00/join " .. GLOBAL_CHANNEL_NAME .. "|r to use Global Sync.")
        ProbeDebug("SendPoll aborted: not in", GLOBAL_CHANNEL_NAME)
        return false
    end

    local realm = MyRealm()
    local myMax, myCount = RealmFreshness(realm)
    local baseMsg = EffectiveProbeMessage()

    -- append the shared sync tag so other clients can recognize this as a probe
    local chatText = baseMsg
    if not chatText:find(PROBE_TAG, 1, true) then
        chatText = chatText .. " " .. PROBE_TAG
    end

    ProbeDebug("SendPoll (CHAT) → chanId=", chanId, "realm=", realm, "myMax=", myMax, "myCount=", myCount, "payload=", chatText)
    SendChatMessage(chatText, "CHANNEL", nil, chanId)
    return true
end

-------------------------------------------------
-- DISCOVERY SESSION: collect HAVE replies then choose best peer
-------------------------------------------------
local probeSession = nil
local lastReplyTo = {}

local function StartDiscovery()
    if probeSession then
        return
    end

    local realm = MyRealm()
    local myMax, myCount = RealmFreshness(realm)

    probeSession = {
        realm      = realm,
        myMax      = myMax,
        myCount    = myCount,
        bestSender = nil,
        bestMax    = 0,
        bestCount  = 0,
        startedAt  = NowFrame(),
        deadline   = NowFrame() + DISCOVERY_WINDOW,
    }

    ProbeDebug("StartDiscovery:", "realm=", realm, "myMax=", myMax, "myCount=", myCount)
end

local function ConsiderHave(sender, realm, maxTs, count)
    ProbeDebug("ConsiderHave:", "sender=", sender, "realm=", realm, "maxTs=", maxTs, "count=", count)

    if not probeSession then
        return
    end
    if realm ~= probeSession.realm then
        return
    end
    if not sender or sender == "" or ShortName(sender) == MyName() then
        return
    end

    if maxTs <= probeSession.myMax then
        return
    end

    local bestMax   = probeSession.bestMax or 0
    local bestCount = probeSession.bestCount or 0

    if maxTs > bestMax or (maxTs == bestMax and count > bestCount) then
        probeSession.bestSender = sender
        probeSession.bestMax    = maxTs
        probeSession.bestCount  = count
        ProbeDebug("ConsiderHave: new best → sender=", sender, "bestMax=", maxTs, "bestCount=", count)
    end
end

local function FinishDiscovery()
    if not probeSession then
        return
    end

    local pickSender = probeSession.bestSender
    local pickCount  = probeSession.bestCount or 0
    local pickMax    = probeSession.bestMax or 0
    local myMax      = probeSession.myMax or 0

    ProbeDebug("FinishDiscovery:", "myMax=", myMax, "pickSender=", pickSender, "pickMax=", pickMax, "pickCount=", pickCount)

    probeSession = nil

    if pickSender then
        local displayName = ShortName(pickSender)
        PrintInfo(string.format("Found fresher data from |cffffff00%s|r (timers: %d). Requesting sync...", displayName, pickCount))
        ProbeDebug("FinishDiscovery: sending REQ whisper to", pickSender)

        -- reuse existing manual-sync whisper REQ protocol:
        local myName = MyName()
        local payload = "REQ|" .. myName
        SendAddonMessage(SYNC_PREFIX, payload, "WHISPER", pickSender)
    else
        PrintInfo("No fresher data found in global.")
    end
end

-------------------------------------------------
-- INBOUND: Handle POLL from chat, reply with HAVE (WHISPER ADDON)
--   chat: message contains #TT
--   addon WHISPER: HAVE|realm|maxTs|count
-------------------------------------------------
local function HandlePollChat(sender)
    ProbeDebug("HandlePollChat raw:", "sender=", sender)

    if not sender or sender == "" then
        return
    end

    local shortSender, senderRealm = sender:match("^([^%-]+)%-(.+)$")
    if not shortSender then
        shortSender = sender
        senderRealm = nil
    end

    if shortSender == MyName() then
        -- don't answer my own probe
        return
    end

    local myRealm = MyRealm()
    local myCanon = CanonicalRealmName(myRealm)
    local senderCanon = senderRealm and CanonicalRealmName(senderRealm) or myCanon

    if senderCanon ~= myCanon then
        ProbeDebug("HandlePollChat: different realm (canonical), ignoring. senderRealm=", senderRealm or "nil", "myRealm=", myRealm, "senderCanon=", senderCanon, "myCanon=", myCanon)
        return
    end

    local myMax, myCount = RealmFreshness(myRealm)
    ProbeDebug("HandlePollChat compare:", "myMax=", myMax, "myCount=", myCount)

    -- if I have no timers at all, no point replying
    if myMax <= 0 or myCount <= 0 then
        return
    end

    local now = NowFrame()
    if lastReplyTo[shortSender] and (now - lastReplyTo[shortSender]) < REPLY_THROTTLE then
        ProbeDebug("HandlePollChat: throttling reply to", shortSender)
        return
    end
    lastReplyTo[shortSender] = now

    local delay = math.random() * (JITTER_MAX - JITTER_MIN) + JITTER_MIN
    ProbeDebug("HandlePollChat: scheduling HAVE reply in", delay, "seconds to", shortSender)
    C_Timer.After(delay, function()
        local myMax2, myCount2 = RealmFreshness(myRealm) -- recalc just in case
        local reply = string.format("HAVE|%s|%d|%d", myRealm, myMax2, myCount2)
        ProbeDebug("Send HAVE →", "to=", shortSender, "payload=", reply)
        SendAddonMessage(SYNC_PREFIX, reply, "WHISPER", shortSender)
    end)
end

-------------------------------------------------
-- CHAT_MSG_CHANNEL LISTENER FOR PROBE MESSAGE
-- respond if the message contains PROBE_TAG ("#TT")
-------------------------------------------------
local pollListener = CreateFrame("Frame")
pollListener:RegisterEvent("CHAT_MSG_CHANNEL")
pollListener:SetScript("OnEvent", function(_, event, message, sender, ...)
    if not message or not message:find(PROBE_TAG, 1, true) then
        return
    end
    HandlePollChat(sender)
end)

-------------------------------------------------
-- CHAT_MSG_ADDON / HAVE HANDLING via OnAddonMessage hook
-------------------------------------------------
hooksecurefunc(TanaanTracker, "OnAddonMessage", function(prefix, message, channel, sender)
    if prefix ~= SYNC_PREFIX or not message or not sender then
        return
    end

    local head = message:match("^(%u+)|")
    if head == "HAVE" then
        -- HAVE|realm|maxTs|count
        local _, realm, sMax, sCount = strsplit("|", message)
        local maxTs = tonumber(sMax or "0") or 0
        local count = tonumber(sCount or "0") or 0
        ConsiderHave(sender, realm, maxTs, count)
    end
end)

-------------------------------------------------
-- UI: Global Sync button on main frame (bottom-left)
-------------------------------------------------
local function SecondsLeft()
    local last = TanaanTrackerDB.globalProbeLastAt or 0
    local elapsed = NowServer() - last
    if elapsed < 0 then
        elapsed = 0
    end
    local left = COOLDOWN_SECONDS - elapsed
    if left < 0 then
        left = 0
    end
    return left
end

local function FormatShort(sec)
    if not sec or sec <= 0 then
        return "Ready"
    end
    sec = math.floor(sec + 0.5)
    local m = math.floor(sec / 60)
    local s = sec % 60
    return string.format("%dm %02ds", m, s)
end

local function UpdateButtonState(btn)
    if not btn then
        return
    end
    local left = SecondsLeft()
    if left > 0 then
        btn:SetEnabled(false)
        btn:SetText("Global Sync (" .. FormatShort(left) .. ")")
    else
        btn:SetEnabled(true)
        btn:SetText("Global Sync")
    end
end

-------------------------------------------------
-- CONFIG POPUP FOR GLOBAL PROBE MESSAGE
-------------------------------------------------
local configFrame

local function SkinConfigWithElvUI(f)
    if not (ElvUI and ElvUI[1] and ElvUI[1].GetModule) then return end
    local E = ElvUI[1]
    local S = E:GetModule("Skins", true)
    if not S then return end

    if S.HandleFrame then
        S:HandleFrame(f)
    end
    if f.editBox and S.HandleEditBox then
        S:HandleEditBox(f.editBox)
    end
    if f.sendBtn and S.HandleButton then
        S:HandleButton(f.sendBtn)
    end
    if f.cancelBtn and S.HandleButton then
        S:HandleButton(f.cancelBtn)
    end
    if f.preset1 and S.HandleButton then
        S:HandleButton(f.preset1)
    end
    if f.preset2 and S.HandleButton then
        S:HandleButton(f.preset2)
    end
    if f.preset3 and S.HandleButton then
        S:HandleButton(f.preset3)
    end
end

local function OpenGlobalProbeConfig(onConfirm)
    if not configFrame then
        local f = CreateFrame("Frame", "TanaanTracker_GlobalProbeConfig", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(380, 190)
        f:SetFrameStrata("DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)

        f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.title:SetPoint("TOP", 0, -8)
        f.title:SetText("TanaanTracker - Global Sync")

        local warn = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        warn:SetPoint("TOPLEFT", 16, -28)
        warn:SetWidth(348)
        warn:SetJustifyH("LEFT")
        warn:SetText("This will send the message below (plus a small '#TT' tag) to channel '" .. GLOBAL_CHANNEL_NAME .. "' to request a sync from other TanaanTracker users on your realm.")

        local edit = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        edit:SetSize(280, 20)
        edit:SetAutoFocus(false)
        edit:SetMaxLetters(120)
        f.editBox = edit

        local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("BOTTOMLEFT", edit, "TOPLEFT", 0, 2)
        label:SetText("Message to send to /" .. GLOBAL_CHANNEL_NAME .. ":")

        -- PRESET buttons
        local function makePresetButton(text, xOffset)
            local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
            b:SetSize(100, 20)
            b:SetPoint("TOP", f, "TOP", xOffset, -110)
            b:SetText(text)
            b:SetScript("OnClick", function()
                edit:SetText(text)
                edit:SetCursorPosition(#text)
            end)
            return b
        end

        f.preset1 = makePresetButton(".", -120)
        f.preset2 = makePresetButton("hi", 0)
        f.preset3 = makePresetButton("legion when?", 120)

        -- buttons
        local sendBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        sendBtn:SetSize(100, 22)
        sendBtn:SetText("Send & Sync")
        f.sendBtn = sendBtn

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(80, 22)
        cancelBtn:SetText("Cancel")
        f.cancelBtn = cancelBtn

        SkinConfigWithElvUI(f)

        configFrame = f
    end

    local f = configFrame

    -- position: below the main addon frame if it exists, else center
    f:ClearAllPoints()
    if TanaanTracker.mainFrame then
        f:SetPoint("TOP", TanaanTracker.mainFrame, "BOTTOM", 0, -10)
    else
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end

    local defaultText = TanaanTrackerDB.globalProbeMessage or "hi"
    f.editBox:ClearAllPoints()
    f.editBox:SetPoint("TOP", f, "TOP", 0, -78)
    f.editBox:SetText(defaultText)
    f.editBox:SetCursorPosition(#defaultText)

    f:Show()
    f.editBox:SetFocus()

    f.cancelBtn:ClearAllPoints()
    f.sendBtn:ClearAllPoints()
    f.sendBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    f.cancelBtn:SetPoint("RIGHT", f.sendBtn, "LEFT", -6, 0)

    f.sendBtn:SetScript("OnClick", function()
        local text = f.editBox:GetText() or ""
        text = text:gsub("^%s+", ""):gsub("%s+$", "")
        if text == "" then
            PrintInfo("Please enter a message to send to /" .. GLOBAL_CHANNEL_NAME .. " or click Cancel.")
            return
        end

        TanaanTrackerDB.globalProbeMessage = text
        TanaanTrackerDB.globalProbeConfirmed = true

        f:Hide()

        if type(onConfirm) == "function" then
            onConfirm()
        end
    end)

    f.cancelBtn:SetScript("OnClick", function()
        f:Hide()
    end)
end

-------------------------------------------------
-- BUTTON CREATION & CLICK HANDLER
-------------------------------------------------
local function EnsureGlobalSyncButton()
    if not TanaanTracker or not TanaanTracker.mainFrame then
        return
    end
    local f = TanaanTracker.mainFrame
    if f._globalSyncBtn then
        return
    end

    local btn = CreateFrame("Button", "TanaanTracker_GlobalSyncButton", f, "UIPanelButtonTemplate")
    btn:SetSize(160, 23)
    btn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 7)
    btn:SetText("Global Sync")
    f._globalSyncBtn = btn

    --tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine("Global Sync", 1, 1, 1)
        GameTooltip:AddLine(" ", 1, 1, 1)
        GameTooltip:AddLine("• Sends a user-chosen message (plus '#TT')", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("  to /" .. GLOBAL_CHANNEL_NAME .. " to request fresher", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("  timers from other Addon users.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• 1 hour cooldown.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("• Shift-click to send last custom message", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    --elvui skin (optional)
    if ElvUI and ElvUI[1] and ElvUI[1].GetModule then
        local E = ElvUI[1]
        local S = E:GetModule("Skins", true)
        if S and S.HandleButton then
            S:HandleButton(btn)
        end
    end

    -- cooldown ticker
    local ticker = CreateFrame("Frame", nil, btn)
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc >= 1.0 then
            acc = 0
            UpdateButtonState(btn)
        end
    end)

    btn:SetScript("OnShow", function()
        UpdateButtonState(btn)
    end)

        btn:SetScript("OnClick", function()
        local left = SecondsLeft()
        if left > 0 then
            UpdateButtonState(btn)
            return
        end

        local function DoProbe()
            if not SendPoll() then
                return
            end

            -- only stamp cooldown if we actually managed to broadcast the probe
            TanaanTrackerDB.globalProbeLastAt = NowServer()
            UpdateButtonState(btn)

            PrintInfo("Probing 'global' for fresher timers...")
            StartDiscovery()
            C_Timer.After(DISCOVERY_WINDOW, FinishDiscovery)
        end

        -- shift+click: quick-send using last confirmed message, no popup
        if IsShiftKeyDown() then
            if not TanaanTrackerDB.globalProbeConfirmed then
                -- if user never confirmed before, force config once
                OpenGlobalProbeConfig(DoProbe)
            else
                DoProbe()
            end
            return
        end

        -- normal click: toggle the config window
        if configFrame and configFrame:IsShown() then
            -- window is open -> close it
            configFrame:Hide()
        else
            -- window is closed -> open it and hook DoProbe
            OpenGlobalProbeConfig(DoProbe)
        end
    end)


    -- initialize state immediately
    UpdateButtonState(btn)
end

-------------------------------------------------
-- Hook into CreateMainFrame + login to ensure button exists
-------------------------------------------------
if TanaanTracker and TanaanTracker.CreateMainFrame then
    hooksecurefunc(TanaanTracker, "CreateMainFrame", function()
        C_Timer.After(0, EnsureGlobalSyncButton)
    end)
end

local probeInitFrame = CreateFrame("Frame")
probeInitFrame:RegisterEvent("PLAYER_LOGIN")
probeInitFrame:SetScript("OnEvent", function()
    if TanaanTrackerDB and TanaanTrackerDB.globalProbeLastAt == nil then
        TanaanTrackerDB.globalProbeLastAt = 0
    end
    if TanaanTrackerDB and TanaanTrackerDB.globalProbeMessage == nil then
        TanaanTrackerDB.globalProbeMessage = "hi"
    end
    C_Timer.After(3, EnsureGlobalSyncButton)
end)

-------------------------------------------------
-- DEBUG
-------------------------------------------------
function TanaanTracker.DebugGlobalProbe()
    if not probeSession then
        PrintInfo("Global probe: no active session.")
        return
    end
    PrintInfo(string.format(
        "Probe session → realm=%s, myMax=%d, myCount=%d, bestSender=%s, bestMax=%d, bestCount=%d",
        probeSession.realm or "?", probeSession.myMax or 0, probeSession.myCount or 0,
        probeSession.bestSender or "none", probeSession.bestMax or 0, probeSession.bestCount or 0
    ))
end
