-- TanaanTracker: Minimap Button
TanaanTracker = TanaanTracker or {}

-------------------------------------------------
-- SAVED POSITION
-------------------------------------------------
TanaanTrackerMiniDB = TanaanTrackerMiniDB or { x = 0, y = 0 }

-------------------------------------------------
-- BUTTON FRAME
-------------------------------------------------
local btn = CreateFrame("Button", "TanaanTrackerMinimapButton", Minimap)
btn:SetWidth(33)
btn:SetHeight(33)
btn:SetFrameStrata("MEDIUM")
btn:SetFrameLevel(8)
btn:SetMovable(true)
btn:RegisterForDrag("LeftButton")
btn:SetUserPlaced(true)

-------------------------------------------------
-- ICON TEXTURE
-------------------------------------------------
local icon = btn:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\AddOns\\TanaanTracker\\Icon.tga")
icon:SetTexCoord(0, 1, 0, 1)
icon:SetWidth(20)
icon:SetHeight(20)
icon:SetPoint("CENTER", btn, "CENTER", 0, 0)

-------------------------------------------------
-- GRAY / SILVER BORDER (gray as fug boy)
-------------------------------------------------
local border = btn:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetWidth(56)
border:SetHeight(56)
border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
border:SetDesaturated(true)          -- removes the ugly gold
border:SetVertexColor(0.8, 0.8, 0.8) -- gray man be graying

-------------------------------------------------
-- HIGHLIGHT EFFECT
-------------------------------------------------
btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
local hl = btn:GetHighlightTexture()
hl:ClearAllPoints()
hl:SetPoint("CENTER", btn, "CENTER", 0, 0)
hl:SetWidth(36)
hl:SetHeight(36)

-------------------------------------------------
-- DRAGGING (SHIFT + LEFT BUTTON)
-------------------------------------------------
btn:SetScript("OnDragStart", function(self)
    if IsShiftKeyDown() then
        self:StartMoving()
    end
end)

btn:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    TanaanTrackerMiniDB.x, TanaanTrackerMiniDB.y = x, y
end)

-------------------------------------------------
-- TOOLTIP + CLICK
-------------------------------------------------
btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("|cff00ff00TanaanTracker|r")
    GameTooltip:AddLine("Shift + Left-Drag to move", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Left-click: Toggle main window", 1, 1, 1)
    GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

btn:SetScript("OnClick", function()
    -- try to toggle main frame safely
    if TanaanTracker.ToggleMainFrame and type(TanaanTracker.ToggleMainFrame) == "function" then
        TanaanTracker.ToggleMainFrame()
    elseif TanaanTracker.mainFrame then
        -- fallback toggle if no dedicated function exists
        if TanaanTracker.mainFrame:IsShown() then
            TanaanTracker.mainFrame:Hide()
        else
            TanaanTracker.mainFrame:Show()
        end
    else
        print("|cff00ff00[TanaanTracker]|r UI toggle not found.")
    end
end)

-------------------------------------------------
-- POSITION RESTORE
-------------------------------------------------
local function RestorePosition()
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", Minimap, "BOTTOMLEFT",
        TanaanTrackerMiniDB.x or 0,
        TanaanTrackerMiniDB.y or 0)
end
RestorePosition()

-------------------------------------------------
-- PUBLIC CREATION CALL
-------------------------------------------------
function TanaanTracker.CreateMinimapButton()
    btn:Show()
end
