function love.conf(t)
    t.window.title = "UHook - CSS Wallpaper Engine"
    t.window.width = 1920
    t.window.height = 1080
    t.window.borderless = true
    t.window.centered = true
    t.window.highdpi = true
    t.window.resizable = false

    -- Let the desktop show through where the theme uses transparency
    t.window.transparent = true
end
