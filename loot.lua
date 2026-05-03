MyLoot = MyLoot or {}


-- =========================
-- LOOT HANDLING
-- =========================

-- Rolltyp-Mapping aus C_LootHistory (playerRollState → interne Bezeichnung)
local rollStateToType = { [0]="MS", [1]="MS", [2]="Transmog", [3]="OS" }

-- Debug-Modus: nur lokal sichtbar, nie im Raid-Chat
-- Toggle mit /wrtdebug
local function LootDebug(msg)
  if MyLootDB.lootDebug then
    print("|cff00ccff[WRT Debug]|r " .. msg)
  end
end
MyLoot.LootDebug = LootDebug  -- für Aufrufe aus main.lua (z.B. Timer-Callbacks)

-- Prüft ob ein Item in die Loot-Liste soll:
--   Gear (equippable, Selten+, kein Bag) ODER Rezept ODER Spielzeug
-- Gibt true zurück wenn das Item getrackt werden soll.
local function IsValidLootItem(itemLink)
  local itemID = itemLink:match("item:(%d+)")
  if not itemID then return false end

  -- Blacklist
  if WRT_BlacklistData and WRT_BlacklistData.items
     and WRT_BlacklistData.items[tonumber(itemID)] then
    LootDebug("Blacklist-Item ignoriert: " .. itemID)
    return false
  end

  local _, _, quality, _, _, itemType, _, _, equipSlot = GetItemInfo(itemLink)

  -- Rezept (z.B. Handwerksschriften von Bossen)
  if itemType == "Rezept" then return true end

  -- Spielzeug (Ruhesteine, Reittiere als Toy etc.)
  if C_ToyBox and C_ToyBox.IsToy and C_ToyBox.IsToy(tonumber(itemID)) then return true end

  -- Gear: equippable, Qualität Episch+ (4), kein Bag, kein Housing
  if itemType == "Behausung Dekoration" then
    LootDebug("Housing-Item ignoriert: " .. itemID); return false
  end
  if quality and quality < 4 then
    LootDebug("Qualität zu niedrig: " .. itemID); return false
  end
  if not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_BAG" then
    LootDebug("Nicht-Ausrüstungs-Item ignoriert: " .. itemID); return false
  end

  return true
end

-- Weist Items zu und aktualisiert Rolltypen aus C_LootHistory (MRT-Ansatz).
-- Wird via LOOT_HISTORY_UPDATE_DROP + LOOT_HISTORY_UPDATE_ENCOUNTER aufgerufen.
-- Primärquelle: dropInfo.winner.playerName/playerClass + dropInfo.itemHyperlink (mit BonusIDs)
function MyLoot.UpdateRollTypes(encounterID)
  if not C_LootHistory or not C_LootHistory.GetSortedDropsForEncounter then
    LootDebug("UpdateRollTypes: C_LootHistory API nicht verfügbar")
    return
  end
  local drops = C_LootHistory.GetSortedDropsForEncounter(encounterID)
  LootDebug("UpdateRollTypes encID=" .. tostring(encounterID) .. " drops=" .. tostring(drops and #drops or "nil"))
  if not drops then return end

  local idx, boss = MyLoot.FindBossByEncounterID(encounterID)
  LootDebug("UpdateRollTypes boss=" .. tostring(boss and boss.bossName or "NIL") .. " idx=" .. tostring(idx))
  if not boss or not boss.items then return end

  local needRender = false
  for di, dropInfo in ipairs(drops) do
    local dropLink = dropInfo.itemHyperlink
    local dropItemID = dropLink and dropLink:match("item:(%d+)")
    LootDebug(string.format("  Drop[%d] itemID=%s winner=%s rollState=%s",
      di, tostring(dropItemID),
      tostring(dropInfo.winner and dropInfo.winner.playerName or "nil"),
      tostring(dropInfo.playerRollState)))

    -- C_LootHistory bestätigt dieses Item als Gruppen-Loot → isGroupLoot setzen,
    -- unabhängig davon ob schon ein Gewinner feststeht (rollState=4 = noch am würfeln)
    if dropItemID then
      for _, loot in ipairs(boss.items) do
        local lootItemID = loot.itemLink and loot.itemLink:match("item:(%d+)")
        if lootItemID and lootItemID == dropItemID and not loot.isGroupLoot then
          loot.isGroupLoot = true
          LootDebug("  Gruppen-Loot bestätigt (kein Kriegsbeute): " .. dropItemID)
          needRender = true
        end
      end
    end

    if dropInfo.winner and dropLink then
      local winnerName  = dropInfo.winner.playerName
      local winnerClass = dropInfo.winner.playerClass

      if winnerClass then
        local shortName = winnerName:match("^([^%-]+)") or winnerName
        MyLootDB.knownClasses = MyLootDB.knownClasses or {}
        MyLootDB.knownClasses[shortName] = winnerClass
      end

      -- ItemID-basiertes Matching (BonusIDs können zwischen Slot-Erkennung und C_LootHistory abweichen)
      for _, loot in ipairs(boss.items) do
        local lootItemID = loot.itemLink and loot.itemLink:match("item:(%d+)")
        if lootItemID and lootItemID == dropItemID then
          -- Bereits einem anderen Gewinner zugeordnet → zweite Kopie suchen
          if loot.assignedTo and loot.assignedTo ~= winnerName then
            -- continue
          else
            if loot.assignedTo ~= winnerName then
              LootDebug("  Zuweisung (C_LootHistory): " .. winnerName .. " → " .. tostring(dropItemID)
                .. (loot.assignedTo and (" [überschreibt " .. loot.assignedTo .. "]") or ""))
              loot.assignedTo = winnerName
              loot.status     = "updated"
              needRender = true
            end
            -- Rolltyp kommt aus CHAT_MSG_LOOT (UpdateRollFromChat)
            -- playerRollState=5 bedeutet nur "abgeschlossen", kein Rolltyp
            break
          end
        end
      end
    end
  end

  -- Kriegsbeute-Cleanup: 10s nach dem letzten C_LootHistory-Update nicht bestätigte Items entfernen.
  -- Nur wenn C_LootHistory mindestens ein Item bestätigt hat (sonst API nicht verfügbar).
  if MyLoot._lootCleanupTimer then MyLoot._lootCleanupTimer:Cancel() end
  MyLoot._lootCleanupTimer = C_Timer.NewTimer(10, function()
    MyLoot._lootCleanupTimer = nil
    local cleanIdx, cleanBoss = MyLoot.FindBossByEncounterID(encounterID)
    if not cleanBoss or not cleanBoss.items then return end
    local anyConfirmed = false
    for _, item in ipairs(cleanBoss.items) do
      if item.isGroupLoot then anyConfirmed = true; break end
    end
    if not anyConfirmed then return end
    local removed = false
    for i = #cleanBoss.items, 1, -1 do
      if not cleanBoss.items[i].isGroupLoot then
        LootDebug("Kriegsbeute-Item entfernt: " .. (cleanBoss.items[i].itemLink and cleanBoss.items[i].itemLink:match("%[(.-)%]") or "?"))
        table.remove(cleanBoss.items, i)
        removed = true
      end
    end
    if removed then MyLoot.Render() end
  end)

  if needRender then
    MyLoot.Render()
    MyLoot.CheckAllItemsAssigned(idx)
  end
end

-- Prüft ob alle erkannten Items einen Gewinner haben → Lootzeitraum beenden
function MyLoot.CheckAllItemsAssigned(idx)
  local boss = idx and MyLootDB.raid.bosses[idx]
  if not boss or not boss.items or #boss.items == 0 then return end
  for _, item in ipairs(boss.items) do
    if not item.assignedTo then return end
  end
  MyLoot._awaitingLootAssignment = false
  LootDebug("Alle Items vergeben – Lootzeitraum beendet")
end

-- Rolltyp + Würfelzahl aus CHAT_MSG_LOOT lesen.
-- Format: "Spieler hat gewonnen (Typ - Zahl): [Item]."
function MyLoot.UpdateRollFromChat(msg)
  local playerFull, rollTypeStr, rollValue = msg:match("^(.+) hat gewonnen %((.+) %- (%d+)%): |H")
  if not playerFull then return end

  local chatItemID = msg:match("|Hitem:(%d+):")
  if not chatItemID then return end

  local player = playerFull:match("^([^%-]+)") or playerFull

  local rollType
  if rollTypeStr == "Bedarf" then rollType = "MS"
  elseif rollTypeStr == "Transmogrifikation" then rollType = "Transmog"
  elseif rollTypeStr == "Gier" or rollTypeStr == "Entzauberung" then rollType = "OS"
  end
  if not rollType then return end

  local roll = tonumber(rollValue)
  LootDebug("Chat-Roll: " .. player .. " " .. rollType .. " (" .. tostring(roll) .. ") itemID=" .. chatItemID)

  local _, boss = MyLoot.FindBossByEncounterID(MyLoot._activeEncounterID)
  if not boss or not boss.items then return end

  -- Erste Priorität: Item das bereits diesem Spieler zugewiesen ist
  for _, loot in ipairs(boss.items) do
    local lootItemID = loot.itemLink and loot.itemLink:match("item:(%d+)")
    if lootItemID == chatItemID and loot.assignedTo == player then
      loot.type = rollType
      loot.roll = roll
      MyLoot.Render()
      return
    end
  end

  -- Fallback: erstes Item gleicher ItemID ohne Rolltyp
  for _, loot in ipairs(boss.items) do
    local lootItemID = loot.itemLink and loot.itemLink:match("item:(%d+)")
    if lootItemID == chatItemID and not loot.type then
      loot.type = rollType
      loot.roll = roll
      MyLoot.Render()
      return
    end
  end
end

function MyLoot.HandleLootOpened()
  if MyLoot._isLooting then return end
  MyLoot._isLooting = true

  local idx, boss = MyLoot.FindBossByEncounterID(MyLoot._activeEncounterID)
  if not boss then
    MyLoot._isLooting = false
    return
  end

  if not boss._lootInitialized then
    boss._lootUIDCounter  = 0
    boss._lootInitialized = true
  end

  local numItems = GetNumLootItems()
  if numItems == 0 then
    MyLoot._isLooting = false
    return
  end

  -- UID-Basis: encounterID + killID + SlotIndex → eindeutig pro physischem Drop,
  -- konsistent auf allen Clients (gleiche Slots, gleiche Reihenfolge)
  local encID  = tostring(MyLoot._activeEncounterID or 0)
  local killID = tostring(boss.killID or 1)

  for i = 1, numItems do
    if LootSlotHasItem(i) then
      local texture, _, quantity, currencyID, quality = GetLootSlotInfo(i)
      if not texture then
        MyLoot._isLooting = false
        C_Timer.After(0, MyLoot.HandleLootOpened)
        return
      end
      if not currencyID and quantity and quantity > 0 and quality and quality >= 4 then
        local link = GetLootSlotLink(i)
        if link and link:find("|Hitem:") and IsValidLootItem(link) then
          local uid = encID .. "-" .. killID .. "-" .. i
          -- Duplikat-Check per UID: identisch auf allen Clients → kein Duplikat bei Sync
          local exists = false
          for _, existing in ipairs(boss.items) do
            if existing.uid == uid then exists = true; break end
          end
          if not exists then
            local itemID = link:match("item:(%d+)")
            local _, sourceName = GetLootSourceInfo(i)
            LootDebug(string.format("Slot %d (uid=%s): %s [%s]", i, uid, link:match("%[(.-)%]") or "?", sourceName or "?"))
            table.insert(boss.items, {
              uid        = uid,
              itemLink   = link,
              processed  = false,
              session    = nil,
              assignedTo = nil,
              type       = nil,
              status     = "new",
              ui         = { selectedPlayer = nil, selectedType = "MS" }
            })
          end
        end
      end
    end
  end

  MyLoot.ProcessLootTable(idx)

  C_Timer.After(1, function()
    MyLoot._isLooting = false
  end)
end


function MyLoot.ProcessLootTable(idx)
  local boss = idx and MyLootDB.raid.bosses[idx]
  if not boss then return end

  for _, loot in ipairs(boss.items) do
    if not loot.processed then
      loot.processed = true
      loot.session = (boss._sessionCounter or 0) + 1
      boss._sessionCounter = loot.session
    end
  end

  MyLoot.Render()
end
-- =========================
-- API FUNKTION
-- =========================

function MyLoot.SyncLootToServer(loot)
  local boss = MyLoot.GetSelectedBoss()
  local raidID = MyLootDB.raid.raidID or "local"

  local data = {
    raidID = raidID,
    boss = boss and boss.bossName,
    kill = boss and boss.killID,
    uid = loot.uid,
    item = loot.itemLink,
    player = loot.assignedTo,
    type = loot.type,
    session = loot.session
  }

  local json = string.format(
    '{"type":"loot_assigned","raidID":"%s","boss":"%s","uid":"%s","item":"%s","player":"%s","lootType":"%s"}',
    raidID or "",
    boss and boss.bossName or "",
    loot.uid or "",
    loot.itemLink or "",
    loot.assignedTo or "",
    loot.type or ""
  )

end


-- =========================
-- DROPDOWN (SPIELER)
-- =========================

local function GetRaidMembers()
  local members = {}

  if IsInRaid() then
    for i = 1, GetNumGroupMembers() do
      local name = select(1, GetRaidRosterInfo(i))
      if name then members[#members + 1] = name end
    end

  elseif IsInGroup() then
    for i = 1, GetNumGroupMembers() - 1 do
      local name = UnitName("party"..i)
      if name then members[#members + 1] = name end
    end

    members[#members + 1] = UnitName("player")

  else
    members[#members + 1] = UnitName("player")
    members[#members + 1] = "Test1"
    members[#members + 1] = "Test2"
  end

  return members
end

local playerDropdown = CreateFrame("Frame", "MyLootPlayerDropdown", UIParent, "UIDropDownMenuTemplate")
UIDropDownMenu_SetDisplayMode(playerDropdown, "MENU")

function MyLoot.ShowWinnerDropdown(index, anchor)

  local members = GetRaidMembers()

  UIDropDownMenu_Initialize(playerDropdown, function(self, level)
    for _, name in ipairs(members) do
      local info = UIDropDownMenu_CreateInfo()

      info.text = name

      info.func = function()
        local boss = MyLoot.GetSelectedBoss()
        local loot = boss.items[index]

        loot.ui = loot.ui or {}
        loot.ui.selectedPlayer = name

        MyLoot.Render()
      end

      UIDropDownMenu_AddButton(info)
    end
  end)

  ToggleDropDownMenu(1, nil, playerDropdown, anchor, 0, 0)
end

-- =========================
-- RENDER LOOT LISTE
-- =========================

-- Gibt den hex-Farbstring einer Klasse für einen Spielernamen zurück.
-- Durchsucht Raid/Party per Unit-Token; cached das Ergebnis in knownClasses.
local function GetClassColorStr(playerName)
  if not playerName then return "ffffffff" end

  MyLootDB.knownClasses = MyLootDB.knownClasses or {}

  -- Kurzname für Cache-Lookup (ohne Realm-Suffix)
  local shortName = playerName:match("^([^%-]+)") or playerName

  -- Cache prüfen
  local cached = MyLootDB.knownClasses[shortName] or MyLootDB.knownClasses[playerName]
  if cached and RAID_CLASS_COLORS[cached] then
    return RAID_CLASS_COLORS[cached].colorStr
  end

  -- Live-Lookup über Raid-Roster
  local maxMembers = IsInRaid() and 40 or (IsInGroup() and GetNumGroupMembers() or 1)
  local prefix     = IsInRaid() and "raid" or "party"
  for i = 1, maxMembers do
    local unit = (i == maxMembers and not IsInRaid()) and "player" or (prefix .. i)
    local unitShort = UnitName(unit)
    if unitShort and (unitShort == shortName or unitShort == playerName) then
      local _, classKey = UnitClass(unit)
      if classKey then
        MyLootDB.knownClasses[shortName] = classKey
        if RAID_CLASS_COLORS[classKey] then
          return RAID_CLASS_COLORS[classKey].colorStr
        end
      end
    end
  end
  -- Eigenen Charakter prüfen
  if UnitName("player") == shortName then
    local _, classKey = UnitClass("player")
    if classKey and RAID_CLASS_COLORS[classKey] then
      MyLootDB.knownClasses[shortName] = classKey
      return RAID_CLASS_COLORS[classKey].colorStr
    end
  end

  return "ffffffff"
end

function MyLoot.RenderLoot()
  local ui     = MyLoot.UI
  local y      = -10
  local isLead = MyLootDB.role == "raidlead"

  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  for _, loot in ipairs(boss.items) do
    local itemLink = loot.itemLink
    if not itemLink or not itemLink:find("|Hitem:") then end
    if itemLink and itemLink:find("|Hitem:") then

      -- Item-Daten
      local name, _, _, _, _, _, _, _, _, texture = GetItemInfo(itemLink)
      if not name then
        local item = Item:CreateFromItemLink(itemLink)
        if not item:IsItemDataCached() then
          item:ContinueOnItemLoad(function() MyLoot.Render() end)
        end
        name = itemLink:match("%[(.-)%]") or "Item"
      end

      -- Item Button
      local btn = CreateFrame("Button", nil, ui.bottomPanel, "BackdropTemplate")
      btn:SetSize(280, 26)
      btn:SetPoint("TOPLEFT", 0, y)
      btn:EnableMouse(true)
      btn:RegisterForClicks("LeftButtonUp")
      btn:SetBackdrop({ bgFile = "Interface/Tooltips/UI-Tooltip-Background", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", edgeSize = 8 })

      local function UpdateColor(self, hover)
        if MyLootDB.activeItem == itemLink then
          self:SetBackdropColor(0.4, 0.35, 0.1, 0.9)
        elseif loot.assignedTo then
          self:SetBackdropColor(0, 0.35, 0, 0.7)
        elseif hover then
          self:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
        else
          self:SetBackdropColor(0, 0, 0, 0.3)
        end
      end
      UpdateColor(btn, false)

      local icon = btn:CreateTexture(nil, "ARTWORK")
      icon:SetSize(20, 20)
      icon:SetPoint("LEFT", 5, 0)
      if texture then icon:SetTexture(texture) end

      local nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      nameText:SetPoint("LEFT", 30, 0)
      nameText:SetPoint("RIGHT", -5, 0)
      nameText:SetJustifyH("LEFT")
      nameText:SetWordWrap(false)
      nameText:SetText(name)

      btn:SetScript("OnClick", function()
        MyLootDB.activeItem = itemLink
        MyLoot.Render()
      end)
      btn:SetScript("OnEnter", function(self)
        UpdateColor(self, true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetHyperlink(itemLink)
        GameTooltip:Show()
      end)
      btn:SetScript("OnLeave", function(self)
        UpdateColor(self, false)
        GameTooltip:Hide()
      end)

      -- Vergabe-Anzeige (rechts neben Item)
      local infoFrame = CreateFrame("Frame", nil, ui.bottomPanel)
      infoFrame:SetSize(300, 26)
      infoFrame:SetPoint("LEFT", btn, "RIGHT", 8, 0)

      if loot.assignedTo then
        -- Gewinner aus Chat erkannt
        local colorStr = GetClassColorStr(loot.assignedTo)

        local assignTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        assignTxt:SetPoint("LEFT", 0, 0)
        assignTxt:SetText("|c" .. colorStr .. loot.assignedTo .. "|r")

        if loot.type then
          local typeLabels = { MS = "Bedarf", OS = "Gier", DE = "Transmog", Transmog = "Transmog" }
          local label = typeLabels[loot.type] or loot.type
          -- Primär/Sekundär Spezialisierung ergänzen
          if loot.spec then
            label = label .. " (" .. loot.spec .. ")"
          end
          -- Würfelzahl als Funfact
          if loot.roll then
            label = label .. "  " .. loot.roll
          end
          local typeTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
          typeTxt:SetPoint("LEFT", 140, 0)
          typeTxt:SetTextColor(1, 0.82, 0)
          typeTxt:SetText(label)
        end


      else
        -- Noch nicht vergeben
        local waitTxt = infoFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        waitTxt:SetPoint("LEFT", 0, 0)
        waitTxt:SetText("—")
      end

      y = y - 32
    end
  end
end

function MyLoot.HandleSyncMessage(msg, sender)
  local playerName = UnitName("player")
  if sender == playerName .. "-" .. GetNormalizedRealmName() then return end

  local cmd, rest = msg:match("^([^:]+):(.+)$")
  if not cmd then cmd = msg end

  if cmd == "HELLO" then
    local senderShort = sender:match("^([^%-]+)") or sender
    MyLoot._addonUsers[senderShort] = rest
    if not MyLoot._outdatedNotified
       and MyLoot.IsVersionNewer and MyLoot.IsVersionNewer(rest, MyLoot.VERSION or "0")
    then
      MyLoot._outdatedNotified = true
      print("|cff00ccff[WRT]|r |cffff4444Dein Addon ist veraltet|r (v"
         .. (MyLoot.VERSION or "?") .. "). Bitte update auf |cff00ff00v" .. rest .. "|r.")
    end
    if MyLoot._versionWindow and MyLoot._versionWindow:IsShown() then
      MyLoot.RefreshVersionWindow()
    end
  elseif cmd == "HELLO_REQUEST" then
    C_Timer.After(math.random() * 2, MyLoot.BroadcastHello)
  end
end