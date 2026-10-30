-- wallpaper.lua: Windows FFI glue that docks the LÖVE window as the actual
-- desktop wallpaper, using the same technique Wallpaper Engine uses:
--
--   1. Ask Progman (the desktop host) to create a WorkerW wallpaper layer
--      behind the desktop icons (undocumented message 0x052C).
--   2. Enumerate top-level windows to find that WorkerW sitting behind a
--      window containing the "SHELLDLL_DefView" list-view (the icons).
--   3. SetParent() our render window into it.
--
-- Result: the canvas renders behind the icons, and the taskbar (a separate
-- shell window) always stays on top — exactly wallpaper behaviour.

local ffi = require("ffi")

-- void* is used for window handles / LRESULT-style values on purpose: its
-- size automatically matches the process (32- or 64-bit), so this works for
-- both LÖVE builds without declaring per-arch prototypes.
ffi.cdef[[
    typedef int (__stdcall *wallpaper_enum_t)(void* hWnd, void* lParam);

    void* FindWindowA(const char* lpClassName, const char* lpWindowName);
    void* FindWindowExA(void* hWndParent, void* hWndChildAfter,
                        const char* lpClassName, const char* lpWindowName);
    void* SendMessageA(void* hWnd, unsigned int Msg, void* wParam, void* lParam);
    int   EnumWindows(wallpaper_enum_t lpEnumFunc, void* lParam);
    int   EnumChildWindows(void* hWndParent, wallpaper_enum_t lpEnumFunc, void* lParam);
    int   GetWindowTextA(void* hWnd, char* lpString, int nMaxCount);
    void* SetParent(void* hWndChild, void* hWndNewParent);
]]

local user32 = ffi.load("user32")

-- Undocumented: Progman spawns a WorkerW "wallpaper layer" when sent this
local WM_SPAWN_WORKERW = 0x052C

local wallpaper = {}

-- Locate the WorkerW window that hosts the wallpaper layer.
-- Returns (workerW or nil, progman).
local function findWallpaperHost()
    local progman = user32.FindWindowA("Progman", nil)
    if progman == nil then
        return nil, nil
    end

    -- Normal Explorer state: the icon list-view lives inside Progman, and a
    -- WorkerW already sits behind it holding the wallpaper.
    local defview = user32.FindWindowExA(progman, nil, "SHELLDLL_DefView", nil)
    if defview ~= nil then
        local worker = user32.FindWindowExA(nil, defview, "WorkerW", nil)
        if worker ~= nil then
            return worker, progman
        end
    end

    -- Explorer sometimes has no WorkerW ready (fresh login, brightness
    -- changes): ask Progman to spawn one, then find it by enumeration.
    user32.SendMessageA(progman, WM_SPAWN_WORKERW, nil, nil)

    local worker = nil
    local callback = ffi.cast("wallpaper_enum_t", function(hwnd, _)
        if worker == nil and user32.FindWindowExA(hwnd, nil, "SHELLDLL_DefView", nil) ~= nil then
            -- The WorkerW immediately AFTER the DefView's parent is ours
            worker = user32.FindWindowExA(nil, hwnd, "WorkerW", nil)
        end
        return 1 -- continue enumeration
    end)
    user32.EnumWindows(callback, nil)
    callback:free()

    return worker, progman
end

--- Count every window with this title. Two passes are needed:
---   1. top-level windows (a running but NOT yet docked instance, maybe us)
---   2. children of the WorkerW wallpaper host (already-docked instances,
---      which stopped being top-level the moment SetParent() ate them)
--- With 0 = none, 1 = just us, 2+ = duplicate instances competing.
function wallpaper.countWindows(windowTitle)
    local count = 0

    -- Pass 1: top-level windows by title
    local hwnd = user32.FindWindowA(nil, windowTitle)
    while hwnd ~= nil and count < 32 do
        count = count + 1
        hwnd = user32.FindWindowExA(nil, hwnd, nil, windowTitle)
    end

    -- Pass 2: windows docked inside the wallpaper host layer
    local host, progman = findWallpaperHost()
    host = host or progman
    if host ~= nil then
        local titleBuffer = ffi.new("char[128]")
        local visited = ffi.cast("wallpaper_enum_t", function(child, _)
            local length = user32.GetWindowTextA(child, titleBuffer, 128)
            if length > 0 and ffi.string(titleBuffer) == windowTitle then
                count = count + 1
            end
            return 1 -- keep enumerating
        end)
        user32.EnumChildWindows(host, visited, nil)
        visited:free()
    end

    return count
end

-- Search our render window by title (must be plain ASCII, see conf.lua)
local function findLoveWindow(windowTitle)
    return user32.FindWindowA(nil, windowTitle)
end

--- Make the LÖVE window the desktop wallpaper (behind icons, taskbar on top)
---@param windowTitle string must match t.window.title in conf.lua exactly
function wallpaper.dock(windowTitle)
    if jit == nil or jit.os ~= "Windows" then
        return false, "wallpaper docking is Windows-only"
    end

    local hwnd = findLoveWindow(windowTitle)
    if hwnd == nil then
        return false, "LOVE window not found (title mismatch?)"
    end

    local host, progman = findWallpaperHost()

    -- Fallback: parenting straight to Progman still renders behind the icons
    host = host or progman
    if host == nil then
        return false, "no Progman/WorkerW wallpaper host found"
    end

    if user32.SetParent(hwnd, host) == nil then
        return false, "SetParent failed"
    end

    return true
end

--- Release the window back to the desktop (used on exit / during tests)
function wallpaper.undock(windowTitle)
    if jit == nil or jit.os ~= "Windows" then
        return false, "wallpaper docking is Windows-only"
    end

    local hwnd = findLoveWindow(windowTitle)
    if hwnd == nil then
        return false, "LOVE window not found (title mismatch?)"
    end

    if user32.SetParent(hwnd, nil) == nil then
        return false, "SetParent failed"
    end

    return true
end

return wallpaper
