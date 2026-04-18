MyLoot = MyLoot or {}

-- =========================
-- VERSIONS-FENSTER
-- =========================
-- Zeigt alle bekannten Addon-Nutzer mit ihrer Version.
-- Öffnen: /wrtversions
-- Aktualisieren-Button sendet HELLO_REQUEST → alle antworten mit ihrer Version.

function MyLoot.ShowVersionWindow()
  -- Fenster nur einmal erstellen, danach wiederverwenden
  if not MyLoot._versionWindow then
    MyLoot._buildVersionWindow()
  end
  MyLoot._versionWindow:Show()
  MyLoot.RefreshVersionWindow()
end

function MyLoot._buildVersionWindow()
  local win = CreateFrame("Frame", "MyLootVersionWindow", UIParent, "BackdropTemplate")
  MyLoot._versionWindow = win

  win:SetSize(300, 380)
  win:SetPoint("CENTER")
  win:SetMovable(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetFrameStrata("DIALOG")
  win:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 8,
  })
  win:SetBackdropColor(0, 0, 0, 0.92)
  table.insert(UISpecialFrames, "MyLootVersionWindow")

  -- Titel
  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -12)
  title:SetText("WRT – Addon Nutzer")

  -- Schließen-Button
  local closeBtn = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  closeBtn:SetSize(26, 26)
  closeBtn:SetPoint("TOPRIGHT", -4, -4)
  closeBtn:SetScript("OnClick", function() win:Hide() end)

  -- Trennlinie unter Titel
  local divider = win:CreateTexture(nil, "BACKGROUND")
  divider:SetColorTexture(1, 1, 1, 0.15)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", 10, -30)
  divider:SetPoint("TOPRIGHT", -10, -30)

  -- Spalten-Header
  local colName = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  colName:SetPoint("TOPLEFT", 14, -40)
  colName:SetText("|cffaaaaaa Spieler|r")

  local colVer = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  colVer:SetPoint("TOPLEFT", 190, -40)
  colVer:SetText("|cffaaaaaa Version|r")

  -- Scroll-Bereich für Spielerliste
  local sf = CreateFrame("ScrollFrame", nil, win)
  sf:SetPoint("TOPLEFT", 10, -58)
  sf:SetPoint("BOTTOMRIGHT", -10, 46)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(_, delta)
    sf:SetVerticalScroll(math.max(0, sf:GetVerticalScroll() - delta * 20))
  end)
  win._scrollFrame = sf

  local content = CreateFrame("Frame", nil, sf)
  content:SetWidth(280)
  content:SetHeight(1)
  sf:SetScrollChild(content)
  win._content = content

  -- Trennlinie über Button
  local divider2 = win:CreateTexture(nil, "BACKGROUND")
  divider2:SetColorTexture(1, 1, 1, 0.15)
  divider2:SetHeight(1)
  divider2:SetPoint("BOTTOMLEFT", 10, 38)
  divider2:SetPoint("BOTTOMRIGHT", -10, 38)

  -- Aktualisieren-Button
  local refreshBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  refreshBtn:SetSize(140, 24)
  refreshBtn:SetPoint("BOTTOM", 0, 10)
  refreshBtn:SetText("Aktualisieren")
  refreshBtn:SetScript("OnClick", function()
    -- Liste leeren (nur eigenen Eintrag behalten)
    local self = UnitName("player")
    MyLoot._addonUsers = {}
    if self then MyLoot._addonUsers[self] = MyLoot.VERSION or "?" end

    -- Alle anderen anfragen + eigene Version senden
    local channel = IsInRaid() and "RAID" or (IsInGroup() and "PARTY" or nil)
    if channel then
      C_ChatInfo.SendAddonMessage("MYLOOT_SYNC", "HELLO_REQUEST", channel)
    end
    MyLoot.BroadcastHello()

    -- Nach 3s aktualisieren (Zeit für Antworten)
    C_Timer.After(3, function()
      if MyLoot._versionWindow and MyLoot._versionWindow:IsShown() then
        MyLoot.RefreshVersionWindow()
      end
    end)
    MyLoot.RefreshVersionWindow()
  end)
end

function MyLoot.RefreshVersionWindow()
  local win = MyLoot._versionWindow
  if not win or not win:IsShown() then return end

  local content = win._content

  -- Bestehende Zeilen entfernen
  for _, c in ipairs({ content:GetChildren() }) do
    c:Hide()
    c:ClearAllPoints()
  end

  -- Neueste bekannte Version ermitteln (für Farbcodierung)
  local newestVer = MyLoot.VERSION or "0"
  for _, ver in pairs(MyLoot._addonUsers or {}) do
    if MyLoot.IsVersionNewer and MyLoot.IsVersionNewer(ver, newestVer) then
      newestVer = ver
    end
  end

  -- Spieler alphabetisch sortieren
  local sorted = {}
  for name, ver in pairs(MyLoot._addonUsers or {}) do
    table.insert(sorted, { name = name, ver = ver })
  end
  table.sort(sorted, function(a, b) return a.name < b.name end)

  local y = 0

  if #sorted == 0 then
    local empty = CreateFrame("Frame", nil, content)
    empty:SetSize(280, 22)
    empty:SetPoint("TOPLEFT", 0, y)
    local txt = empty:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    txt:SetAllPoints()
    txt:SetJustifyH("CENTER")
    txt:SetText("Keine Addon-Nutzer bekannt")
    y = y - 22
  else
    for _, entry in ipairs(sorted) do
      local row = CreateFrame("Frame", nil, content)
      row:SetSize(280, 22)
      row:SetPoint("TOPLEFT", 0, y)

      -- Spielername
      local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      nameText:SetPoint("LEFT", 5, 0)
      nameText:SetWidth(170)
      nameText:SetJustifyH("LEFT")
      nameText:SetWordWrap(false)
      nameText:SetText(entry.name)

      -- Version mit Farbcodierung
      --   Grün  = aktuellste bekannte Version
      --   Rot   = veraltet
      local color
      if entry.ver == newestVer then
        color = "|cff00cc44"  -- grün
      else
        color = "|cffff4444"  -- rot
      end

      local verText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      verText:SetPoint("LEFT", 185, 0)
      verText:SetText(color .. "v" .. entry.ver .. "|r")

      y = y - 22
    end
  end

  content:SetHeight(math.max(math.abs(y), 1))
end
