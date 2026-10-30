-- services
local Graphics2D = require("Graphics2D")
local wallpaper = require("wallpaper")

-- Must match t.window.title in conf.lua, and be plain ASCII so the
-- Windows wallpaper module can find the window with FindWindowA.
-- Whether the window is currently docked as the real desktop wallpaper
local dockedAsWallpaper = false
local WINDOW_TITLE = "UHook - CSS Wallpaper Engine"

-- ---------------------------------------------------------------------------
-- Crash tracing: everything interesting and any runtime error lands in
-- Logs/uhook.log next to Main.lua. A native (non-Lua) crash leaves the
-- heartbeat trail so we can at least see where it stopped.
-- ---------------------------------------------------------------------------
local LOG_PATH = nil

local function uhookLog(message)
    print(message)
    if LOG_PATH == nil or LOG_PATH == "" then return end
    local f = io.open(LOG_PATH, "a")
    if f then
        f:write(os.date("[%Y-%m-%d %H:%M:%S] "), message, "\n")
        f:close()
    end
end

local defaultErrorHandler = love.errorhandler
function love.errorhandler(msg)
    uhookLog("SCRIPT ERROR: " .. tostring(msg) .. "\n" .. debug.traceback("", 3))
    return defaultErrorHandler(msg)
end

-- Registry: add a filename in themes/ here to register a new CSS theme
local themes = {
    "default_wallpaper",
    "neon_cyberpunk",
    "matrix_terminal",
}

-- Watching this file lets you switch themes while the wallpaper is docked
-- (docked windows can't take keyboard focus, so F1/F2 won't always work)
local THEME_SWITCH_FILE = "active_theme.txt"
local THEME_SWITCH_INTERVAL = 0.5

local renderer
local themeIndex = 1
local cardFont, hintFont
local clockText = "00:00:00"
local themeTime = 0

--- Load (or re-load) a CSS theme through the Graphics2D renderer
function applyTheme(themeName)
    local ok, err = pcall(function()
        renderer:Render(nil, themeName .. ".css")
    end)

    if not ok then
        print("Failed to apply theme '" .. tostring(themeName) .. "': " .. tostring(err))
        -- Fall back to the built-in defaults so the wallpaper never breaks
        renderer.rules = nil
        renderer.themeName = "fallback"
        return false
    end

    themeTime = 0
    renderer.currentTheme = themeName
    themeIndex = indexForTheme(themeName) or themeIndex
    print("Theme switched to: " .. themeName)
    return true
end

local function isValidTheme(name)
    for _, theme in ipairs(themes) do
        if theme == name then return true end
    end
    return false
end

function indexForTheme(name)
    for i, theme in ipairs(themes) do
        if theme == name then return i end
    end
    return nil
end

-- Poll the switch file: first line = theme name ("neon_cyberpunk" or the
-- full "neon_cyberpunk.css" both work). Writing "exit" closes the wallpaper
-- (docked windows have no taskbar button to click).
local switchTimer = 0
local function checkThemeSwitchFile()
    local ok, contents = pcall(love.filesystem.read, "string", THEME_SWITCH_FILE)
    if not ok or type(contents) ~= "string" then return end

    local requested = contents:match("[^\r\n]+")
    if not requested then return end

    requested = requested:gsub("/%*.-%*/", ""):match("^%s*(.-)%s*$")
    if requested == "" then return end

    local keyword = string.lower(requested)
    if keyword == "exit" or keyword == "quit" then
        love.event.quit()
        return
    end

    requested = requested:match("^(.*)%.css$") or requested
    if requested ~= renderer.currentTheme and isValidTheme(requested) then
        applyTheme(requested)
    end
end

-- 1. This function runs ONCE when the engine initializes
local duplicateInstance = false
local heartbeat = 0
local lastHeartbeatLog = 0

function love.load()
    -- Crash-log target: <source>/Logs/uhook.log (empty for .love archives)
    local sourceDir = love.filesystem.getSource() or ""
    if sourceDir ~= "" then
        LOG_PATH = sourceDir:gsub("\\+$", "") .. "/Logs/uhook.log"
    end

    math.randomseed(os.time())

    -- Refuse to run twice: stacked wallpaper windows fight over the WorkerW
    -- layer and closing one can re-parent the other's window mid-exit, which
    -- looks exactly like UHook "keeps crashing".
    local instances = wallpaper.countWindows(WINDOW_TITLE)
    if instances > 1 then
        duplicateInstance = true
        uhookLog("Duplicate instance detected (" .. instances .. " windows) - closing this copy.")
        love.event.quit()
        return
    end

    uhookLog("== UHook Desktop v2.3 booting ==")
    uhookLog("Controls: F1 next theme | F2 random theme | Esc quit")
    uhookLog("Tip: create '" .. THEME_SWITCH_FILE .. "' containing a theme name to switch themes while docked.")

    renderer = Graphics2D.new()
    cardFont = love.graphics.newFont(64)
    hintFont = love.graphics.newFont(14)

    -- Cover the whole desktop, top-left anchored, then dock the window as
    -- the wallpaper (behind desktop icons, taskbar stays on top)
    local desktopWidth, desktopHeight = love.window.getDesktopDimensions()
    uhookLog("Desktop size: " .. tostring(desktopWidth) .. "x" .. tostring(desktopHeight))
    love.window.setMode(desktopWidth, desktopHeight, {
        resizable = false,
        borderless = true,
        highdpi = true,
        centered = true,
    })
    love.window.setPosition(0, 0)

    local docked, dockErr = wallpaper.dock(WINDOW_TITLE)
    if docked then
        dockedAsWallpaper = true
        uhookLog("Wallpaper mode: docked behind the desktop icons.")
    else
        uhookLog("Wallpaper mode failed: " .. tostring(dockErr) .. " (running as a normal window)")
    end

    applyTheme(themes[themeIndex])
end

-- 2. This function loops continuously to update code logic
function love.update(dt)
    if duplicateInstance then return end

    clockText = os.date("%H:%M:%S")
    themeTime = themeTime + dt

    -- Heartbeat: if UHook ever dies without an error screen, this trail in
    -- Logs/uhook.log shows the last moments before the process vanished.
    heartbeat = heartbeat + dt
    if heartbeat - lastHeartbeatLog >= 10 then
        lastHeartbeatLog = heartbeat
        uhookLog(string.format("heartbeat ok (uptime %.0fs, theme=%s, docked=%s)",
            heartbeat, tostring(renderer.themeName), tostring(dockedAsWallpaper)))
    end

    switchTimer = switchTimer + dt
    if switchTimer >= THEME_SWITCH_INTERVAL then
        switchTimer = 0
        checkThemeSwitchFile()
    end
end

-- 3. This function loops continuously to physically draw the graphics
function love.draw()
    if duplicateInstance or renderer == nil then return end

    local style = renderer:getStyle()
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()

    -- Fullscreen body layer driven by the theme's CSS background.
    -- When docked as the wallpaper there is nothing meaningful "behind" the
    -- window to show through, so render fully opaque for a clean wallpaper.
    local background = style.background
    love.graphics.setColor(background[1], background[2], background[3],
        dockedAsWallpaper and 1.0 or background[4])
    love.graphics.rectangle("fill", 0, 0, w, h)

    -- Centered clock card
    local cardWidth, cardHeight = 520, 200
    local cx, cy = w / 2, h / 2

    -- @keyframes pulse lives in the CSS; approximate scale 1.00 -> 1.05 -> 1.00
    -- on a 2s loop so every theme inherits its animation.
    local pulse = 1 + 0.05 * math.sin((themeTime / 2) * math.pi * 2)

    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.scale(pulse, pulse)

    love.graphics.setColor(style.card)
    love.graphics.rectangle("fill", -cardWidth / 2, -cardHeight / 2, cardWidth, cardHeight, 16, 16)

    love.graphics.setColor(style.text)
    love.graphics.setFont(cardFont)
    local textWidth = cardFont:getWidth(clockText)
    love.graphics.print(clockText, -textWidth / 2, -cardFont:getHeight() / 2)

    love.graphics.pop()

    -- Current theme + control hints
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.setFont(hintFont)
    love.graphics.print(
        ("Theme: %s    [F1] next theme   [F2] random theme   [Esc] quit  (only while focused, create %s to switch anytime)")
            :format(renderer.themeName, THEME_SWITCH_FILE),
        16,
        h - 30
    )
end

-- Keypress handling for theme switching.
-- NOTE: docked wallpaper windows don't receive keyboard focus, so these hotkeys
-- only work when the window happens to be focused. Use active_theme.txt otherwise.
function love.keypressed(key)
    if duplicateInstance then return end
    if key == "f1" then
        -- Cycle to the next theme
        themeIndex = themeIndex % #themes + 1
        applyTheme(themes[themeIndex])
    elseif key == "f2" then
        -- Random theme (never the currently active one)
        local pick = math.random(#themes)
        if pick == themeIndex then pick = pick % #themes + 1 end
        themeIndex = pick
        applyTheme(themes[themeIndex])
    elseif key == "escape" then
        love.event.quit()
    end
end

function love.quit()
    if duplicateInstance then return end

    -- Re-parent the window to the desktop before quitting so the shell is
    -- not left holding a destroyed child (which it dislikes). Only ever
    -- touch our OWN window when we actually docked it, never a sibling's.
    uhookLog("Shutting down" .. (dockedAsWallpaper and " (un-docking wallpaper)" or ""))
    if dockedAsWallpaper then
        wallpaper.undock(WINDOW_TITLE)
    end
    uhookLog("== Exit complete ==")
end
