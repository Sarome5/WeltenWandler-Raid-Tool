MyLoot = MyLoot or {}

-- =========================
-- RAID VIEW
-- =========================
function MyLoot.RenderRaidView()
  local ui   = MyLoot.UI
  local data = WRT_RaidData

  local y = -10
  local panel = ui.bottomPanel

  -- Hilfsfunktion: Zeile mit Label + Wert
  local function AddRow(label, value, valueColor)
    local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", 10, y)
    lbl:SetTextColor(0.7, 0.7, 0.7)
    lbl:SetText(label)

    local val = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    val:SetPoint("TOPLEFT", 160, y)
    if valueColor then
      val:SetTextColor(unpack(valueColor))
    else
      val:SetTextColor(1, 1, 1)
    end
    val:SetText(value or "—")

    y = y - 24
  end

  -- Trennlinie
  local function AddSeparator()
    local line = panel:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", 10, y - 4)
    line:SetPoint("TOPRIGHT", -10, y - 4)
    line:SetHeight(1)
    y = y - 18
  end

  -- Überschrift
  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 10, y)
  title:SetTextColor(1, 0.82, 0)
  y = y - 30

  -- Keine Daten vorhanden (Companion App noch nicht eingerichtet)
  if not data or not data.raidID then
    title:SetText("Raid")
    AddSeparator()

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 10, y)
    hint:SetText("Keine Raid-Daten vorhanden.")
    y = y - 20

    local hint2 = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint2:SetPoint("TOPLEFT", 10, y)
    hint2:SetText("Bitte WeltenWandler Companion App einrichten.")
    return
  end

  -- Titel mit Raid-Name
  title:SetText(data.raidName or "Raid")

  AddSeparator()

  -- Basis-Infos
  AddRow("Schwierigkeit:", data.difficulty)

  if data.scheduledAt and data.scheduledAt > 0 then
    AddRow("Datum:", date("%d.%m.%Y  %H:%M", data.scheduledAt))
  end

  AddSeparator()

  -- Anmeldestatus
  local statusMap = {
    ["angemeldet"] = { text = "Angemeldet", color = { 0.2, 1,    0.2  } },
    ["spaeter"]    = { text = "Später",     color = { 1,   0.85,  0    } },
    ["vorlaeufig"] = { text = "Vorläufig",  color = { 1,   0.6,   0.1  } },
    ["bench"]      = { text = "Bench",      color = { 0.4, 0.7,   1    } },
    ["abgelehnt"]  = { text = "Abgelehnt",  color = { 1,   0.3,   0.3  } },
  }
  local statusEntry = statusMap[data.signupStatus]
  local statusText  = statusEntry and statusEntry.text  or (data.signupStatus or "Unbekannt")
  local statusColor = statusEntry and statusEntry.color or { 0.5, 0.5, 0.5 }
  AddRow("Anmeldestatus:", statusText, statusColor)

  -- Prio-Status
  local prioColor = data.prioFilled and { 0.2, 1, 0.2 } or { 1, 0.6, 0.1 }
  local prioText  = data.prioFilled and "Ausgefüllt" or "Nicht ausgefüllt"
  AddRow("Prio-Liste:", prioText, prioColor)

  -- Prio-Items anzeigen
  if data.prioFilled and data.prioItems and #data.prioItems > 0 then
    AddSeparator()

    local prioHeader = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prioHeader:SetPoint("TOPLEFT", 10, y)
    prioHeader:SetTextColor(1, 0.82, 0)
    prioHeader:SetText("Meine Prio-Items:")
    y = y - 22

    for _, entry in ipairs(data.prioItems) do
      local row = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      row:SetPoint("TOPLEFT", 20, y)
      row:SetText(string.format("Prio %d  —  %s", entry.priority or 0, entry.itemName or ("Item " .. (entry.itemID or "?"))))
      y = y - 20
    end
  end

  -- Stand der Daten
  if data.generatedAt and data.generatedAt > 0 then
    AddSeparator()
    local age = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    age:SetPoint("TOPLEFT", 10, y)
    age:SetText("Datenstand: " .. date("%d.%m.%Y %H:%M", data.generatedAt))
  end
end
