MyLoot = MyLoot or {}

-- =========================
-- PRIO VIEW
-- =========================

-- Gibt die Klassenfarbe eines Charakters zurück.
-- Reihenfolge: 1. Live via UnitClass (im Raid)
--              2. Cache aus Import (MyLootDB.knownClasses)
--              3. nil (kein Eintrag bekannt)
local function GetCharacterClassColor(name)
  MyLootDB.knownClasses = MyLootDB.knownClasses or {}

  -- Live-Abfrage wenn Spieler in der Gruppe ist → gleichzeitig Cache aktualisieren
  local _, classKey = UnitClass(name)
  if classKey then
    MyLootDB.knownClasses[name] = classKey
    return RAID_CLASS_COLORS[classKey]
  end

  -- Aus Cache
  local cached = MyLootDB.knownClasses[name]
  if cached then
    return RAID_CLASS_COLORS[cached]
  end

  return nil
end

-- Debounce-Flag: verhindert dass mehrere ContinueOnItemLoad gleichzeitig neu rendern
MyLoot._prioRenderPending = false

function MyLoot.RenderPrioList()
  local ui = MyLoot.UI

  if not ui.prioListFrame then
    local sf = CreateFrame("ScrollFrame", nil, ui.content)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", 0, 0)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(_, delta)
      sf:SetVerticalScroll(math.max(0, sf:GetVerticalScroll() - delta * 30))
    end)
    ui.prioListFrame = sf
  end

  local sf = ui.prioListFrame

  -- ScrollChild komplett neu erstellen statt GetRegions() zu leeren
  -- (verhindert Stack Overflow durch akkumulierte tausende von Regions)
  if ui.prioListChild then
    ui.prioListChild:Hide()
    ui.prioListChild:SetParent(nil)
  end
  local sc = CreateFrame("Frame", nil, sf)
  sc:SetWidth(ui.content:GetWidth() or 680)
  sc:SetHeight(1)
  sf:SetScrollChild(sc)
  ui.prioListChild = sc

  sf:Show()
  sf:SetVerticalScroll(0)

  -- =========================
  -- LAYOUT
  -- =========================
  local prioData  = MyLootDB.raid.prioData or {}
  local rowHeight = 38
  local nameWidth = 160
  local colWidth  = 165
  local colCount  = 3
  local startX    = 10
  local startY    = -10
  local totalW    = nameWidth + colWidth * colCount + 10

  local players = {}
  for player in pairs(prioData) do
    table.insert(players, player)
  end
  table.sort(players)

  -- =========================
  -- HEADER
  -- =========================
  local headerBg = sc:CreateTexture(nil, "BACKGROUND")
  headerBg:SetPoint("TOPLEFT", startX - 5, startY)
  headerBg:SetSize(totalW, 44)
  headerBg:SetColorTexture(0.12, 0.12, 0.15, 0.95)

  local charHeader = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  charHeader:SetPoint("TOPLEFT", startX + 8, startY - 8)
  charHeader:SetTextColor(1, 0.82, 0)
  charHeader:SetText("Charakter")

  for i = 1, colCount do
    local col = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    col:SetPoint("TOPLEFT", startX + nameWidth + (i - 1) * colWidth, startY - 8)
    col:SetWidth(colWidth)
    col:SetJustifyH("CENTER")
    col:SetTextColor(1, 0.82, 0)
    col:SetText("Prio " .. i)
  end

  -- Goldene Trennlinie unter Header
  local headerLine = sc:CreateTexture(nil, "OVERLAY")
  headerLine:SetPoint("TOPLEFT", startX - 5, startY - 44)
  headerLine:SetSize(totalW, 1)
  headerLine:SetColorTexture(1, 0.82, 0, 0.5)

  -- =========================
  -- ZEILEN (Hintergründe zuerst)
  -- =========================
  for rowIndex, player in ipairs(players) do
    local y = startY - 50 - ((rowIndex - 1) * rowHeight)

    local rowBg = sc:CreateTexture(nil, "BACKGROUND")
    rowBg:SetPoint("TOPLEFT", startX - 5, y)
    rowBg:SetSize(totalW, rowHeight)
    if rowIndex % 2 == 0 then
      rowBg:SetColorTexture(0.1, 0.1, 0.12, 0.95)
    else
      rowBg:SetColorTexture(0.07, 0.07, 0.09, 0.95)
    end
  end

  -- =========================
  -- ZEILEN (Inhalt)
  -- =========================
  for rowIndex, player in ipairs(players) do
    local items = prioData[player]
    local y = startY - 50 - ((rowIndex - 1) * rowHeight)

    -- Spielername
    local nameText = sc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOPLEFT", startX + 8, y - 10)
    nameText:SetWidth(nameWidth - 16)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)

    local classColor = GetCharacterClassColor(player)
    if classColor then
      nameText:SetText("|c" .. classColor.colorStr .. player .. "|r")
    else
      nameText:SetTextColor(0.8, 0.8, 0.8)
      nameText:SetText(player)
    end

    -- Prio-Spalten
    if type(items) == "table" then
      for p = 1, colCount do
        local cellX = startX + nameWidth + (p - 1) * colWidth
        local rendered = false

        for itemID, prio in pairs(items) do
          local isMatch      = type(prio) == "number" and prio == p
          local isSuperprio  = prio == "superprio"

          if isMatch or isSuperprio then
            local itemName, itemLink, itemQuality, _, _, _, _, _, _, itemIcon = GetItemInfo(itemID)

            if not itemName then
              local itemObj = Item:CreateFromItemID(tonumber(itemID) or 0)
              itemObj:ContinueOnItemLoad(function()
                -- Debounce: nur ein Render auslösen wenn mehrere Items gleichzeitig laden
                if not MyLoot._prioRenderPending then
                  MyLoot._prioRenderPending = true
                  C_Timer.After(0.05, function()
                    MyLoot._prioRenderPending = false
                    if MyLoot.currentView == "prio" then
                      MyLoot.Render()
                    end
                  end)
                end
              end)
            end

            -- Icon
            if itemIcon then
              local icon = sc:CreateTexture(nil, "ARTWORK")
              icon:SetSize(16, 16)
              icon:SetPoint("TOPLEFT", cellX + 5, y - 11)
              icon:SetTexture(itemIcon)
            end

            -- Item Name in Qualitätsfarbe; Superprio-Einträge gold hervorheben
            local nameStr = itemName or ("Item " .. tostring(itemID))
            local r, g, b = 1, 1, 1
            if isSuperprio then
              r, g, b = 1, 0.82, 0
            elseif itemQuality then
              r, g, b = GetItemQualityColor(itemQuality)
            end

            local colText = sc:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            colText:SetPoint("TOPLEFT", cellX + 24, y - 11)
            colText:SetWidth(colWidth - 32)
            colText:SetJustifyH("LEFT")
            colText:SetWordWrap(false)
            colText:SetTextColor(r, g, b)
            colText:SetText(nameStr)

            -- Tooltip Button (unsichtbar über der Zelle)
            if itemLink then
              local tipBtn = CreateFrame("Button", nil, sc)
              tipBtn:SetPoint("TOPLEFT", cellX, y)
              tipBtn:SetSize(colWidth, rowHeight)
              tipBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(itemLink)
                GameTooltip:Show()
              end)
              tipBtn:SetScript("OnLeave", function()
                GameTooltip:Hide()
              end)
            end

            rendered = true
            break
          end
        end

        -- Kein Item für diesen Slot → Spieler hat gepasst
        if not rendered then
          local dashTxt = sc:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
          dashTxt:SetPoint("TOPLEFT", cellX + 5, y - 11)
          dashTxt:SetTextColor(0.4, 0.4, 0.4)
          dashTxt:SetText("—")
        end
      end
    end

    -- Horizontale Trennlinie (OVERLAY, über allem)
    local rowLine = sc:CreateTexture(nil, "OVERLAY")
    rowLine:SetPoint("TOPLEFT", startX - 5, y - rowHeight)
    rowLine:SetSize(totalW, 1)
    rowLine:SetColorTexture(1, 1, 1, 0.06)
  end

  -- =========================
  -- VERTIKALE LINIEN (ganz zuletzt, OVERLAY)
  -- =========================
  local linesTop    = startY - 44
  local linesBottom = startY - 50 - (#players * rowHeight)

  for i = 1, colCount do
    local line = sc:CreateTexture(nil, "OVERLAY")
    local lx = startX + nameWidth + (i - 1) * colWidth - 5
    line:SetPoint("TOPLEFT",    sc, "TOPLEFT", lx, linesTop)
    line:SetPoint("BOTTOMLEFT", sc, "TOPLEFT", lx, linesBottom)
    line:SetWidth(1)
    line:SetColorTexture(1, 1, 1, 0.12)
  end

  sc:SetHeight(math.max(#players * rowHeight + 60, 1))
end
