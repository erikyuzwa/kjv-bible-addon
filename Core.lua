local ADDON, ns = ...
local Books = ns.Books

local MAX_RANGE = 8   -- most verses shown at once for a range like "Psalm 23:1-6"

local DEFAULTS = {
    shown    = true,
    locked   = false,
    scale    = 1.0,
    width    = 300,
    mode     = "daily",     -- verse at login: "daily" or "random"
    source   = "favorites", -- where daily/random verses come from: "favorites" or "all"
    interval = 0,           -- minutes between auto-rotation; 0 = off
    point    = nil,         -- { point, relPoint, x, y }
}

local db
local cur          -- { book, chapter, firstVerse, lastVerse }
local favs = {}    -- parsed favorites
local lastFav
local ticker
local chapterIndex, total   -- for numbering every verse 1..total

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cffd4af37KJV:|r " .. msg)
end

local function Trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---------------------------------------------------------------------------
-- References
---------------------------------------------------------------------------
local ALIASES = {
    psalm = "psalms", ps = "psalms", revelations = "revelation",
    songofsongs = "songofsolomon", canticles = "songofsolomon",
}

local function FindBook(q)
    local key = q:lower():gsub("[%s%.]", "")
    if key == "" then return end
    key = ALIASES[key] or key
    for i, b in ipairs(Books) do
        if b.key == key then return i end
    end
    for i, b in ipairs(Books) do
        if b.key:sub(1, #key) == key then return i end
    end
end

-- "John 3:16", "1 cor 13:4-7", "Psalm 23" (chapter), "Jude" (book)
local function Parse(ref)
    ref = Trim(ref)
    local book, c, v1, v2 = ref:match("^(.-)%s*(%d+):(%d+)%s*%-%s*(%d+)$")
    if not book then book, c, v1 = ref:match("^(.-)%s*(%d+):(%d+)$") end
    if not book then book, c = ref:match("^(.-)%s*(%d+)$") end
    if not book or Trim(book) == "" then book, c = ref, nil end

    local b = FindBook(book)
    if not b then return end
    local chapter = Books[b].chapters[tonumber(c) or 1]
    if not chapter then return end
    v1 = tonumber(v1) or 1
    v2 = tonumber(v2) or v1
    if v1 < 1 or v1 > #chapter then return end
    if v2 < v1 then v2 = v1 end
    v2 = math.min(v2, #chapter, v1 + MAX_RANGE - 1)
    return b, tonumber(c) or 1, v1, v2
end

local function RefString(b, c, v1, v2)
    local name = Books[b].name
    if name == "Psalms" then name = "Psalm" end
    local s = name .. " " .. c .. ":" .. v1
    if v2 and v2 > v1 then s = s .. "-" .. v2 end
    return s
end

local function BuildIndex()
    chapterIndex, total = {}, 0
    for b, book in ipairs(Books) do
        for c, verses in ipairs(book.chapters) do
            chapterIndex[#chapterIndex + 1] = { b, c, total }  -- verses before this chapter
            total = total + #verses
        end
    end
end

-- n in 1..total -> book, chapter, verse
local function VerseAt(n)
    local lo, hi = 1, #chapterIndex
    while lo < hi do
        local mid = math.floor((lo + hi + 1) / 2)
        if chapterIndex[mid][3] < n then lo = mid else hi = mid - 1 end
    end
    local e = chapterIndex[lo]
    return e[1], e[2], n - e[3]
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local f = CreateFrame("Frame", "KJVBibleFrame", UIParent,
    BackdropTemplateMixin and "BackdropTemplate" or nil)
f:Hide()
f:SetFrameStrata("LOW")
f:SetClampedToScreen(true)
f:SetMovable(true)
f:EnableMouse(true)
f:EnableMouseWheel(true)
f:RegisterForDrag("LeftButton")
f:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(0, 0, 0, 0.75)
f:SetBackdropBorderColor(0.83, 0.69, 0.22, 1)

local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
text:SetPoint("TOPLEFT", 10, -10)
text:SetPoint("TOPRIGHT", -10, -10)
text:SetJustifyH("LEFT")
text:SetJustifyV("TOP")
text:SetWordWrap(true)
text:SetSpacing(2)

local ref = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ref:SetPoint("TOPRIGHT", text, "BOTTOMRIGHT", 0, -6)
ref:SetJustifyH("RIGHT")

local function Layout()
    f:SetWidth(db.width)
    f:SetHeight(text:GetStringHeight() + ref:GetStringHeight() + 26)
end

local function ShowPassage(b, c, v1, v2)
    v2 = v2 or v1
    cur = { b, c, v1, v2 }
    local verses, parts = Books[b].chapters[c], {}
    for v = v1, v2 do parts[#parts + 1] = verses[v] end
    text:SetText(table.concat(parts, " "))
    ref:SetText(RefString(b, c, v1, v2))
    Layout()
end

-- Move one verse forward (dir = 1) or back (dir = -1), crossing chapters/books.
local function Step(dir)
    if not cur then return end
    local b, c = cur[1], cur[2]
    local v = (dir > 0 and cur[4] or cur[3]) + dir
    if v > #Books[b].chapters[c] then
        c, v = c + 1, 1
        if c > #Books[b].chapters then b, c = b % #Books + 1, 1 end
    elseif v < 1 then
        c = c - 1
        if c < 1 then
            b = (b - 2) % #Books + 1
            c = #Books[b].chapters
        end
        v = #Books[b].chapters[c]
    end
    ShowPassage(b, c, v)
end

local function UseAll() return db.source == "all" or #favs == 0 end

local function ShowFavorite(i)
    lastFav = i
    local p = favs[i]
    ShowPassage(p[1], p[2], p[3], p[4])
end

local function ShowRandom()
    if UseAll() then
        ShowPassage(VerseAt(math.random(total)))
    else
        local i
        repeat i = math.random(#favs) until #favs < 2 or i ~= lastFav
        ShowFavorite(i)
    end
end

local function ShowDaily()
    local day = tonumber(date("%Y")) * 366 + tonumber(date("%j"))
    if UseAll() then
        ShowPassage(VerseAt((day * 7919) % total + 1))  -- scatter across the Bible
    else
        ShowFavorite(day % #favs + 1)
    end
end

local function SavePosition()
    local point, _, relPoint, x, y = f:GetPoint()
    db.point = { point, relPoint, x, y }
end

local function RestorePosition()
    f:ClearAllPoints()
    local p = db.point
    if p then
        f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -220, -40)
    end
end

f:SetScript("OnDragStart", function(self)
    if not db.locked then self:StartMoving() end
end)
f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self:SetUserPlaced(false) -- we store the position ourselves
    SavePosition()
end)
f:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then ShowRandom() end
end)
f:SetScript("OnMouseWheel", function(self, delta)
    Step(-delta)  -- wheel down reads forward
end)
f:SetScript("OnShow", Layout)
f:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
    GameTooltip:AddLine("KJV Bible")
    GameTooltip:AddLine("Right-click: random verse", 1, 1, 1)
    GameTooltip:AddLine("Mouse wheel: previous / next verse", 1, 1, 1)
    if not db.locked then
        GameTooltip:AddLine("Left-drag: move", 1, 1, 1)
    end
    GameTooltip:AddLine("/kjv help for commands", 0.7, 0.7, 0.7)
    GameTooltip:Show()
end)
f:SetScript("OnLeave", function() GameTooltip:Hide() end)

---------------------------------------------------------------------------
-- Auto-rotation
---------------------------------------------------------------------------
local function SetupTicker()
    if ticker then ticker:Cancel(); ticker = nil end
    if db.interval and db.interval > 0 then
        ticker = C_Timer.NewTicker(db.interval * 60, ShowRandom)
    end
end

---------------------------------------------------------------------------
-- Search (packed as book * 1e6 + chapter * 1e3 + verse)
---------------------------------------------------------------------------
local function Search(word)
    word = word:lower()
    local hits = {}
    for b, book in ipairs(Books) do
        for c, verses in ipairs(book.chapters) do
            for v, t in ipairs(verses) do
                if t:lower():find(word, 1, true) then
                    hits[#hits + 1] = b * 1000000 + c * 1000 + v
                end
            end
        end
    end
    return hits
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Help()
    Print("commands:")
    Print("  /kjv - show or hide the panel")
    Print("  /kjv <reference> - e.g. John 3:16, 1 Cor 13:4-7, Psalm 23")
    Print("  /kjv next | prev - next / previous verse in the text")
    Print("  /kjv random - random verse")
    Print("  /kjv daily - today's verse")
    Print("  /kjv find <words> - random verse containing the words")
    Print("  /kjv source favorites|all - pool for daily/random verses")
    Print("  /kjv mode daily|random - verse shown at login")
    Print("  /kjv interval <minutes> - auto-rotate random verses (0 = off)")
    Print("  /kjv lock | unlock - lock panel position")
    Print("  /kjv scale <0.5-2> | width <150-600>")
    Print("  /kjv reset - reset position and size")
end

local function Reveal()
    f:Show(); db.shown = true
end

SLASH_KJV_BIBLE1 = "/kjv"
SlashCmdList.KJV_BIBLE = function(msg)
    msg = Trim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()

    if cmd == "" then
        db.shown = not f:IsShown()
        f:SetShown(db.shown)
    elseif cmd == "help" then
        Help()
    elseif cmd == "next" or cmd == "+" then
        Step(1); Reveal()
    elseif cmd == "prev" or cmd == "-" then
        Step(-1); Reveal()
    elseif cmd == "random" then
        ShowRandom(); Reveal()
    elseif cmd == "daily" then
        ShowDaily(); Reveal()
    elseif cmd == "find" and rest ~= "" then
        local hits = Search(rest)
        if #hits == 0 then
            Print("no verses contain \"" .. rest .. "\".")
        else
            local h = hits[math.random(#hits)]
            ShowPassage(math.floor(h / 1000000), math.floor(h / 1000) % 1000, h % 1000)
            Reveal()
            Print(#hits .. " verse(s) contain \"" .. rest .. "\".")
        end
    elseif cmd == "source" and (rest == "favorites" or rest == "all") then
        db.source = rest
        Print("daily/random verses now come from: " .. rest)
    elseif cmd == "mode" and (rest == "daily" or rest == "random") then
        db.mode = rest
        Print("login verse mode: " .. rest)
    elseif cmd == "interval" then
        local n = tonumber(rest)
        if n and n >= 0 then
            db.interval = n
            SetupTicker()
            Print(n > 0 and ("rotating every " .. n .. " min.") or "auto-rotate off.")
        else
            Print("usage: /kjv interval <minutes>")
        end
    elseif cmd == "lock" then
        db.locked = true;  Print("panel locked.")
    elseif cmd == "unlock" then
        db.locked = false; Print("panel unlocked.")
    elseif cmd == "scale" then
        local n = tonumber(rest)
        if n and n >= 0.5 and n <= 2 then
            db.scale = n; f:SetScale(n)
        else
            Print("usage: /kjv scale <0.5-2>")
        end
    elseif cmd == "width" then
        local n = tonumber(rest)
        if n and n >= 150 and n <= 600 then
            db.width = n; Layout()
        else
            Print("usage: /kjv width <150-600>")
        end
    elseif cmd == "reset" then
        db.point, db.scale, db.width = nil, DEFAULTS.scale, DEFAULTS.width
        f:SetScale(db.scale)
        RestorePosition()
        Layout()
    else
        local b, c, v1, v2 = Parse(msg)
        if b then
            ShowPassage(b, c, v1, v2); Reveal()
        else
            Print("couldn't find \"" .. msg .. "\". Type /kjv help.")
        end
    end
end

---------------------------------------------------------------------------
-- Init
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        KJV_BIBLE_DB = KJV_BIBLE_DB or {}
        db = KJV_BIBLE_DB
        for k, v in pairs(DEFAULTS) do
            if db[k] == nil then db[k] = v end
        end
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        BuildIndex()
        for _, r in ipairs(ns.Favorites or {}) do
            local b, c, v1, v2 = Parse(r)
            if b then
                favs[#favs + 1] = { b, c, v1, v2 }
            else
                Print("skipping unknown favorite \"" .. r .. "\".")
            end
        end
        f:SetScale(db.scale)
        RestorePosition()
        if db.mode == "random" then ShowRandom() else ShowDaily() end
        f:SetShown(db.shown)
        SetupTicker()
    end
end)
