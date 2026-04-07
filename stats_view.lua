MyLoot = MyLoot or {}

-- Zustand der Stats-Ansicht (persistent innerhalb Session)
local statsState = {
  view = "history",  -- "dropchance" | "player" | "history"
  spec = "ms",       -- "ms" | "os" | "all"  (nur für "player")
}

-- =========================
-- HILFSFUNKTIONEN
-- =========================
local function GetClassColor(playerName)
  local classColor = MyLootDB.knownClasses and MyLootDB.knownClasses[playerName]
  if classColor and RAID_CLASS_COLORS[classColor] then
    local c = RAID_CLASS_COLORS[classColor]
    return c.r, c.g, c.b, c.colorStr
  end
  return 1, 1, 1, "ffffffff"
end

-- =========================
-- RENDER STATS VIEW
-- =========================
function MyLoot.RenderStatsView()
  local ui   = MyLoot.UI
  local data = WRT_StatsData

  -- ScrollFrame aufbauen / wiederverwenden
  if not ui.statsScrollFrame then
    local sf = CreateFrame("ScrollFrame", nil, ui.content)
    sf:SetPoint("TOPLEFT",  ui.content, "TOPLEFT",   0, -90)
    sf:SetPoint("BOTTOMRIGHT", ui.content, "BOTTOMRIGHT", 0, 0)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
      local cur = self:GetVerticalScroll()
      self:SetVerticalScroll(math.max(0, cur - delta * 20))
    end)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(ui.content:GetWidth(), 1)
    sf:SetScrollChild(child)

    ui.statsScrollFrame = sf
    ui.statsScrollChild = child
  end

  ui.statsScrollFrame:Show()
  ui.statsScrollFrame:SetVerticalScroll(0)

  -- ScrollChild komplett neu erstellen (verhindert Stack Overflow durch akkumulierte Regions)
  if ui.statsScrollChild then
    ui.statsScrollChild:Hide()
    ui.statsScrollChild:SetParent(nil)
  end
  local child = CreateFrame("Frame", nil, ui.statsScrollFrame)
  child:SetSize(ui.content:GetWidth() or 660, 1)
  ui.statsScrollFrame:SetScrollChild(child)
  ui.statsScrollChild = child

  -- =========================
  -- TAB-LEISTE (topPanel)
  -- =========================
  -- Alte Tab-Buttons aufräumen
  if ui.statsTabButtons then
    for _, b in ipairs(ui.statsTabButtons) do b:Hide() end
  end
  ui.statsTabButtons = {}

  local tabs = {
    { key = "dropchance", label = "Dropchance" },
    { key = "player",     label = "Loot pro Spieler" },
    { key = "history",    label = "Loothistorie" },
  }

  local tabX = 0
  for _, tab in ipairs(tabs) do
    local btn = CreateFrame("Button", nil, ui.topPanel)
    btn:SetSize(130, 28)
    btn:SetPoint("BOTTOMLEFT", ui.topPanel, "BOTTOMLEFT", tabX + 10, 6)

    local isActive = (statsState.view == tab.key)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(isActive and 0.15 or 0.08, isActive and 0.12 or 0.08, 0, isActive and 0.9 or 0.5)

    local bar = btn:CreateTexture(nil, "BORDER")
    bar:SetPoint("BOTTOMLEFT", 0, 0)
    bar:SetPoint("BOTTOMRIGHT", 0, 0)
    bar:SetHeight(2)
    bar:SetColorTexture(1, 0.82, 0, isActive and 1 or 0)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints()
    lbl:SetJustifyH("CENTER")
    lbl:SetTextColor(isActive and 1 or 0.7, isActive and 0.82 or 0.7, isActive and 0 or 0.7)
    lbl:SetText(tab.label)

    local key = tab.key
    btn:SetScript("OnClick", function()
      statsState.view = key
      MyLoot.Render()
    end)

    table.insert(ui.statsTabButtons, btn)
    tabX = tabX + 134
  end

  -- Spec-Filter (nur bei "player")
  if ui.statsSpecButtons then
    for _, b in ipairs(ui.statsSpecButtons) do b:Hide() end
  end
  ui.statsSpecButtons = {}

  if statsState.view == "player" then
    local specs = {
      { key = "ms",  label = "Main-Spec" },
      { key = "os",  label = "Off-Spec"  },
      { key = "all", label = "Overall"   },
    }
    local sx = 415
    for _, sp in ipairs(specs) do
      local sbtn = CreateFrame("Button", nil, ui.topPanel)
      sbtn:SetSize(90, 22)
      sbtn:SetPoint("BOTTOMLEFT", ui.topPanel, "BOTTOMLEFT", sx, 8)

      local isActive = (statsState.spec == sp.key)
      local sbg = sbtn:CreateTexture(nil, "BACKGROUND")
      sbg:SetAllPoints()
      sbg:SetColorTexture(isActive and 0.2 or 0.08, isActive and 0.18 or 0.08, 0, isActive and 0.9 or 0.4)

      local slbl = sbtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      slbl:SetAllPoints()
      slbl:SetJustifyH("CENTER")
      slbl:SetTextColor(isActive and 1 or 0.6, isActive and 0.82 or 0.6, isActive and 0 or 0.6)
      slbl:SetText(sp.label)

      local skey = sp.key
      sbtn:SetScript("OnClick", function()
        statsState.spec = skey
        MyLoot.Render()
      end)

      table.insert(ui.statsSpecButtons, sbtn)
      sx = sx + 94
    end
  end

  -- Keine Daten
  if not data or data.version == 0 then
    local hint = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", child, "TOP", 0, -30)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Keine Statistik-Daten vorhanden.\nBitte WeltenWandler Companion App einrichten.")
    child:SetHeight(80)
    return
  end

  -- =========================
  -- INHALT je nach Ansicht
  -- =========================
  if statsState.view == "dropchance" then
    MyLoot.RenderStatsDropchance(child, data)
  elseif statsState.view == "player" then
    MyLoot.RenderStatsPlayer(child, data, statsState.spec)
  else
    MyLoot.RenderStatsHistory(child, data)
  end
end


-- =========================
-- DROPCHANCE
-- =========================
function MyLoot.RenderStatsDropchance(child, data)
  local y = -10
  local W = child:GetWidth() or 660

  if not data.dropchance or #data.dropchance == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Dropchance-Daten vorhanden.")
    child:SetHeight(40)
    return
  end

  for _, boss in ipairs(data.dropchance) do
    -- Boss-Header
    local bh = child:CreateTexture(nil, "BACKGROUND")
    bh:SetPoint("TOPLEFT",  0, y)
    bh:SetPoint("TOPRIGHT", 0, y)
    bh:SetHeight(22)
    bh:SetColorTexture(0.12, 0.10, 0.02, 1)

    local bLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bLabel:SetPoint("TOPLEFT", 10, y - 3)
    bLabel:SetTextColor(1, 0.82, 0)
    bLabel:SetText(boss.bossName or "Boss")
    y = y - 22

    -- Spalten-Header
    local function H(text, xOff, justify)
      local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f:SetPoint("TOPLEFT", xOff, y)
      f:SetTextColor(0.6, 0.6, 0.6)
      f:SetJustifyH(justify or "LEFT")
      f:SetText(text)
    end
    H("Item",     10)
    H("Drops",    W - 200, "RIGHT")
    H("Kills",    W - 140, "RIGHT")
    H("Chance",   W -  70, "RIGHT")
    y = y - 18

    if boss.items then
      for i, item in ipairs(boss.items) do
        if i % 2 == 0 then
          local stripe = child:CreateTexture(nil, "BACKGROUND")
          stripe:SetPoint("TOPLEFT",  0, y)
          stripe:SetPoint("TOPRIGHT", 0, y)
          stripe:SetHeight(20)
          stripe:SetColorTexture(1, 1, 1, 0.03)
        end

        local iName = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iName:SetPoint("TOPLEFT", 10, y - 2)
        iName:SetTextColor(0.8, 0.8, 1)
        iName:SetText(item.itemName or ("Item " .. (item.itemID or "?")))

        local function RightCol(text, xOff)
          local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          f:SetPoint("TOPLEFT", xOff, y - 2)
          f:SetJustifyH("RIGHT")
          f:SetWidth(60)
          f:SetText(tostring(text or "—"))
        end
        RightCol(item.drops,  W - 220)
        RightCol(item.kills,  W - 160)

        local chanceColor = { 1, 1, 1 }
        local chance = item.chance or 0
        if chance >= 70 then chanceColor = { 0.2, 1, 0.2 }
        elseif chance >= 40 then chanceColor = { 1, 0.82, 0 }
        else chanceColor = { 1, 0.5, 0.5 } end

        local cf = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cf:SetPoint("TOPLEFT", W - 100, y - 2)
        cf:SetJustifyH("RIGHT")
        cf:SetWidth(60)
        cf:SetTextColor(unpack(chanceColor))
        cf:SetText(string.format("%.1f%%", chance))

        y = y - 20
      end
    end
    y = y - 8
  end

  child:SetHeight(math.abs(y) + 20)
end


-- =========================
-- LOOT PRO SPIELER
-- =========================
function MyLoot.RenderStatsPlayer(child, data, spec)
  local y = -10
  local W = child:GetWidth() or 660

  if not data.playerStats or #data.playerStats == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Spieler-Daten vorhanden.")
    child:SetHeight(40)
    return
  end

  -- Header
  local function H(text, xOff)
    local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", xOff, y)
    f:SetTextColor(1, 0.82, 0)
    f:SetText(text)
  end
  H("Charakter",         10)
  H("Loot",             200)
  H("Raids",            260)
  H("Ø / Raid",         340)
  H("Ø / teilgen.",     430)
  H("Anteil",           520)
  y = y - 4

  local hline = child:CreateTexture(nil, "ARTWORK")
  hline:SetColorTexture(1, 0.82, 0, 0.3)
  hline:SetPoint("TOPLEFT",  0, y)
  hline:SetPoint("TOPRIGHT", 0, y)
  hline:SetHeight(1)
  y = y - 18

  for i, ps in ipairs(data.playerStats) do
    -- Loot-Wert je nach Spec-Filter
    local lootVal
    if spec == "ms" then
      lootVal = ps.lootMS or 0
    elseif spec == "os" then
      lootVal = ps.lootOS or 0
    else
      lootVal = ps.lootTotal or 0
    end

    if i % 2 == 0 then
      local stripe = child:CreateTexture(nil, "BACKGROUND")
      stripe:SetPoint("TOPLEFT",  0, y)
      stripe:SetPoint("TOPRIGHT", 0, y)
      stripe:SetHeight(20)
      stripe:SetColorTexture(1, 1, 1, 0.03)
    end

    local r, g, b = GetClassColor(ps.playerName)

    local function Col(text, xOff, cr, cg, cb)
      local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f:SetPoint("TOPLEFT", xOff, y - 2)
      f:SetTextColor(cr or 1, cg or 1, cb or 1)
      f:SetText(tostring(text or "—"))
    end

    Col(ps.playerName or "?",                               10,  r, g, b)
    Col(lootVal,                                           200)
    Col(string.format("%d (%.0f%%)",
      ps.raids or 0,
      ps.raidsTotal and ps.raids and (ps.raids / ps.raidsTotal * 100) or 0),
                                                           260,  0.7, 0.7, 0.7)
    Col(string.format("%.2f", ps.avgPerRaid   or 0),       340)
    Col(string.format("%.2f", ps.avgAttended  or 0),       430)

    -- Prozent-Balken
    local pct = ps.percentage or 0
    local barW = math.max(2, math.min(120, pct * 1.2))
    local bar = child:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 520, y - 4)
    bar:SetSize(barW, 12)
    bar:SetColorTexture(0.2, 0.6, 0.2, 0.8)

    local pctLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctLabel:SetPoint("TOPLEFT", 648, y - 2)
    pctLabel:SetTextColor(0.7, 0.7, 0.7)
    pctLabel:SetText(string.format("%.1f%%", pct))

    y = y - 20
  end

  child:SetHeight(math.abs(y) + 20)
end


-- =========================
-- LOOTHISTORIE
-- =========================
function MyLoot.RenderStatsHistory(child, data)
  local y = -10
  local W = child:GetWidth() or 660

  if not data.lootHistory or #data.lootHistory == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Loothistorie vorhanden.")
    child:SetHeight(40)
    return
  end

  local diffColors = {
    ["Normal"]    = { 0.3, 0.9, 0.3 },
    ["Heroisch"]  = { 0.2, 0.5, 1.0 },
    ["Mythisch"]  = { 0.6, 0.2, 1.0 },
  }

  local typeColors = {
    ["MS"] = { 0.2, 0.8, 1.0 },
    ["OS"] = { 0.5, 0.5, 0.5 },
  }

  for _, raid in ipairs(data.lootHistory) do
    -- Raid-Header-Zeile
    local rh = child:CreateTexture(nil, "BACKGROUND")
    rh:SetPoint("TOPLEFT",  0, y)
    rh:SetPoint("TOPRIGHT", 0, y)
    rh:SetHeight(22)
    rh:SetColorTexture(0.10, 0.08, 0.02, 1)

    local rName = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rName:SetPoint("TOPLEFT", 10, y - 3)
    rName:SetTextColor(1, 0.82, 0)
    rName:SetText(raid.raidName or "Raid")

    if raid.date then
      local rDate = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      rDate:SetPoint("TOPLEFT", 360, y - 3)
      rDate:SetTextColor(0.7, 0.7, 0.7)
      rDate:SetText(raid.date)
    end

    -- Schwierigkeits-Badge
    if raid.difficulty then
      local dc = diffColors[raid.difficulty] or { 0.7, 0.7, 0.7 }
      local badge = child:CreateTexture(nil, "ARTWORK")
      badge:SetPoint("TOPLEFT", W - 100, y - 1)
      badge:SetSize(80, 16)
      badge:SetColorTexture(dc[1] * 0.3, dc[2] * 0.3, dc[3] * 0.3, 0.9)

      local dLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      dLabel:SetPoint("TOPLEFT", W - 100, y - 3)
      dLabel:SetWidth(80)
      dLabel:SetJustifyH("CENTER")
      dLabel:SetTextColor(unpack(dc))
      dLabel:SetText(raid.difficulty)
    end

    y = y - 22

    -- Einträge des Raids
    if raid.entries and #raid.entries > 0 then
      -- Spalten-Header
      local function H(text, xOff)
        local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", xOff, y - 2)
        f:SetTextColor(0.5, 0.5, 0.5)
        f:SetText(text)
      end
      H("Zeitpunkt",  10)
      H("Boss",       100)
      H("Item",       260)
      H("Charakter",  520)
      H("Typ",        620)
      y = y - 18

      for i, entry in ipairs(raid.entries) do
        if i % 2 == 0 then
          local stripe = child:CreateTexture(nil, "BACKGROUND")
          stripe:SetPoint("TOPLEFT",  0, y)
          stripe:SetPoint("TOPRIGHT", 0, y)
          stripe:SetHeight(18)
          stripe:SetColorTexture(1, 1, 1, 0.03)
        end

        local timeStr = entry.timestamp and date("%d.%m. %H:%M", entry.timestamp) or ""
        local r, g, b = GetClassColor(entry.player)
        local tc = typeColors[entry.lootType] or { 0.7, 0.7, 0.7 }

        local function Col(text, xOff, cr, cg, cb)
          local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          f:SetPoint("TOPLEFT", xOff, y - 2)
          f:SetTextColor(cr or 0.8, cg or 0.8, cb or 0.8)
          f:SetText(tostring(text or ""))
        end

        Col(timeStr,                          10,  0.5, 0.5, 0.5)
        Col(entry.boss    or "",             100)
        Col(entry.itemName or "",            260,  0.8, 0.8, 1.0)
        Col(entry.player  or "",             520,  r, g, b)

        -- Typ-Badge
        local typeBg = child:CreateTexture(nil, "ARTWORK")
        typeBg:SetPoint("TOPLEFT", 615, y - 1)
        typeBg:SetSize(42, 14)
        typeBg:SetColorTexture(tc[1] * 0.3, tc[2] * 0.3, tc[3] * 0.3, 0.9)

        local typeLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        typeLabel:SetPoint("TOPLEFT", 615, y - 2)
        typeLabel:SetWidth(42)
        typeLabel:SetJustifyH("CENTER")
        typeLabel:SetTextColor(unpack(tc))
        local typeDisplay = entry.lootType == "MS" and "Main" or (entry.lootType == "OS" and "Off" or (entry.lootType or ""))
        typeLabel:SetText(typeDisplay)

        y = y - 18
      end
    end
    y = y - 10
  end

  child:SetHeight(math.abs(y) + 20)
end
