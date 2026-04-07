MyLoot = MyLoot or {}

function MyLoot.RenderRaidView()
  local ui   = MyLoot.UI
  local data = WRT_RaidData

  -- ScrollFrame aufbauen / wiederverwenden
  if not ui.raidScrollFrame then
    local sf = CreateFrame("ScrollFrame", nil, ui.content)
    sf:SetPoint("TOPLEFT",     ui.content, "TOPLEFT",     0,  -10)
    sf:SetPoint("BOTTOMRIGHT", ui.content, "BOTTOMRIGHT", 0,  0)
    sf:EnableMouseWheel(true)
    sf:SetScript("OnMouseWheel", function(self, delta)
      self:SetVerticalScroll(math.max(0, self:GetVerticalScroll() - delta * 20))
    end)

    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(ui.content:GetWidth(), 1)
    sf:SetScrollChild(child)

    ui.raidScrollFrame = sf
    ui.raidScrollChild = child
  end

  ui.raidScrollFrame:Show()
  ui.raidScrollFrame:SetVerticalScroll(0)

  -- Child leeren
  local child = ui.raidScrollChild
  for _, c in ipairs({ child:GetChildren() }) do c:Hide() end
  for _, r in ipairs({ child:GetRegions() }) do
    if r:IsObjectType("FontString") then r:SetText("") end
    if r:IsObjectType("Texture")    then r:Hide() end
  end

  local y = -10

  -- Keine Daten
  if not data or not data.raids or #data.raids == 0 then
    local hint = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", child, "TOP", 0, y)
    hint:SetJustifyH("CENTER")
    hint:SetTextColor(0.5, 0.5, 0.5)
    hint:SetText("Keine Raid-Daten vorhanden.\nBitte WeltenWandler Companion App einrichten.")
    child:SetHeight(80)
    return
  end

  local statusMap = {
    ["angemeldet"] = { text = "Angemeldet",  color = { 0.2, 1,    0.2  } },
    ["spaeter"]    = { text = "Später",      color = { 1,   0.85, 0    } },
    ["vorlaeufig"] = { text = "Vorläufig",   color = { 1,   0.6,  0.1  } },
    ["bench"]      = { text = "Ersatzbank",  color = { 0.4, 0.7,  1    } },
    ["abgelehnt"]  = { text = "Abwesend",    color = { 1,   0.3,  0.3  } },
  }

  local function AddRow(label, value, valueColor)
    local lbl = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 16, y)
    lbl:SetTextColor(0.7, 0.7, 0.7)
    lbl:SetText(label)

    local val = child:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("TOPLEFT", 170, y)
    if valueColor then
      val:SetTextColor(unpack(valueColor))
    else
      val:SetTextColor(1, 1, 1)
    end
    val:SetText(value or "—")
    y = y - 22
  end

  local function AddSeparator()
    local line = child:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.06)
    line:SetPoint("TOPLEFT",  8, y - 4)
    line:SetPoint("TOPRIGHT", -8, y - 4)
    line:SetHeight(1)
    y = y - 14
  end

  -- Jeden Raid rendern
  for i, raid in ipairs(data.raids) do
    -- Raid-Header
    local header = child:CreateTexture(nil, "BACKGROUND")
    header:SetPoint("TOPLEFT",  0, y)
    header:SetPoint("TOPRIGHT", 0, y)
    header:SetHeight(28)
    header:SetColorTexture(0.12, 0.10, 0.02, 1)

    local rTitle = child:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rTitle:SetPoint("TOPLEFT", 10, y - 4)
    rTitle:SetTextColor(1, 0.82, 0)
    rTitle:SetText(raid.raidName or "Raid")
    y = y - 34

    -- Infos
    AddRow("Schwierigkeit:", raid.difficulty)

    if raid.scheduledAt and raid.scheduledAt > 0 then
      AddRow("Datum:", date("%d.%m.%Y  %H:%M", raid.scheduledAt))
    end

    AddSeparator()

    local statusEntry = statusMap[raid.signupStatus]
    local statusText  = statusEntry and statusEntry.text  or (raid.signupStatus or "Unbekannt")
    local statusColor = statusEntry and statusEntry.color or { 0.5, 0.5, 0.5 }
    AddRow("Anmeldestatus:", statusText, statusColor)

    local prioColor = raid.prioFilled and { 0.2, 1, 0.2 } or { 1, 0.6, 0.1 }
    local prioText  = raid.prioFilled and "Ausgefüllt" or "Nicht ausgefüllt"
    AddRow("Prio-Liste:", prioText, prioColor)

    -- Prio-Items
    if raid.prioFilled and raid.prioItems and #raid.prioItems > 0 then
      AddSeparator()
      local ph = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      ph:SetPoint("TOPLEFT", 16, y)
      ph:SetTextColor(1, 0.82, 0)
      ph:SetText("Meine Prio-Items:")
      y = y - 20

      for _, entry in ipairs(raid.prioItems) do
        local row = child:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row:SetPoint("TOPLEFT", 26, y)
        row:SetText(string.format("Prio %d  —  %s",
          entry.priority or 0,
          entry.itemName or ("Item " .. (entry.itemID or "?"))))
        y = y - 18
      end
    end

    -- Abstand zwischen Raids
    y = y - 16

    -- Trennlinie zwischen Raids (nicht nach dem letzten)
    if i < #data.raids then
      local divider = child:CreateTexture(nil, "ARTWORK")
      divider:SetColorTexture(1, 0.82, 0, 0.15)
      divider:SetPoint("TOPLEFT",  8, y)
      divider:SetPoint("TOPRIGHT", -8, y)
      divider:SetHeight(1)
      y = y - 16
    end
  end

  -- Datenstand
  if data.generatedAt and data.generatedAt > 0 then
    local age = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    age:SetPoint("TOPLEFT", 10, y - 6)
    age:SetText("Datenstand: " .. date("%d.%m.%Y %H:%M", data.generatedAt))
    y = y - 24
  end

  child:SetHeight(math.abs(y) + 20)
end
