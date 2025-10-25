-- TanaanTracker: TomTomSupport.lua
TanaanTracker = TanaanTracker or {}

-- Create and wire TomTom buttons for a row
function TanaanTracker.AttachTomTomButtons(row, rareName, anchorTo)
    local tomSet = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    tomSet:SetSize(24, 24)
    tomSet:SetPoint("LEFT", anchorTo, "RIGHT", 6, -8)
    tomSet:SetText(">")

    local tomClear = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    tomClear:SetSize(24, 24)
    tomClear:SetPoint("LEFT", tomSet, "RIGHT", 4, 0)
    tomClear:SetText("X")

    -- button hover glow
    tomSet:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")
    tomClear:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight")

    -------------------------------------------------------------
    -- ELVUI SKIN SUPPORT (for TomTom buttons)
    -------------------------------------------------------------
    if ElvUI and ElvUI[1] and ElvUI[1].GetModule then
        local E = ElvUI[1]
        local S = E:GetModule("Skins", true)
        if S and S.HandleButton then
            S:HandleButton(tomSet, true)
            S:HandleButton(tomClear, true)

            -- Optional: color accent to match TanaanTracker theme (soft blue)
            local r, g, b = 0.4, 0.7, 1.0
            tomSet:SetBackdropBorderColor(r, g, b, 0.8)
            tomClear:SetBackdropBorderColor(r, g, b, 0.8)
        end
    end

    -------------------------------------------------------------
    -- SET: behave exactly like typing /way Tanaan Jungle <x> <y> <title>
    -------------------------------------------------------------
    tomSet:SetScript("OnClick", function()
        if not TomTom then print("TomTom not found."); return end
        local info = TanaanTracker.rares[rareName]
        if not info or not info.coords then
            print("Missing coordinates for " .. rareName); return
        end
        local x, y = tonumber(info.coords[1]), tonumber(info.coords[2])
        if not x or not y then print("Invalid coordinates for " .. rareName); return end

        local zone = "Tanaan Jungle"
        local title = rareName
        TanaanTracker:RunSlash(string.format("/way %s %.2f %.2f %s", zone, x, y, title))
        print(string.format("TomTom waypoint set for %s (%.2f, %.2f)", rareName, x, y))
    end)

    tomSet:SetScript("OnEnter", function()
        GameTooltip:SetOwner(tomSet, "ANCHOR_LEFT")
        GameTooltip:AddLine("Set TomTom waypoint")
        GameTooltip:Show()
    end)
    tomSet:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -------------------------------------------------------------
    -- CLEAR: remove all active TomTom waypoints + arrow
    -------------------------------------------------------------
    tomClear:SetScript("OnClick", function()
        if not TomTom then print("TomTom not found."); return end
        if TomTom.waypoints then
            for _, wpList in pairs(TomTom.waypoints) do
                for _, waypoint in pairs(wpList) do
                    TomTom:RemoveWaypoint(waypoint)
                end
            end
            if TomTom.HideCrazyArrow then TomTom:HideCrazyArrow() end
            print("TomTom waypoints cleared.")
        else
            if TomTom.HideCrazyArrow then
                TomTom:HideCrazyArrow()
                print("TomTom arrow hidden.")
            else
                TanaanTracker:RunSlash("/cway")
                print("TomTom arrow cleared (fallback).")
            end
        end
    end)

    tomClear:SetScript("OnEnter", function()
        GameTooltip:SetOwner(tomClear, "ANCHOR_LEFT")
        GameTooltip:AddLine("Clear TomTom waypoint")
        GameTooltip:Show()
    end)
    tomClear:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
