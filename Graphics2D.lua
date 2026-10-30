-- Graphics2D: a tiny CSS theme engine.
--
-- this module PARSES the CSS theme files in themes/ and exposes the
-- extracted styles to LÖVE's 2D renderer. The CSS files are the single source
-- of truth for the wallpaper's look.

local Graphics2D = {}
Graphics2D.__index = Graphics2D

-- Folder that contains the CSS themes
Graphics2D.themeDir = "themes/"

function Graphics2D.new(config)
    local self = setmetatable({}, Graphics2D)
    self.config = config or {}
    return self
end

-- Fallback palette used when a property is missing from the CSS file
local FALLBACK = {
    background = { 0.12, 0.12, 0.18, 0.7 },
    -- clock text: white/blue
    text = { 0.80, 0.84, 0.96, 1.0 },
    -- clock backing card
    card = { 0.20, 0.20, 0.28, 0.8 },
}



local function parseColor(value)
    if type(value) ~= "string" then return nil end

    local r, g, b, a = value:match("rgba%((%d+),%s*(%d+),%s*(%d+),%s*([%d%.]+)%)")
    if r then
        return { r / 255, g / 255, b / 255, tonumber(a) }
    end

    r, g, b = value:match("rgb%((%d+),%s*(%d+),%s*(%d+)%)")
    if r then
        return { r / 255, g / 255, b / 255, 1 }
    end

    local hex = value:match("#(%x%x%x%x%x%x)")
    if hex then
        return {
            tonumber("0x" .. hex:sub(1, 2)) / 255,
            tonumber("0x" .. hex:sub(3, 4)) / 255,
            tonumber("0x" .. hex:sub(5, 6)) / 255,
            1,
        }
    end

    hex = value:match("#(%x%x%x)")
    if hex then
        return {
            tonumber("0x" .. hex:sub(1, 1)) / 15,
            tonumber("0x" .. hex:sub(2, 2)) / 15,
            tonumber("0x" .. hex:sub(3, 3)) / 15,
            1,
        }
    end

    -- Gradients and named colors are not supported by the canvas renderer;
    -- returning nil falls back to the theme-safe defaults.
    return nil
end

local function trim(s)
    return s:match("^%s*(.-)%s*$") or ""
end

-- Selectors we must ignore: @keyframes blocks and their step selectors ("0%", "50%")
local function skipSelector(selector)
    if selector:find("@") then return true end
    if selector:find("keyframes") then return true end
    if selector:match("^[%s0-9%%]+$") then return true end
    return false
end

local function parseBlock(block)
    local props = {}
    for name, value in block:gmatch("([%w%-]+)%s*:%s*([^;{}]+)") do
        props[trim(name)] = trim(value)
    end
    return props
end

--load css
function Graphics2D:loadCSS(path)
    local contents = love.filesystem.read("string", path)
    assert(contents, "Could not read theme file: " .. path)

    contents = contents:gsub("/%*.-%*/", " ")

    local rules = {}
    local from = 1
    while true do
        local _, stop, selector, block = contents:find("([^{}]*)%{([^{}]*)%}", from)
        if not stop then break end
        from = stop + 1

        selector = trim(selector)
        if not skipSelector(selector) then
            rules[selector] = rules[selector] or {}
            for name, value in pairs(parseBlock(block)) do
                rules[selector][name] = value
            end
        end
    end

    return rules
end

-- load a theme by CSS filename, e.g. "neon_cyberpunk.css"
function Graphics2D:Render(Events, themeFile)
    themeFile = themeFile or "default_wallpaper.css"
    self.rules = self:loadCSS(self.themeDir .. themeFile)
    self.themeName = themeFile:match("^(.*)%.css$") or themeFile
    print("CSS Theme Loaded: " .. themeFile)
    return true
end

function Graphics2D:getStyle()
    local rules = self.rules or {}
    local body = rules["body"] or {}
    local clock = rules["#clock"] or {}

    local background = parseColor(body["background-color"]) or parseColor(body.background) or FALLBACK.background

    local card = parseColor(clock.background) or FALLBACK.card

    local text = parseColor(clock.color) or FALLBACK.text

    local family = string.lower(clock["font-family"] or "")
    local mono = family:find("courier") ~= nil or family:find("monospace") ~= nil

    return {
        background = background,
        card = card,
        text = text,
        mono = mono,
    }
end

return Graphics2D
