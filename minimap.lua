MyLoot = MyLoot or {}

-- =========================
-- MINIMAP BUTTON
-- =========================

local BUTTON_SIZE = 36
local RADIUS      = 80

local function UpdatePosition(btn)
  local angle = MyLootDB.minimapAngle or 225
  local rad   = math.rad(angle)
  btn:SetPoint("CENTER", Minimap, "CENTER", RADIUS * math.cos(rad), RADIUS * math.sin(rad))
end

local function CreateMinimapButton()
  local btn = CreateFrame("Button", "WRTMinimapButton", Minimap)
  btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)

  -- Icon (das Logo ist bereits rund → keine Maske nötig)
  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface/AddOns/WeltenWandler_Raid_Tool/textures/minimap_icon.tga")
  icon:SetAllPoints(btn)

  -- Highlight beim Hovern
  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")
  hl:SetSize(BUTTON_SIZE + 8, BUTTON_SIZE + 8)
  hl:SetPoint("CENTER", 0, 0)
  hl:SetBlendMode("ADD")

  -- =========================
  -- KLICK: Fenster toggeln
  -- =========================
  btn:SetScript("OnClick", function(_, mouseButton)
    if mouseButton == "LeftButton" then
      local ui = MyLoot.UI
      ui:SetShown(not ui:IsShown())

      if ui:IsShown() then
        C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "REQUEST_SYNC", "RAID")
        if MyLootDB.role == "raidlead" then
          MyLoot.BroadcastFullState()
        end
      end

      MyLoot.Render()
    end
  end)

  -- =========================
  -- TOOLTIP
  -- =========================
  btn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("WeltenWandler Raid Tool", 1, 0.82, 0)
    GameTooltip:AddLine("Linksklick: Fenster öffnen/schließen", 0.8, 0.8, 0.8)
    GameTooltip:AddLine("Ziehen: Position anpassen", 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)

  btn:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  -- =========================
  -- DRAGGING
  -- =========================
  btn:RegisterForDrag("LeftButton")

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale  = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale

      local angle = math.deg(math.atan2(cy - my, cx - mx))
      MyLootDB.minimapAngle = angle
      UpdatePosition(self)
    end)
  end)

  btn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
  end)

  UpdatePosition(btn)
  return btn
end

-- =========================
-- INIT (nach PLAYER_LOGIN)
-- =========================
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  MyLootDB.minimapAngle = MyLootDB.minimapAngle or 225
  MyLoot.minimapButton = CreateMinimapButton()
end)
