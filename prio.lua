MyLoot = MyLoot or {}

-- =========================
-- HILFSFUNKTION: ItemID aus Link
-- =========================
function MyLoot.GetItemID(itemLink)
  if not itemLink then return nil end
  return tonumber(itemLink:match("item:(%d+)")) or tonumber(itemLink)
end

-- =========================
-- MODE
-- =========================
function MyLoot.GetItemMode(itemLink)
  local itemID = MyLoot.GetItemID(itemLink)
  if not itemID then return "FFA" end

  if MyLootDB.raid.ffaItems[itemID] then
    return "FFA"
  end

  local ipd = MyLootDB.raid.itemPrioData
  if not ipd or not ipd[itemID] then
    return "FFA"
  end

  local data = ipd[itemID]
  local hasAny = #data.superprio > 0 or #data[1] > 0 or #data[2] > 0 or #data[3] > 0
  if not hasAny then return "FFA" end

  if MyLootDB.raid.superprioEnabled and #data.superprio > 0 then
    return "SUPERPRIO"
  end

  return "PRIO"
end


-- =========================
-- TOP BAR
-- =========================
function MyLoot.RenderTopBar()
  local ui          = MyLoot.UI
  local raid        = MyLootDB.raid
  local selectedIndex = MyLootDB.selectedBossIndex or 1

  -- Boss-Dropdown (oben links)
  if raid and raid.bosses then
    if not ui.bossButton then
      local btn = CreateFrame("Button", nil, ui.topPanel, "BackdropTemplate")
      btn:SetSize(180, 25)
      btn:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background" })
      btn:SetBackdropColor(0.1, 0.1, 0.1, 0.9)

      local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      text:SetPoint("LEFT", 10, 0)
      btn.text = text
      ui.bossButton = btn
    end

    ui.bossButton:SetPoint("TOPLEFT", 10, -8)
    ui.bossButton:Show()

    if not ui.bossDropdown then
      ui.bossDropdown = MyDropdown:Create(UIParent)
    end

    local selectedBoss = raid.bosses[selectedIndex]
    ui.bossButton.text:SetText(selectedBoss and selectedBoss.bossName or "Boss wählen")

    ui.bossButton:SetScript("OnClick", function()
      local dd = ui.bossDropdown
      if dd:IsShown() then dd:Hide(); return end

      local items = {}
      for i, boss in ipairs(raid.bosses) do
        items[i] = {
          text  = (boss.bossName or boss.name or "Boss " .. i) .. (boss.difficulty and " [" .. boss.difficulty .. "]" or "") .. " (" .. i .. ")",
          value = i
        }
      end

      dd:SetPoint("TOPLEFT", ui.bossButton, "BOTTOMLEFT", 0, -5)
      dd:SetItems(items, function(selected)
        MyLootDB.selectedBossIndex = selected.value
        MyLoot.Render()
      end)
      dd:Show()
      dd:Raise()
    end)
  end

  -- =========================
  -- AKTIVES ITEM (zentriert, unterhalb Dropdown)
  -- =========================
  if MyLootDB.activeItem then
    local itemLink = MyLootDB.activeItem
    local name, _, quality = GetItemInfo(itemLink)
    if not name then
      name = itemLink:match("%[(.-)%]") or "Item"
    end

    -- Icon
    if not ui.activeItemIcon then
      local icon = ui.topPanel:CreateTexture(nil, "ARTWORK")
      icon:SetSize(22, 22)
      ui.activeItemIcon = icon
    end

    local _, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemLink)

    -- Name in Qualitätsfarbe
    if not ui.activeItemText then
      local txt = ui.topPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      ui.activeItemText = txt
    end

    local r, g, b = 1, 0.82, 0
    if quality then r, g, b = GetItemQualityColor(quality) end

    if texture then
      ui.activeItemIcon:SetTexture(texture)

      -- Text zuerst setzen, damit GetStringWidth korrekt ist
      ui.activeItemText:SetTextColor(r, g, b)
      ui.activeItemText:SetText(name)

      local totalW   = 22 + 5 + ui.activeItemText:GetStringWidth()
      local iconOffX = -(totalW / 2) + 11
      ui.activeItemIcon:ClearAllPoints()
      ui.activeItemIcon:SetPoint("LEFT", ui.topPanel, "CENTER", iconOffX, -10)
      ui.activeItemIcon:Show()

      ui.activeItemText:ClearAllPoints()
      ui.activeItemText:SetPoint("LEFT", ui.activeItemIcon, "RIGHT", 5, 0)
      ui.activeItemText:Show()
    else
      ui.activeItemIcon:Hide()
      ui.activeItemText:SetTextColor(r, g, b)
      ui.activeItemText:SetText(name)
      ui.activeItemText:ClearAllPoints()
      ui.activeItemText:SetPoint("CENTER", ui.topPanel, "CENTER", 0, -10)
      ui.activeItemText:Show()
    end

    -- Tooltip-Button über dem aktiven Item
    if not ui.activeItemTooltipBtn then
      local tipBtn = CreateFrame("Button", nil, ui.topPanel)
      tipBtn:SetSize(280, 30)
      ui.activeItemTooltipBtn = tipBtn
    end
    ui.activeItemTooltipBtn:ClearAllPoints()
    ui.activeItemTooltipBtn:SetPoint("CENTER", ui.topPanel, "CENTER", 0, -10)
    ui.activeItemTooltipBtn:SetScript("OnEnter", function(self)
      if MyLootDB.activeItem then
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetHyperlink(MyLootDB.activeItem)
        GameTooltip:Show()
      end
    end)
    ui.activeItemTooltipBtn:SetScript("OnLeave", function()
      GameTooltip:Hide()
    end)
    ui.activeItemTooltipBtn:Show()

  else
    -- Kein aktives Item → Platzhalter
    if not ui.activeItemText then
      local txt = ui.topPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
      ui.activeItemText = txt
    end
    ui.activeItemText:ClearAllPoints()
    ui.activeItemText:SetPoint("CENTER", ui.topPanel, "CENTER", 0, -10)
    ui.activeItemText:SetTextColor(0.5, 0.5, 0.5)
    ui.activeItemText:SetText("Kein Item ausgewählt")
    ui.activeItemText:Show()

    if ui.activeItemIcon then ui.activeItemIcon:Hide() end
  end
end

-- =========================
-- RENDER PRIO
-- =========================
function MyLoot.RenderItemPrio()
  local ui       = MyLoot.UI
  local itemLink = MyLootDB.activeItem

  -- Kein aktives Item → Platzhalter im prioPanel
  if not itemLink then
    local hint = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("CENTER", ui.prioPanel, "CENTER", 0, 0)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(0.4, 0.4, 0.4)
    hint:SetText("Item aus der Lootliste auswählen\num die Prio-Auswertung zu sehen")
    return
  end

  local itemID = MyLoot.GetItemID(itemLink)
  local mode   = MyLoot.GetItemMode(itemLink)

  if mode == "FFA" then
    local title = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("CENTER", ui.prioPanel, "CENTER", 0, 10)
    title:SetJustifyH("CENTER")
    title:SetText("|cffff6600FFA – Free for All|r")

    local sub = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("CENTER", ui.prioPanel, "CENTER", 0, -10)
    sub:SetJustifyH("CENTER")
    sub:SetText("Kein Spieler hat dieses Item auf der Prio-Liste.")
    return
  end

  local title = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 10, -10)
  title:SetText("Prio Auswertung")

  local data = itemID and (MyLootDB.raid.itemPrioData or {})[itemID]
  if not data then
    local sub = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sub:SetPoint("TOPLEFT", 10, -30)
    sub:SetText("Keine Prio-Daten vorhanden. Bitte Import durchführen.")
    return
  end

  -- Spalten aufbauen
  local cols = {}

  if MyLootDB.raid.superprioEnabled and #data.superprio > 0 then
    table.insert(cols, { label = "|cffffff00Superprio|r", players = data.superprio })
  end

  table.insert(cols, { label = "Prio 1", players = data[1] })
  table.insert(cols, { label = "Prio 2", players = data[2] })
  table.insert(cols, { label = "Prio 3", players = data[3] })

  local colWidth = 160
  local startX   = 10

  for i, col in ipairs(cols) do
    local x = startX + (i - 1) * colWidth

    local header = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", x, -35)
    header:SetText(col.label)

    local line = ui.prioPanel:CreateTexture(nil, "BACKGROUND")
    line:SetColorTexture(1, 1, 1, 0.15)
    line:SetPoint("TOPLEFT", x, -50)
    line:SetSize(colWidth - 10, 1)

    local y = -58

    if #col.players == 0 then
      local empty = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      empty:SetPoint("TOPLEFT", x, y)
      empty:SetText("—")
    else
      for _, name in ipairs(col.players) do
        local txt = ui.prioPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        txt:SetPoint("TOPLEFT", x, y)

        local classColor = GetCharacterClassColor and GetCharacterClassColor(name)
        if classColor then
          txt:SetText("|c" .. classColor.colorStr .. name .. "|r")
        else
          txt:SetText(name)
        end

        y = y - 16
      end
    end
  end
end
