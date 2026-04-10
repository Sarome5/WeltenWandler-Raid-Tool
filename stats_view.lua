MyLoot = MyLoot or {}

-- Zustand der Stats-Ansicht (persistent innerhalb Session)
local statsState = {
  view    = "history",   -- "history" | "player" | "dropchance"
  diff    = "all",       -- "all" | "normal" | "heroic" | "mythic"
  scope   = "all",       -- "all" | "ms" | "os"  (bei dropchance ignoriert)
  patchId = nil,         -- nil = alle Patches, sonst Patch-ID (number)
}

-- Item-Name-Cache: nach Render einmal befüllen, dann per Timer neu rendern
local _statsItemRetryPending = false

local function TryGetItemName(itemID)
  if not itemID then return "?" end
  local name = GetItemInfo(itemID)
  if name then return name end
  -- Noch nicht im Cache → WoW anfordern, später neu rendern
  if not _statsItemRetryPending then
    _statsItemRetryPending = true
    C_Timer.After(0.8, function()
      _statsItemRetryPending = false
      if MyLoot.currentView == "stats" and MyLoot.UI and MyLoot.UI:IsShown() then
        MyLoot.Render()
      end
    end)
  end
  return "Item #" .. itemID
end

-- =========================
-- HILFSFUNKTIONEN
-- =========================
local function GetClassColor(playerName)
  local classColor = MyLootDB.knownClasses and MyLootDB.knownClasses[playerName]
  if classColor and RAID_CLASS_COLORS[classColor] then
    local c = RAID_CLASS_COLORS[classColor]
    return c.r, c.g, c.b
  end
  return 1, 1, 1
end

-- difficulty kommt aus der DB als "normal"/"heroic"/"mythic" (englisch lowercase)
local DIFF_LABEL = {
  normal = "Normal",
  heroic = "Heroisch",
  mythic = "Mythisch",
}
local DIFF_COLOR = {
  normal  = { 0.3, 0.9, 0.3 },
  heroic  = { 0.2, 0.5, 1.0 },
  mythic  = { 0.6, 0.2, 1.0 },
}

local function IsMS(entry)
  local t = (entry.lootType or ""):lower()
  return t == "ms" or t == "main" or t == "mainspec"
end

-- Aggregiert Dropchance-Daten live aus der lootHistory.
-- patches: data.patches (für vollständige Item-Liste inkl. 0%-Items wenn ein Patch gewählt ist)
local function AggregateDropchance(lootHistory, diff, patchId, patches)
  local bossKills = {}
  local itemDrops = {}

  for _, raid in ipairs(lootHistory or {}) do
    local skip = false
    local raidDiff = (raid.difficulty or ""):lower()
    if diff ~= "all" and raidDiff ~= diff then skip = true end
    if not skip and patchId ~= nil then
      local match = false
      for _, pid in ipairs(raid.patchIds or {}) do
        if pid == patchId then match = true; break end
      end
      if not match then skip = true end
    end
    if not skip then
      -- Boss-Kills: jeder Boss zählt pro Raid genau einmal
      local seen = {}
      for _, e in ipairs(raid.entries or {}) do
        if e.boss and not seen[e.boss] then
          seen[e.boss] = true
          bossKills[e.boss] = (bossKills[e.boss] or 0) + 1
        end
      end
      -- Item-Drops pro Boss
      for _, e in ipairs(raid.entries or {}) do
        if e.boss and e.itemID then
          if not itemDrops[e.boss] then itemDrops[e.boss] = {} end
          itemDrops[e.boss][e.itemID] = (itemDrops[e.boss][e.itemID] or 0) + 1
        end
      end
    end
  end

  -- Wenn ein Patch gewählt: vollständige Loot-Tabelle des Patches als Basis verwenden.
  -- Items die nie gedroppt sind erscheinen mit drops=0 (0%-Dropchance).
  if patchId ~= nil and patches then
    for _, p in ipairs(patches) do
      if p.id == patchId and p.bossItems then
        for bossName, itemIDs in pairs(p.bossItems) do
          -- Boss-Eintrag anlegen falls er noch nicht aus lootHistory bekannt ist
          if not bossKills[bossName] then bossKills[bossName] = 0 end
          if not itemDrops[bossName] then itemDrops[bossName] = {} end
          for _, itemID in ipairs(itemIDs) do
            -- Nur eintragen wenn das Item noch nicht als Drop bekannt ist
            if not itemDrops[bossName][itemID] then
              itemDrops[bossName][itemID] = 0
            end
          end
        end
        break
      end
    end
  end

  local result = {}
  for bossName, kills in pairs(bossKills) do
    local items = {}
    for itemID, drops in pairs(itemDrops[bossName] or {}) do
      table.insert(items, {
        itemID = itemID,
        drops  = drops,
        kills  = kills,
        chance = kills > 0 and (drops / kills) or 0,
      })
    end
    -- Sortierung: erst nach Drops absteigend, dann nach ItemID
    table.sort(items, function(a, b)
      if (a.drops or 0) ~= (b.drops or 0) then
        return (a.drops or 0) > (b.drops or 0)
      end
      return (a.itemID or 0) < (b.itemID or 0)
    end)
    table.insert(result, { bossName = bossName, items = items })
  end
  table.sort(result, function(a, b) return (a.bossName or "") < (b.bossName or "") end)
  return result
end

-- Aggregiert Spielerstatistiken live aus der lootHistory
local function AggregatePlayerStats(lootHistory, diff, patchId)
  local players   = {}
  local totalRaids = 0
  local totalLoot  = 0

  for _, raid in ipairs(lootHistory or {}) do
    local skip = false
    local raidDiff = (raid.difficulty or ""):lower()
    if diff ~= "all" and raidDiff ~= diff then skip = true end
    if not skip and patchId ~= nil then
      local match = false
      for _, pid in ipairs(raid.patchIds or {}) do
        if pid == patchId then match = true; break end
      end
      if not match then skip = true end
    end
    if not skip then
      totalRaids = totalRaids + 1
      local raidKey = (raid.raidName or "") .. "|" .. (raid.date or "")
      for _, e in ipairs(raid.entries or {}) do
        if e.player then
          if not players[e.player] then
            players[e.player] = { lootMS = 0, lootOS = 0, raids = {} }
          end
          local pd = players[e.player]
          if IsMS(e) then pd.lootMS = pd.lootMS + 1
          else             pd.lootOS = pd.lootOS + 1 end
          pd.raids[raidKey] = true
          totalLoot = totalLoot + 1
        end
      end
    end
  end

  local result = {}
  for playerName, pd in pairs(players) do
    local lootMS    = pd.lootMS
    local lootOS    = pd.lootOS
    local lootTotal = lootMS + lootOS
    local attended  = 0
    for _ in pairs(pd.raids) do attended = attended + 1 end
    table.insert(result, {
      playerName  = playerName,
      wowClass    = MyLootDB.knownClasses and MyLootDB.knownClasses[playerName] or nil,
      lootTotal   = lootTotal,
      lootMS      = lootMS,
      lootOS      = lootOS,
      raidsTotal  = totalRaids,
      avgPerRaid  = totalRaids > 0 and (lootTotal / totalRaids) or 0,
      avgAttended = attended   > 0 and (lootTotal / attended)   or 0,
      percentage  = totalLoot  > 0 and (lootTotal / totalLoot * 100) or 0,
    })
  end
  table.sort(result, function(a, b) return (a.lootTotal or 0) > (b.lootTotal or 0) end)
  return result
end

-- =========================
-- DROPDOWN-HELPER
-- =========================
local function CreateDropdown(parent, x, y, w, items, currentKey, onSelect)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(w, 22)
  btn:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)

  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.08, 0.08, 0.08, 0.9)

  local border = btn:CreateTexture(nil, "BORDER")
  border:SetAllPoints()
  border:SetColorTexture(0.3, 0.25, 0.0, 0.6)

  local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", 6, 0)
  label:SetPoint("RIGHT", -16, 0)
  label:SetJustifyH("LEFT")
  label:SetTextColor(0.9, 0.9, 0.9)

  local arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  arrow:SetPoint("RIGHT", -4, 0)
  arrow:SetTextColor(0.6, 0.6, 0.6)
  arrow:SetText("▾")

  local function SetLabel(key)
    for _, item in ipairs(items) do
      if item.key == key then label:SetText(item.label); return end
    end
    label:SetText("?")
  end
  SetLabel(currentKey)

  local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  popup:SetFrameStrata("FULLSCREEN_DIALOG")
  popup:SetFrameLevel(9999)
  popup:SetWidth(w)
  popup:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
  popup:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  popup:Hide()

  local rowH = 20
  popup:SetHeight(#items * rowH + 6)

  for i, item in ipairs(items) do
    local row = CreateFrame("Button", nil, popup)
    row:SetSize(w, rowH)
    row:SetPoint("TOPLEFT", 0, -3 - (i - 1) * rowH)

    local rowBg = row:CreateTexture(nil, "BACKGROUND")
    rowBg:SetAllPoints()
    rowBg:SetColorTexture(1, 1, 1, 0)

    local rowLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rowLabel:SetPoint("LEFT", 8, 0)
    rowLabel:SetTextColor(0.85, 0.85, 0.85)
    rowLabel:SetText(item.label)

    local rowKey = item.key
    row:SetScript("OnEnter", function() rowBg:SetColorTexture(1, 0.82, 0, 0.12) end)
    row:SetScript("OnLeave", function() rowBg:SetColorTexture(1, 1, 1, 0) end)
    row:SetScript("OnClick", function()
      SetLabel(rowKey)
      popup:Hide()
      onSelect(rowKey)
    end)
  end

  btn:SetScript("OnClick", function()
    if popup:IsShown() then
      popup:Hide()
    else
      local ax, ay = btn:GetLeft(), btn:GetBottom()
      popup:ClearAllPoints()
      popup:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", ax, ay)
      popup:Show()
    end
  end)

  btn._popup  = popup
  btn._setLbl = SetLabel
  return btn
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

  -- ScrollChild komplett neu erstellen (verhindert Stack Overflow)
  if ui.statsScrollChild then
    ui.statsScrollChild:Hide()
    ui.statsScrollChild:SetParent(nil)
  end
  local child = CreateFrame("Frame", nil, ui.statsScrollFrame)
  child:SetSize(ui.content:GetWidth() or 660, 1)
  ui.statsScrollFrame:SetScrollChild(child)
  ui.statsScrollChild = child

  -- =========================
  -- FILTER-LEISTE (topPanel)
  -- =========================
  if ui.statsTabButtons then
    for _, b in ipairs(ui.statsTabButtons) do
      if b._popup then b._popup:Hide() end
      b:Hide()
    end
  end
  ui.statsTabButtons = {}

  -- ── Ansichts-Tabs ────────────────────────────────────
  local tabs = {
    { key = "history",    label = "Loothistorie"     },
    { key = "player",     label = "Loot pro Spieler" },
    { key = "dropchance", label = "Dropchance"       },
  }
  local tabX = 0
  for _, tab in ipairs(tabs) do
    local btn = CreateFrame("Button", nil, ui.topPanel)
    btn:SetSize(130, 28)
    btn:SetPoint("TOPLEFT", ui.topPanel, "TOPLEFT", tabX + 10, -8)

    local isActive = (statsState.view == tab.key)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(isActive and 0.15 or 0.08, isActive and 0.12 or 0.08, 0, isActive and 0.9 or 0.5)

    local bar = btn:CreateTexture(nil, "BORDER")
    bar:SetPoint("BOTTOMLEFT", 0, 0); bar:SetPoint("BOTTOMRIGHT", 0, 0); bar:SetHeight(2)
    bar:SetColorTexture(1, 0.82, 0, isActive and 1 or 0)

    local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetAllPoints(); lbl:SetJustifyH("CENTER")
    lbl:SetTextColor(isActive and 1 or 0.7, isActive and 0.82 or 0.7, isActive and 0 or 0.7)
    lbl:SetText(tab.label)

    local key = tab.key
    btn:SetScript("OnClick", function() statsState.view = key; MyLoot.Render() end)
    table.insert(ui.statsTabButtons, btn)
    tabX = tabX + 134
  end

  -- ── Difficulty-Dropdown ──────────────────────────────
  local diffItems = {
    { key = "all",    label = "Alle Schwierigkeiten" },
    { key = "normal", label = "Normal"  },
    { key = "heroic", label = "Heroisch"},
    { key = "mythic", label = "Mythisch"},
  }
  local diffBtn = CreateDropdown(ui.topPanel, 10, -44, 155, diffItems, statsState.diff,
    function(key) statsState.diff = key; MyLoot.Render() end)
  table.insert(ui.statsTabButtons, diffBtn)

  -- ── Scope-Dropdown (nicht bei dropchance) ────────────
  local scopeItems = {
    { key = "all", label = "MS + OS"   },
    { key = "ms",  label = "Main-Spec" },
    { key = "os",  label = "Off-Spec"  },
  }
  local scopeBtn = CreateDropdown(ui.topPanel, 173, -44, 125, scopeItems, statsState.scope,
    function(key) statsState.scope = key; MyLoot.Render() end)
  table.insert(ui.statsTabButtons, scopeBtn)
  if statsState.view == "dropchance" then
    scopeBtn:Hide()
    if scopeBtn._popup then scopeBtn._popup:Hide() end
  end

  -- ── Patch-Dropdown ───────────────────────────────────
  local patches = (data and data.patches) or {}
  if #patches > 0 then
    local patchItems = { { key = "all", label = "Alle Patches" } }
    for _, p in ipairs(patches) do
      table.insert(patchItems, { key = tostring(p.id), label = p.name })
    end
    local currentPatchKey = statsState.patchId and tostring(statsState.patchId) or "all"
    local patchBtn = CreateDropdown(ui.topPanel, 306, -44, 155, patchItems, currentPatchKey,
      function(key)
        statsState.patchId = (key == "all") and nil or tonumber(key)
        MyLoot.Render()
      end)
    table.insert(ui.statsTabButtons, patchBtn)
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
  local lootHistory = data.lootHistory or {}
  if statsState.view == "dropchance" then
    local dcList = AggregateDropchance(lootHistory, statsState.diff, statsState.patchId, data.patches)
    MyLoot.RenderStatsDropchance(child, dcList)
  elseif statsState.view == "player" then
    local psList = AggregatePlayerStats(lootHistory, statsState.diff, statsState.patchId)
    MyLoot.RenderStatsPlayer(child, psList, statsState.scope)
  else
    MyLoot.RenderStatsHistory(child, data, statsState.diff, statsState.scope, statsState.patchId)
  end
end


-- =========================
-- DROPCHANCE
-- =========================
function MyLoot.RenderStatsDropchance(child, bossList)
  local y = -10
  local W = child:GetWidth() or 660

  if not bossList or #bossList == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Dropchance-Daten vorhanden.")
    child:SetHeight(40)
    return
  end

  local hadAny = false

  for _, boss in ipairs(bossList) do
    local items = boss.items or {}
    if #items > 0 then
      hadAny = true

      -- Boss-Header
      local bh = child:CreateTexture(nil, "BACKGROUND")
      bh:SetPoint("TOPLEFT", 0, y); bh:SetPoint("TOPRIGHT", 0, y); bh:SetHeight(22)
      bh:SetColorTexture(0.12, 0.10, 0.02, 1)

      local bLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      bLabel:SetPoint("TOPLEFT", 10, y - 3)
      bLabel:SetTextColor(1, 0.82, 0)
      bLabel:SetText(boss.bossName or "Boss")
      y = y - 22

      -- Spalten-Header
      local function H(text, xOff, justify)
        local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        f:SetPoint("TOPLEFT", xOff, y); f:SetTextColor(0.6, 0.6, 0.6)
        f:SetJustifyH(justify or "LEFT"); f:SetText(text)
      end
      H("Item",   10); H("Drops", W-200, "RIGHT"); H("Kills", W-140, "RIGHT"); H("Chance", W-70, "RIGHT")
      y = y - 18

      for i, item in ipairs(items) do
        if i % 2 == 0 then
          local s = child:CreateTexture(nil, "BACKGROUND")
          s:SetPoint("TOPLEFT", 0, y); s:SetPoint("TOPRIGHT", 0, y); s:SetHeight(20)
          s:SetColorTexture(1, 1, 1, 0.03)
        end

        local iName = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        iName:SetPoint("TOPLEFT", 10, y - 2)
        iName:SetTextColor(0.8, 0.8, 1)
        iName:SetText(TryGetItemName(item.itemID))

        local function RCol(text, xOff, cr, cg, cb)
          local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          f:SetPoint("TOPLEFT", xOff, y - 2); f:SetJustifyH("RIGHT"); f:SetWidth(60)
          f:SetTextColor(cr or 0.7, cg or 0.7, cb or 0.7)
          f:SetText(tostring(text ~= nil and text or "—"))
        end
        -- Bei kills=0 → noch kein Raid mit diesem Boss → gedimmt anzeigen
        local neverKilled = (item.kills or 0) == 0
        RCol(item.drops, W - 220, neverKilled and 0.4 or 0.8, neverKilled and 0.4 or 0.8, neverKilled and 0.4 or 0.8)
        RCol(item.kills, W - 160, neverKilled and 0.4 or 0.8, neverKilled and 0.4 or 0.8, neverKilled and 0.4 or 0.8)

        -- chance = drops/kills → * 100 für Prozentanzeige; kills=0 → "—"
        local cf = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cf:SetPoint("TOPLEFT", W - 100, y - 2); cf:SetJustifyH("RIGHT"); cf:SetWidth(60)
        if neverKilled then
          cf:SetTextColor(0.4, 0.4, 0.4)
          cf:SetText("—")
        else
          local chancePct = (item.chance or 0) * 100
          local cc
          if chancePct >= 70 then cc = {0.2, 1, 0.2}
          elseif chancePct >= 40 then cc = {1, 0.82, 0}
          else cc = {1, 0.5, 0.5} end
          cf:SetTextColor(unpack(cc))
          cf:SetText(string.format("%.1f%%", chancePct))
        end
        y = y - 20
      end
      y = y - 8
    end
  end

  if not hadAny then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, -10)
    h:SetText("Keine Items für den gewählten Filter.")
    child:SetHeight(40)
    return
  end

  child:SetHeight(math.abs(y) + 20)
end


-- =========================
-- LOOT PRO SPIELER
-- =========================
function MyLoot.RenderStatsPlayer(child, playerList, scope)
  local y = -10
  local W = child:GetWidth() or 660

  if not playerList or #playerList == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Spieler-Daten vorhanden.")
    child:SetHeight(40)
    return
  end

  local function H(text, xOff)
    local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", xOff, y); f:SetTextColor(1, 0.82, 0); f:SetText(text)
  end
  local lootHeader = scope == "ms" and "MS" or (scope == "os" and "OS" or "Loot")
  H("Charakter", 10); H(lootHeader, 200); H("MS", 260); H("OS", 300)
  H("Raids", 340); H("Ø/Raid", 420); H("Ø/teilgen.", 500); H("Anteil", 580)
  y = y - 4

  local hline = child:CreateTexture(nil, "ARTWORK")
  hline:SetColorTexture(1, 0.82, 0, 0.3)
  hline:SetPoint("TOPLEFT", 0, y); hline:SetPoint("TOPRIGHT", 0, y); hline:SetHeight(1)
  y = y - 18

  for i, ps in ipairs(playerList) do
    local lootVal = scope == "ms" and (ps.lootMS or 0)
                 or scope == "os" and (ps.lootOS or 0)
                 or (ps.lootTotal or 0)

    if i % 2 == 0 then
      local s = child:CreateTexture(nil, "BACKGROUND")
      s:SetPoint("TOPLEFT", 0, y); s:SetPoint("TOPRIGHT", 0, y); s:SetHeight(20)
      s:SetColorTexture(1, 1, 1, 0.03)
    end

    local r, g, b = GetClassColor(ps.playerName)
    local function Col(text, xOff, cr, cg, cb)
      local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f:SetPoint("TOPLEFT", xOff, y - 2)
      f:SetTextColor(cr or 1, cg or 1, cb or 1)
      f:SetText(tostring(text or "—"))
    end

    Col(ps.playerName or "?",   10, r, g, b)
    Col(lootVal,                200)
    Col(ps.lootMS or 0,         260, 0.3, 0.9, 0.3)
    Col(ps.lootOS or 0,         300, 0.6, 0.6, 0.6)
    Col(string.format("%d/%d", 0, ps.raidsTotal or 0), 340, 0.7, 0.7, 0.7)
    Col(string.format("%.2f", ps.avgPerRaid  or 0),    420)
    Col(string.format("%.2f", ps.avgAttended or 0),    500)

    local pct  = ps.percentage or 0
    local barW = math.max(2, math.min(120, pct * 1.2))
    local bar  = child:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("TOPLEFT", 580, y - 4); bar:SetSize(barW, 12)
    bar:SetColorTexture(0.2, 0.6, 0.2, 0.8)

    local pctLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pctLabel:SetPoint("TOPLEFT", 706, y - 2); pctLabel:SetTextColor(0.7, 0.7, 0.7)
    pctLabel:SetText(string.format("%.1f%%", pct))
    y = y - 20
  end

  child:SetHeight(math.abs(y) + 20)
end


-- =========================
-- LOOTHISTORIE
-- =========================
function MyLoot.RenderStatsHistory(child, data, diff, scope, patchId)
  local y = -10
  local W = child:GetWidth() or 660

  if not data.lootHistory or #data.lootHistory == 0 then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, y)
    h:SetText("Keine Loothistorie vorhanden.")
    child:SetHeight(40)
    return
  end

  local typeColors = { ms = {0.2, 0.8, 1.0}, os = {0.5, 0.5, 0.5} }
  local hadAnyRaid = false

  for _, raid in ipairs(data.lootHistory) do
    local raidDiff = (raid.difficulty or ""):lower()

    -- Filter
    local skip = false
    if diff ~= "all" and raidDiff ~= diff then skip = true end
    if not skip and patchId ~= nil then
      local patchMatch = false
      for _, pid in ipairs(raid.patchIds or {}) do
        if pid == patchId then patchMatch = true; break end
      end
      if not patchMatch then skip = true end
    end

    if not skip then
      -- Scope-Filter auf Eintragsebene
      local entries = {}
      for _, e in ipairs(raid.entries or {}) do
        local eIsMS = IsMS(e)
        if scope == "ms" and not eIsMS then
        elseif scope == "os" and eIsMS then
        else table.insert(entries, e) end
      end

      if #entries > 0 then
        hadAnyRaid = true

        -- Raid-Header
        local rh = child:CreateTexture(nil, "BACKGROUND")
        rh:SetPoint("TOPLEFT", 0, y); rh:SetPoint("TOPRIGHT", 0, y); rh:SetHeight(22)
        rh:SetColorTexture(0.10, 0.08, 0.02, 1)

        local rName = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rName:SetPoint("TOPLEFT", 10, y - 3); rName:SetTextColor(1, 0.82, 0)
        rName:SetText(raid.raidName or "Raid")

        if raid.date then
          local rDate = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          rDate:SetPoint("TOPLEFT", 360, y - 3); rDate:SetTextColor(0.7, 0.7, 0.7)
          rDate:SetText(raid.date)
        end

        local dc = DIFF_COLOR[raidDiff] or {0.7, 0.7, 0.7}
        local dlabel = DIFF_LABEL[raidDiff] or ""
        if dlabel ~= "" then
          local badge = child:CreateTexture(nil, "ARTWORK")
          badge:SetPoint("TOPLEFT", W - 100, y - 1); badge:SetSize(84, 16)
          badge:SetColorTexture(dc[1]*0.3, dc[2]*0.3, dc[3]*0.3, 0.9)
          local dLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          dLabel:SetPoint("TOPLEFT", W - 100, y - 3); dLabel:SetWidth(84)
          dLabel:SetJustifyH("CENTER"); dLabel:SetTextColor(unpack(dc)); dLabel:SetText(dlabel)
        end
        y = y - 22

        -- Spalten-Header
        local function H(text, xOff)
          local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          f:SetPoint("TOPLEFT", xOff, y - 2); f:SetTextColor(0.5, 0.5, 0.5); f:SetText(text)
        end
        H("Zeitpunkt", 10); H("Boss", 120); H("Item", 280); H("Charakter", 520); H("Typ", 620)
        y = y - 18

        for i, entry in ipairs(entries) do
          if i % 2 == 0 then
            local s = child:CreateTexture(nil, "BACKGROUND")
            s:SetPoint("TOPLEFT", 0, y); s:SetPoint("TOPRIGHT", 0, y); s:SetHeight(18)
            s:SetColorTexture(1, 1, 1, 0.03)
          end

          local timeStr = entry.timestamp and date("%d.%m. %H:%M", entry.timestamp) or ""
          local r, g, b = GetClassColor(entry.player)
          local eIsMS = IsMS(entry)
          local tc = eIsMS and typeColors.ms or typeColors.os

          local function Col(text, xOff, cr, cg, cb)
            local f = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            f:SetPoint("TOPLEFT", xOff, y - 2)
            f:SetTextColor(cr or 0.8, cg or 0.8, cb or 0.8)
            f:SetText(tostring(text or ""))
          end

          Col(timeStr,                       10, 0.5, 0.5, 0.5)
          Col(entry.boss or "",             120)
          Col(TryGetItemName(entry.itemID), 280, 0.8, 0.8, 1.0)
          Col(entry.player or "",           520, r, g, b)

          local typeBg = child:CreateTexture(nil, "ARTWORK")
          typeBg:SetPoint("TOPLEFT", 615, y - 1); typeBg:SetSize(46, 14)
          typeBg:SetColorTexture(tc[1]*0.3, tc[2]*0.3, tc[3]*0.3, 0.9)

          local typeLabel = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          typeLabel:SetPoint("TOPLEFT", 615, y - 2); typeLabel:SetWidth(46)
          typeLabel:SetJustifyH("CENTER"); typeLabel:SetTextColor(unpack(tc))
          typeLabel:SetText(eIsMS and "Main" or "Off")
          y = y - 18
        end
        y = y - 10
      end
    end
  end

  if not hadAnyRaid then
    local h = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    h:SetPoint("TOPLEFT", 10, -10)
    h:SetText("Keine Einträge für den gewählten Filter.")
    child:SetHeight(40)
    return
  end

  child:SetHeight(math.abs(y) + 20)
end
