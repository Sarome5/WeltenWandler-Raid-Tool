MyLoot = MyLoot or {}

-- =========================
-- IMPORT VIEW
-- =========================

function MyLoot.RenderImportView()
  local ui = MyLoot.UI

  if not ui.importFrame then
    local f = CreateFrame("Frame", nil, ui.content)
    f:SetPoint("TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", 0, 0)

    -- Titel
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -20)
    title:SetText("Prio Import")

    local desc = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOPLEFT", 20, -45)
    desc:SetText("Importstring von der Website hier einfügen:")

    -- EditBox Container
    local editContainer = CreateFrame("Frame", nil, f, "BackdropTemplate")
    editContainer:SetPoint("TOPLEFT", 20, -70)
    editContainer:SetSize(620, 36)
    editContainer:SetBackdrop({
      bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 10,
    })
    editContainer:SetBackdropColor(0, 0, 0, 0.6)
    editContainer:EnableMouse(true)
    editContainer:SetScript("OnMouseDown", function()
      WRTImportEditBox:SetFocus()
    end)

    local editBox = CreateFrame("EditBox", "WRTImportEditBox", editContainer)
    editBox:SetPoint("LEFT", editContainer, "LEFT", 10, 0)
    editBox:SetPoint("RIGHT", editContainer, "RIGHT", -10, 0)
    editBox:SetHeight(24)
    editBox:SetMultiLine(false)
    editBox:SetMaxLetters(0)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:EnableMouse(true)
    editBox:SetScript("OnMouseDown", function(self)
      self:SetFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    editBox:SetScript("OnEnterPressed", function(self)
      self:ClearFocus()
    end)

    -- Status Label
    local statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusText:SetPoint("TOPLEFT", 20, -120)
    statusText:SetText("")
    f.statusText = statusText

    -- Import Button
    local importBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    importBtn:SetSize(120, 28)
    importBtn:SetPoint("TOPLEFT", 20, -145)
    importBtn:SetText("Importieren")

    importBtn:SetScript("OnClick", function()
      local str = editBox:GetText()
      str = str:match("^%s*(.-)%s*$") -- trim whitespace

      if str == "" then
        statusText:SetText("|cffff4444Kein Text eingegeben.|r")
        return
      end

      statusText:SetText("|cffffff00Importiere...|r")

      -- Import ausführen
      MyLoot.ImportString(str)

      -- Status aus dem Ergebnis setzen
      local raid = MyLootDB.raid
      if raid and raid.importedAt then
        local playerCount = 0
        for _ in pairs(raid.prioData or {}) do playerCount = playerCount + 1 end
        local itemCount = 0
        for _ in pairs(raid.itemPrioData or {}) do itemCount = itemCount + 1 end

        statusText:SetText(
          "|cff00ff00Import erfolgreich!|r  " ..
          raid.raidName .. " [" .. (raid.difficulty or "?") .. "]  –  " ..
          playerCount .. " Spieler, " .. itemCount .. " Items"
        )

        editBox:SetText("")
      else
        statusText:SetText("|cffff4444Import fehlgeschlagen. Format prüfen.|r")
      end
    end)

    -- Leeren Button
    local clearBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    clearBtn:SetSize(80, 28)
    clearBtn:SetPoint("LEFT", importBtn, "RIGHT", 10, 0)
    clearBtn:SetText("Leeren")
    clearBtn:SetScript("OnClick", function()
      editBox:SetText("")
      statusText:SetText("")
    end)

    ui.importFrame = f
    ui.importEditBox = editBox
  end

  ui.importFrame:Show()
end
