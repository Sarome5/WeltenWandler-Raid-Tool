local Dropdown = {}

local MAX_HEIGHT = 220 -- max sichtbare Höhe in Pixeln
local ITEM_HEIGHT = 22

function Dropdown:Create(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(200, 10)
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
    })

    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(1000)
    f:Hide()

    -- ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", nil, f)
    scrollFrame:SetPoint("TOPLEFT", 5, -5)
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(180)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    f.scrollFrame = scrollFrame
    f.scrollChild = scrollChild
    f.buttons = {}

    -- Mausrad-Scroll
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta)
        local current = scrollFrame:GetVerticalScroll()
        scrollFrame:SetVerticalScroll(math.max(0, current - delta * ITEM_HEIGHT))
    end)

    function f:SetItems(items, onClick)
        -- alte Buttons löschen
        for _, b in ipairs(self.buttons) do
            b:Hide()
        end
        wipe(self.buttons)

        local totalHeight = 0

        for i, item in ipairs(items) do
            local btn = CreateFrame("Button", nil, scrollChild)
            btn:SetSize(180, 20)
            btn:SetPoint("TOPLEFT", 0, -(i - 1) * ITEM_HEIGHT)

            local bg = btn:CreateTexture(nil, "BACKGROUND")
            bg:SetAllPoints()
            bg:SetColorTexture(1, 1, 1, 0)
            btn.bg = bg

            btn:SetScript("OnEnter", function() bg:SetColorTexture(1, 1, 1, 0.1) end)
            btn:SetScript("OnLeave", function() bg:SetColorTexture(1, 1, 1, 0) end)

            local text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            text:SetPoint("LEFT", 5, 0)
            text:SetText(item.text or item)

            btn:SetScript("OnClick", function()
                self:Hide()
                if onClick then onClick(item) end
            end)

            self.buttons[i] = btn
            totalHeight = totalHeight + ITEM_HEIGHT
        end

        scrollChild:SetHeight(math.max(totalHeight, 1))
        scrollFrame:SetVerticalScroll(0)

        local frameHeight = math.min(totalHeight, MAX_HEIGHT) + 10
        self:SetHeight(frameHeight)
    end

    return f
end

_G.MyDropdown = Dropdown
