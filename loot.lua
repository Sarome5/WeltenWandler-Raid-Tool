MyLoot = MyLoot or {}

-- =========================
-- SEND HELPER
-- =========================
local function Send(msg)
  C_ChatInfo.SendAddonMessage("MYLOOT", msg, "RAID")
end

MyLoot._msgQueue = MyLoot._msgQueue or {}
MyLoot._sending = false
MyLoot._clientBuffer = {}

function MyLoot.QueueMessage(prefix, msg, channel, target)
  table.insert(MyLoot._msgQueue, {
    prefix = prefix,
    msg = msg,
    channel = channel,
    target = target
  })

  MyLoot.ProcessQueue()
end

function MyLoot.ProcessQueue()
  if MyLoot._sending then return end
  if #MyLoot._msgQueue == 0 then return end

  MyLoot._sending = true

  local data = table.remove(MyLoot._msgQueue, 1)

  if data.target then
    C_ChatInfo.SendAddonMessage(data.prefix, data.msg, data.channel, data.target)
  else
    C_ChatInfo.SendAddonMessage(data.prefix, data.msg, data.channel)
  end

  C_Timer.After(0.05, function()
    MyLoot._sending = false
    MyLoot.ProcessQueue()
  end)
end

function MyLoot.AddItem(itemLink)
  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  -- ID GENERIERUNG
  boss._sessionCounter = (boss._sessionCounter or 0) + 1
  local session = boss._sessionCounter


  local itemID = itemLink:match("item:(%d+)")
  local uid = itemID .. "-" .. session

  local loot = {
    uid = uid,
    session = session,
    itemLink = itemLink,
    assignedTo = nil,
    type = nil,
    status = "new",
    ui = {
      selectedPlayer = nil,
      selectedType = "MS"
    }
  }

  table.insert(boss.items, loot)

  -- SYNC + PRIO
  MyLoot.SendNewItem(loot)

  return loot
end


function MyLoot.SendClientLoot(link, uid)
  local encoded = link:gsub(":", ";"):gsub("|", "!")

  if not uid then
    return
  end

  local msg = "CLIENT_LOOT:" .. uid .. ":" .. encoded
  MyLoot.QueueMessage("MYLOOT_SYNC", msg, "RAID")
end

-- =========================
-- LOOT HANDLING
-- =========================

-- Erkennt Loot-Vergaben aus dem deutschen WoW-Chat
-- Unterstützte Muster:
--   "[Spieler] gewinnt [Item]. (Bedarf)"   → MS
--   "[Spieler] gewinnt [Item]. (Gier)"     → OS
--   "[Spieler] gewinnt [Item]. (Transmog)" → Transmog
--   "[Item] geht an [Spieler]."            → MS (Master Looter)
--   "Du hast geplündert: [Item]."          → eigener Loot

local LOOT_TYPE_MAP = {
  ["Bedarf"]                    = "MS",
  ["Primäre Spezialisierung"]   = "MS",
  ["Gier"]                      = "OS",
  ["Sekundäre Spezialisierung"] = "OS",
  ["Transmog"]                  = "Transmog",
  ["Aussehen"]                  = "Transmog",
}

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

  -- Gear: equippable, Qualität Selten+ (3), kein Bag, kein Housing
  if itemType == "Behausung Dekoration" then
    LootDebug("Housing-Item ignoriert: " .. itemID); return false
  end
  if quality and quality < 3 then
    LootDebug("Qualität zu niedrig: " .. itemID); return false
  end
  if not equipSlot or equipSlot == "" or equipSlot == "INVTYPE_BAG" then
    LootDebug("Nicht-Ausrüstungs-Item ignoriert: " .. itemID); return false
  end

  return true
end

-- Fügt ein Item aus dem Group-Loot-Chat zu boss.items hinzu
function MyLoot.TryAddGroupLootItem(itemLink)
  local idx  = MyLoot._activeLootBossIndex or MyLootDB.selectedBossIndex
  local boss = idx and MyLootDB.raid.bosses[idx]
  if not boss then return end

  local itemID = itemLink:match("item:(%d+)")
  if not itemID then return end

  if not IsValidLootItem(itemLink) then return end

  -- Kein Duplikat-Check: Chat feuert exakt einmal pro physischem Drop.
  -- Mehrfachdrops (auch gleicher Hitem) werden korrekt als separate Einträge getrackt.

  boss._lootUIDCounter = (boss._lootUIDCounter or 0) + 1
  local uid = itemID .. "-" .. boss._lootUIDCounter

  table.insert(boss.items, {
    uid        = uid,
    itemLink   = itemLink,
    assignedTo = nil,
    type       = nil,
    status     = "new",
    processed  = true,
    ui         = { selectedPlayer = nil, selectedType = "MS" }
  })

  LootDebug("Group Loot Item hinzugefügt: " .. itemID)
  MyLoot.Render()
end

-- Entfernt den Chat-Kanal-Präfix aus einem Spielernamen
-- (WoW sendet "[Beute]: " manchmal als Hyperlink: |Hchannel:...|h[Beute]|h)
local function StripChannelPrefix(str)
  if not str then return str end
  str = str:gsub("^|c%x+", "")                      -- führender Farbcode
  str = str:gsub("^|H[^|]*|h%[.-%]|h|r?:%s*", "")  -- Hyperlink-Format
  str = str:gsub("^%[[^%]]+%]:%s*", "")             -- Klartext-Format [Kanal]:
  return str:match("^%s*(.-)%s*$")                   -- Whitespace trimmen
end

function MyLoot.TryAutoAssignFromChat(msg)
  local canDetect = MyLoot._awaitingItemDetection
  local canAssign = MyLoot._awaitingLootAssignment
  if not canDetect and not canAssign then return end

  LootDebug("Chat: " .. msg)

  local itemLink = msg:match("|Hitem:.-|h.-|h")
  if not itemLink then
    LootDebug("Kein Item-Link gefunden → ignoriert")
    return
  end

  -- Group Loot: reiner Item-Drop nur wenn [Beute]: Prefix vorhanden
  -- und kein Gewinner/Gepasst dahinter steht
  local hasBeutePrefix = msg:find("%[Beute%]") or msg:find("|h%[Beute%]|h")
  local isBareDrop = hasBeutePrefix
                 and not msg:find("hat gewonnen")
                 and not msg:find("habt gewonnen")  -- eigener Charakter gewinnt
                 and not msg:find("hat gepasst")    -- anderer Spieler passt
                 and not msg:find("habt gepasst")   -- eigener Charakter passt
                 and not msg:find("Beuteverteilung")
  if isBareDrop then
    if canDetect then MyLoot.TryAddGroupLootItem(itemLink) end
    return
  end

  if not canAssign then return end

  local player    = nil
  local lootType  = "MS"
  local _lastRoll = nil
  local _lastSpec = nil

  -- Nur "hat/habt gewonnen" für Zuweisung nutzen.
  -- "erhält/bekommt Beute" sind Lieferbestätigungen und kommen nach dem Würfelergebnis –
  -- bei Mehrfachdrops würden sie das zweite Item fälschlich dem ersten Gewinner zuweisen.

  -- Muster 3a: "Ihr habt gewonnen (...): [Item]" → eigener Charakter
  if msg:find("habt gewonnen") then
    player = UnitName("player")
    local inner = msg:match("habt gewonnen %((.-)%)")
    if inner then
      local rollNum = inner:match("%- (%d+)")
      _lastRoll = rollNum and tonumber(rollNum) or nil
      for key, val in pairs(LOOT_TYPE_MAP) do
        if inner:find(key, 1, true) then lootType = val; break end
      end
      if inner:find("Primäre Spezialisierung", 1, true) then
        _lastSpec = "Primär"
      elseif inner:find("Sekundäre Spezialisierung", 1, true) then
        _lastSpec = "Sekundär"
      end
    end
    LootDebug("Muster 3a (Selbst gewonnen): " .. player .. " → " .. lootType .. " Roll:" .. tostring(_lastRoll))

  -- Muster 3b: "[Spieler] hat gewonnen (Bedarf - 98, Sekundäre Spezialisierung): [Item]"
  elseif msg:find("hat gewonnen") then
    local winner = msg:match("(.+) hat gewonnen %(")
    if winner then
      player = StripChannelPrefix(winner)
      local inner = msg:match("hat gewonnen %((.-)%)")
      if inner then
        -- Würfelzahl extrahieren (Format: "Bedarf - 98" oder "Gier - 42")
        local rollNum = inner:match("%- (%d+)")
        if rollNum then
          _lastRoll = tonumber(rollNum)
        else
          _lastRoll = nil
        end
        -- Loot-Typ bestimmen
        for key, val in pairs(LOOT_TYPE_MAP) do
          if inner:find(key, 1, true) then
            lootType = val
            break
          end
        end
        -- Primär/Sekundär Spezialisierung separat merken
        if inner:find("Primäre Spezialisierung", 1, true) then
          _lastSpec = "Primär"
        elseif inner:find("Sekundäre Spezialisierung", 1, true) then
          _lastSpec = "Sekundär"
        else
          _lastSpec = nil
        end
      end
      LootDebug("Muster 3b (Würfel): " .. tostring(player) .. " → " .. lootType .. " Roll:" .. tostring(_lastRoll))
    else
      LootDebug("Kein Muster erkannt für: " .. msg)
    end

  else
    LootDebug("Kein Muster erkannt für: " .. msg)
  end

  if not player or player == "" then return end

  -- Sicherheits-Strip: [Kanal]: Prefix entfernen falls StripChannelPrefix es nicht erwischt hat
  player = player:gsub("^|c%x+", "")               -- führender Farbcode
  player = player:gsub("^|H[^|]*|h%[.-%]|h|r?:%s*", "")  -- Hyperlink-Kanalformat
  player = player:gsub("^%[.-%]:%s*", "")          -- Klartext [Kanal]:
  player = player:match("^%s*(.-)%s*$")            -- Whitespace trimmen
  if not player or player == "" then return end

  -- Vollständigen Hitem-String extrahieren (inkl. BonusIDs)
  local chatItemString = itemLink:match("Hitem:([^|]+)")
  local chatItemID     = itemLink:match("item:(%d+)")
  if not chatItemID then return end

  -- Blacklist-Prüfung: Item ignorieren wenn auf der Blacklist
  local isBlacklisted = WRT_BlacklistData and WRT_BlacklistData.items
                     and WRT_BlacklistData.items[tonumber(chatItemID)]
  if isBlacklisted then
    LootDebug("Blacklist-Item ignoriert: " .. chatItemID)
    return
  end

  local assigned = false

  -- Schritt 1: exakter Match auf Hitem-String (BonusID-sicher)
  -- Nur "new"-Items matchen: "updated" (bereits tentativ zugewiesen) überspringen,
  -- damit bei Mehrfachdrops des gleichen Items jede Kopie ihren eigenen Gewinner bekommt.
  for _, boss in ipairs(MyLootDB.raid.bosses) do
    for _, loot in ipairs(boss.items) do
      if loot.status == "new" and loot.itemLink then
        local lootItemString = loot.itemLink:match("Hitem:([^|]+)")
        if lootItemString == chatItemString then
          loot.assignedTo = player
          loot.type       = lootType
          loot.roll       = _lastRoll
          loot.spec       = _lastSpec
          loot.status     = "updated"
          assigned = true
          break
        end
      end
    end
    if assigned then break end
  end

  -- Schritt 2: Fallback auf Base-ItemID (falls BonusID-String abweicht)
  -- Nur wenn die ItemID unter den "new"-Items eindeutig ist – bei Duplikaten lieber nicht raten
  if not assigned then
    local matchCount = 0
    for _, boss in ipairs(MyLootDB.raid.bosses) do
      for _, loot in ipairs(boss.items) do
        if loot.status == "new" and loot.itemLink then
          if loot.itemLink:match("item:(%d+)") == chatItemID then
            matchCount = matchCount + 1
          end
        end
      end
    end

    if matchCount == 1 then
      for _, boss in ipairs(MyLootDB.raid.bosses) do
        for _, loot in ipairs(boss.items) do
          if loot.status == "new" and loot.itemLink then
            if loot.itemLink:match("item:(%d+)") == chatItemID then
              loot.assignedTo = player
              loot.type       = lootType
              loot.roll       = _lastRoll
              loot.spec       = _lastSpec
              loot.status     = "updated"
              assigned = true
              break
            end
          end
        end
        if assigned then break end
      end
    else
      LootDebug("Schritt 2 übersprungen: " .. matchCount .. "x ItemID " .. chatItemID .. " → mehrdeutig")
    end
  end

  MyLoot.Render()
  MyLoot.CheckAllItemsAssigned()
end

function MyLoot.SendNewItem(loot)
  local bossIndex = MyLootDB.selectedBossIndex or 1
  local encoded = loot.itemLink:gsub(":", ";")
  local boss = MyLoot.GetSelectedBoss()
  local raidID = MyLootDB.raid.raidID or "local"

  local globalUID = raidID .. "-" .. bossIndex .. "-" .. (boss.killID or 1) .. "-" .. loot.uid

  local msg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. globalUID .. ":" .. encoded

  MyLoot.QueueMessage("MYLOOT_SYNC", msg, "RAID")

end

-- Prüft ob alle erkannten Items einen Gewinner haben → Lootzeitraum beenden
function MyLoot.CheckAllItemsAssigned()
  local idx  = MyLoot._activeLootBossIndex or MyLootDB.selectedBossIndex
  local boss = idx and MyLootDB.raid.bosses[idx]
  if not boss or not boss.items or #boss.items == 0 then return end
  for _, item in ipairs(boss.items) do
    if not item.assignedTo then return end
  end
  MyLoot._awaitingLootAssignment = false
  LootDebug("Alle Items vergeben – Lootzeitraum beendet")
end

function MyLoot.HandleLoot(msg)
  MyLoot.TryAutoAssignFromChat(msg)
end

function MyLoot.HandleLootOpened()
  if MyLoot._isLooting then return end
  MyLoot._isLooting = true

  -- Aktiven Loot-Boss nutzen (eingefroren bei ENCOUNTER_END), nicht den Dropdown-Stand
  local idx  = MyLoot._activeLootBossIndex or MyLootDB.selectedBossIndex
  local boss = idx and MyLootDB.raid.bosses[idx]
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

  -- Schritt 1: Gültige Items aus Slots sammeln
  local slotItems = {}  -- { link, hitem, itemID }
  for i = 1, numItems do
    if LootSlotHasItem(i) then
      local texture, _, quantity, currencyID, quality = GetLootSlotInfo(i)
      if not texture then
        -- Slot noch nicht gerendert → nächsten Frame neu versuchen
        MyLoot._isLooting = false
        C_Timer.After(0, MyLoot.HandleLootOpened)
        return
      end
      if not currencyID and quantity and quantity > 0 and quality and quality >= 3 then
        local link = GetLootSlotLink(i)
        if link and link:find("|Hitem:") then
          local _, sourceName = GetLootSourceInfo(i)
          LootDebug(string.format("Slot %d: %s [Quelle: %s]", i, link:match("%[(.-)%]") or "?", sourceName or "?"))
          local itemID = link:match("item:(%d+)")
          local skip = not IsValidLootItem(link)
          if not skip then
            table.insert(slotItems, {
              link   = link,
              hitem  = link:match("Hitem:([^|]+)"),
              itemID = itemID,
            })
          end
        end
      end
    end
  end

  -- Schritt 2: Anzahl pro Hitem in Slots zählen
  local slotCounts = {}
  for _, s in ipairs(slotItems) do
    slotCounts[s.hitem] = (slotCounts[s.hitem] or 0) + 1
  end

  -- Schritt 3: Anzahl pro Hitem bereits in boss.items zählen (alle Statuses)
  local existingCounts = {}
  for _, existing in ipairs(boss.items) do
    if existing.itemLink then
      local h = existing.itemLink:match("Hitem:([^|]+)")
      if h then existingCounts[h] = (existingCounts[h] or 0) + 1 end
    end
  end

  -- Schritt 4: Fehlende Items ergänzen (Slot-Anzahl - vorhandene Anzahl)
  -- Speichert einen Link-Vertreter pro Hitem für die Eintragserstellung
  local linkByHitem = {}
  for _, s in ipairs(slotItems) do
    linkByHitem[s.hitem] = linkByHitem[s.hitem] or s
  end

  for hitem, slotCount in pairs(slotCounts) do
    local missing = slotCount - (existingCounts[hitem] or 0)
    if missing > 0 then
      local s = linkByHitem[hitem]
      for _ = 1, missing do
        boss._lootUIDCounter = (boss._lootUIDCounter or 0) + 1
        local uid = s.itemID .. "-" .. boss._lootUIDCounter
        table.insert(boss.items, {
          uid        = uid,
          itemLink   = s.link,
          processed  = false,
          session    = nil,
          assignedTo = nil,
          type       = nil,
          status     = "new",
          ui         = { selectedPlayer = nil, selectedType = "MS" }
        })
        LootDebug("LootOpened Fallback hinzugefügt: " .. s.itemID)
      end
    end
  end

  MyLoot.ProcessLootTable()

  C_Timer.After(1, function()
    MyLoot._isLooting = false
  end)
end


function MyLoot.ProcessLootTable()
  local boss = MyLoot.GetSelectedBoss()
  if not boss then return end

  for _, loot in ipairs(boss.items) do
    if not loot.processed then

      if MyLootDB.role == "raidlead" then
        loot.processed = true

        loot.session = (boss._sessionCounter or 0) + 1
        boss._sessionCounter = loot.session

        if not loot.uid then
          local itemID = loot.itemLink:match("item:(%d+)")
          loot.uid = itemID .. "-" .. loot.session
        end

        MyLoot.SendNewItem(loot)

      else
        if not loot.session then
          loot.processed = true
          MyLoot.SendClientLoot(loot.itemLink, loot.uid)
        end
      end

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

  -- =========================
  -- JOIN SYNC REQUEST
  -- =========================
  if msg == "REQUEST_SYNC" then
    if MyLootDB.role ~= "raidlead" then return end

    for bossIndex, boss in ipairs(MyLootDB.raid.bosses) do
      -- Boss-Info vorab senden: Empfänger kann damit richtig matchen/erstellen
      local bossInfoMsg = "SYNC_BOSS:" .. bossIndex .. ":" .. (boss.bossName or "") .. ":" .. (boss.difficulty or "")
      MyLoot.QueueMessage("MYLOOT_SYNC", bossInfoMsg, "WHISPER", sender)

      for _, loot in ipairs(boss.items) do
        local encoded = loot.itemLink:gsub(":", ";")
        local raidID = MyLootDB.raid.raidID or "local"
        local globalUID = raidID .. "-" .. bossIndex .. "-" .. (boss.killID or 1) .. "-" .. loot.uid

        local newMsg = "LOOT_NEW:" .. bossIndex .. ":" .. loot.session .. ":" .. globalUID .. ":" .. encoded
        MyLoot.QueueMessage("MYLOOT_SYNC", newMsg, "WHISPER", sender)

        local syncMsg = "LOOT_SYNC:" .. bossIndex .. ":" .. loot.session .. ":" .. (loot.assignedTo or "nil") .. ":" .. (loot.type or "nil")
        MyLoot.QueueMessage("MYLOOT_SYNC", syncMsg, "WHISPER", sender)
      end
    end

    return
  end

  -- eigene Nachrichten ignorieren
  local playerName = UnitName("player")
  local fullPlayerName = playerName .. "-" .. GetNormalizedRealmName()

  if sender == fullPlayerName then return end
  local cmd, rest = msg:match("^([^:]+):(.+)$")

  if not cmd then
    cmd = msg
  end

  if cmd == "SYNC_BOSS" then
    -- Format: SYNC_BOSS:remoteBossIndex:bossName:difficulty
    -- Baut eine Mapping-Tabelle remoteBossIndex → lokalem Boss-Index auf,
    -- damit LOOT_NEW/LOOT_SYNC den richtigen Boss treffen.
    local remoteBossIndex, bossName, difficulty = rest:match("^(%d+):(.+):(.-)$")
    remoteBossIndex = tonumber(remoteBossIndex)
    if not remoteBossIndex then return end

    MyLoot._syncBossMap = MyLoot._syncBossMap or {}

    -- Vorhandenen Boss per Name+Schwierigkeit suchen
    local localIndex = nil
    for i, b in ipairs(MyLootDB.raid.bosses) do
      if b.bossName == bossName and (b.difficulty or "") == (difficulty or "") then
        localIndex = i
        break
      end
    end

    -- Nicht gefunden → neu anlegen mit echtem Namen
    if not localIndex then
      local newBoss = {
        bossName   = bossName,
        difficulty = difficulty ~= "" and difficulty or nil,
        items      = {},
        killID     = 1,
      }
      table.insert(MyLootDB.raid.bosses, newBoss)
      localIndex = #MyLootDB.raid.bosses
    end

    MyLoot._syncBossMap[remoteBossIndex] = localIndex
    return

  elseif cmd == "LOOT_NEW" then
    local bossIndex, session, uid, itemLink = rest:match("^(%d+):(%d+):([^:]+):(.+)$")

    if not itemLink then
      bossIndex, session, itemLink = rest:match("^(%d+):(%d+):(.+)$")
      uid = "fallback-" .. session
    end
    itemLink = itemLink:gsub(";", ":")
    session = tonumber(session)
    bossIndex = tonumber(bossIndex)

    -- Mapping aus SYNC_BOSS nutzen wenn vorhanden, sonst direkter Index
    local localIndex = (MyLoot._syncBossMap and MyLoot._syncBossMap[bossIndex]) or bossIndex
    local boss = MyLootDB.raid.bosses[localIndex]

    if not boss then
      -- Fallback: Platzhalter (sollte durch SYNC_BOSS eigentlich nicht mehr vorkommen)
      boss = {
        bossName = "Boss " .. bossIndex,
        items = {}
      }
      table.insert(MyLootDB.raid.bosses, boss)
      localIndex = #MyLootDB.raid.bosses
    end

    -- Reconciliation: chat-getrackte Items (status="new", kein session) mit Sync-Daten abgleichen
    -- Mehrfachdrops: jeder LOOT_NEW reconciliert genau einen noch nicht abgeglichenen Eintrag
    local syncHitem = itemLink:match("Hitem:([^|]+)")
    local reconciled = false
    for _, l in ipairs(boss.items) do
      if l.uid == uid then
        reconciled = true; break  -- bereits bekannt
      end
      if syncHitem and l.itemLink
         and l.itemLink:match("Hitem:([^|]+)") == syncHitem
         and not l.session then
        -- Chat-getracks Item gefunden → Session + UID aktualisieren
        l.uid     = uid
        l.session = session
        l.status  = "synced"
        reconciled = true
        break
      end
    end

    if not reconciled then
      -- DC/Join-Szenario: Item war nicht im Chat → neu anlegen
      table.insert(boss.items, {
        uid = uid,
        session = session,
        itemLink = itemLink,
        assignedTo = nil,
        type = nil,
        status = "synced",
        processed = true,
        ui = {
          selectedPlayer = nil,
          selectedType = "MS"
        }
      })
    end

  elseif cmd == "CLIENT_LOOT" then
    if MyLootDB.role ~= "raidlead" then return end


    local uid, encoded = rest:match("^([^:]+):(.+)$")
    local itemLink = encoded:gsub("!", "|"):gsub(";", ":")

    local boss = MyLoot.GetSelectedBoss()
    boss._clientBuffer = boss._clientBuffer or {}

    table.insert(boss._clientBuffer, {
      uid = uid,
      itemLink = itemLink
    })


  elseif cmd == "CLIENT_DONE" then
    if MyLootDB.role ~= "raidlead" then return end


    local boss = MyLoot.GetSelectedBoss()
    if not boss then return end

    for _, data in ipairs(boss._clientBuffer or {}) do
      local uid = data.uid
      local itemLink = data.itemLink

      local exists = false
      for _, existing in ipairs(boss.items) do
        if existing.uid == uid then
          exists = true
          break
        end
      end

      if not exists then
        table.insert(boss.items, {
          uid = uid,
          itemLink = itemLink,
          slot = -1,
          processed = false,
          session = nil,
          assignedTo = nil,
          type = nil,
          status = "new",
          ui = {
            selectedPlayer = nil,
            selectedType = "MS"
          }
        })
      end
    end
    boss._clientBuffer = {}
    MyLoot._clientBuffer = {}
    MyLoot.ProcessLootTable()


  elseif cmd == "LOOT_SYNC" then
    -- Neues Format: bossIndex:session:player:type
    -- Altes Format (Fallback): session:player:type
    local p1, p2, p3, p4 = strsplit(":", rest)
    local bossIndex, session, player, lootType
    if p4 then
      -- neues Format mit bossIndex
      bossIndex = tonumber(p1)
      session   = tonumber(p2)
      player    = p3
      lootType  = p4
    else
      -- altes Format ohne bossIndex (Abwärtskompatibilität)
      bossIndex = nil
      session   = tonumber(p1)
      player    = p2
      lootType  = p3
    end

    if bossIndex then
      -- Mapping aus SYNC_BOSS nutzen wenn vorhanden, sonst direkter Index
      local localIndex = (MyLoot._syncBossMap and MyLoot._syncBossMap[bossIndex]) or bossIndex
      local boss = MyLootDB.raid.bosses[localIndex]
      if boss then
        for _, loot in ipairs(boss.items) do
          if loot.session == session then
            loot.assignedTo = (player ~= "nil") and player or nil
            loot.type       = (lootType ~= "nil") and lootType or nil
            loot.status     = "synced"
            break
          end
        end
      end
    else
      -- Fallback: ersten Treffer über alle Bosse (altes Protokoll)
      local found = false
      for _, boss in ipairs(MyLootDB.raid.bosses) do
        if found then break end
        for _, loot in ipairs(boss.items) do
          if loot.session == session then
            loot.assignedTo = (player ~= "nil") and player or nil
            loot.type       = (lootType ~= "nil") and lootType or nil
            loot.status     = "synced"
            found = true
            break
          end
        end
      end
    end
  elseif cmd == "HELLO" then
    -- rest = Versions-String des Senders
    -- Realm-Suffix entfernen für lokale Tabelle (Gilde = keine Namenskollisionen)
    local senderShort = sender:match("^([^%-]+)") or sender
    MyLoot._addonUsers[senderShort] = rest

    -- Eigene Version vergleichen: bin ich veraltet?
    if not MyLoot._outdatedNotified
       and MyLoot.IsVersionNewer and MyLoot.IsVersionNewer(rest, MyLoot.VERSION or "0")
    then
      MyLoot._outdatedNotified = true
      print("|cff00ccff[WRT]|r |cffff4444Dein Addon ist veraltet|r (v"
         .. (MyLoot.VERSION or "?") .. "). Bitte update auf |cff00ff00v" .. rest .. "|r.")
    end

    -- Versionsfenster aktualisieren falls geöffnet
    if MyLoot._versionWindow and MyLoot._versionWindow:IsShown() then
      MyLoot.RefreshVersionWindow()
    end
    return  -- kein Render nötig

  elseif cmd == "HELLO_REQUEST" then
    -- Jemand fragt nach unserer Version → nach kurzem Zufalls-Delay antworten
    -- (verhindert dass alle 30 Spieler gleichzeitig antworten)
    C_Timer.After(math.random() * 2, MyLoot.BroadcastHello)
    return
  end

  MyLoot.Render()
end