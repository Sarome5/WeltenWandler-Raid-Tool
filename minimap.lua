MyLoot = MyLoot or {}

-- =========================
-- MINIMAP BUTTON
-- =========================

local BUTTON_SIZE = 32
local ICON_SIZE   = 20
local RADIUS      = 80

local function UpdatePosition(btn)
  local x = MyLootDB.minimapX or -56
  local y = MyLootDB.minimapY or -56
  btn:ClearAllPoints()
  btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function CreateMinimapButton()
  local btn = CreateFrame("Button", "WRTMinimapButton", Minimap)
  btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
  btn:SetFrameStrata("MEDIUM")
  btn:SetFrameLevel(8)
  btn:SetDontSavePosition(true)

  -- Icon (zentriert, kleiner als Button → Ecken bleiben frei)
  local icon = btn:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface/AddOns/WeltenWandler_Raid_Tool/textures/minimap_icon.tga")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("CENTER", 0, 0)
  -- Kreismaske damit Ecken der TGA ausgeblendet werden
  icon:SetMask("Interface/CHARACTERFRAME/TempPortraitMask")

  -- Rand-Ring (wie MRT: überdeckt Ecken, gibt runden Look)
  local border = btn:CreateTexture(nil, "ARTWORK")
  border:SetTexture("Interface/Minimap/MiniMap-TrackingBorder")
  border:SetTexCoord(0, 0.6, 0, 0.6)
  border:SetAllPoints()

  -- Highlight beim Hovern (WoW-API wie MRT)
  btn:SetHighlightTexture("Interface/Minimap/UI-Minimap-ZoomButton-Highlight")

  -- =========================
  -- KLICK: Fenster toggeln
  -- =========================
  btn:RegisterForClicks("anyUp")
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
  -- DRAGGING (X/Y wie MRT)
  -- =========================
  btn:RegisterForDrag("LeftButton")

  btn:SetScript("OnDragStart", function(self)
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local cx, cy = GetCursorPosition()
      local scale  = Minimap:GetEffectiveScale()
      cx, cy = cx / scale, cy / scale

      local dx = cx - mx
      local dy = cy - my

      -- Auf Minimap-Rand einrasten (Radius begrenzen)
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist > 0 then
        local clamped = math.min(dist, RADIUS)
        dx = dx / dist * clamped
        dy = dy / dist * clamped
      end

      MyLootDB.minimapX = dx
      MyLootDB.minimapY = dy
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
  -- Alte minimapAngle-Daten migrieren
  if MyLootDB.minimapAngle and not MyLootDB.minimapX then
    local rad = math.rad(MyLootDB.minimapAngle)
    MyLootDB.minimapX = RADIUS * math.cos(rad)
    MyLootDB.minimapY = RADIUS * math.sin(rad)
    MyLootDB.minimapAngle = nil
  end

  MyLoot.minimapButton = CreateMinimapButton()
end)
