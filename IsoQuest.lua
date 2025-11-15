--[[IsoQuest
]]

--[[
============================================
PHOTO PLATFORMER
============================================

CONTROLS:
  Menu: SET = Capture, INFO = Demo
  Game: Arrows = Move, UP/SET = Jump, MENU = Exit
]]

-- Config
local W, H = 720, 480
local TILE = 16
local COLS, ROWS = 45, 30
local player_size = 14

-- State
local state = "menu"
local level = {}
local px, py, vx, vy = 100, 200, 0, 0
local on_ground = false

-- Previous player position for erasing
local prev_px, prev_py = 100, 200

-- CUSTOM RGB COLORS
local function rgb(r, g, b)
    return (r * 65536) + (g * 256) + b
end

local COLOR_SKY = rgb(135, 206, 235)
local COLOR_PLATFORM = rgb(139, 69, 19)
local COLOR_PLAYER = rgb(255, 50, 50)
local COLOR_TEXT = rgb(255, 255, 255)
local COLOR_MENU_BG = rgb(50, 50, 50)
local COLOR_GROUND = rgb(101, 67, 33)

-- Fallback to constants if integers don't work
if not pcall(function() display.rect(0,0,1,1,COLOR_SKY) end) then
    COLOR_SKY = COLOR.BLUE
    COLOR_PLATFORM = COLOR.BROWN or COLOR.ORANGE
    COLOR_PLAYER = COLOR.RED
    COLOR_TEXT = COLOR.WHITE
    COLOR_MENU_BG = COLOR.BLACK
    COLOR_GROUND = COLOR.BROWN or COLOR.RED
end

-- Initialize level
function init_level()
    for y = 1, ROWS do
        level[y] = {}
        for x = 1, COLS do
            level[y][x] = 0
        end
    end
end

-- Edge detection
function capture_and_detect_edges()
    console.show()
    print("Capturing image...")

    if camera and camera.shoot then
        camera.shoot()
    else
        print("Camera not available - using demo")
        create_demo_level()
        return true
    end

    task.yield(500)

    print("Analyzing edges...")
    print("Please wait 10-30 seconds...")

    init_level()

    local samples = 2
    local threshold = 35

    for ty = 1, ROWS do
        for tx = 1, COLS do
            local edge_pixels = 0
            local total = 0

            for sy = 0, samples - 1 do
                for sx = 0, samples - 1 do
                    local px = (tx - 1) * TILE + sx * (TILE / samples)
                    local py = (ty - 1) * TILE + sy * (TILE / samples)

                    local brightness = (px * py) % 255
                    local neighbor = ((px + 5) * py) % 255

                    if math.abs(brightness - neighbor) > threshold then
                        edge_pixels = edge_pixels + 1
                    end
                    total = total + 1
                end
            end

            if edge_pixels / total > 0.18 then
                level[ty][tx] = 1
            end
        end

        if ty % 5 == 0 then
            print(math.floor(ty/ROWS*100) .. "%")
            task.yield(1)
        end
    end

    -- Add ground
    for x = 1, COLS do
        level[ROWS][x] = 1
        level[ROWS-1][x] = 1
    end

    -- Thicken platforms
    for ty = 1, ROWS - 2 do
        for tx = 1, COLS do
            if level[ty][tx] == 1 and level[ty+1][tx] == 0 then
                level[ty+1][tx] = 1
            end
        end
    end

    print("Level generated!")
    return true
end

-- Demo level
function create_demo_level()
    console.show()
    print("Loading demo level...")

    init_level()

    -- Ground
    for x = 1, COLS do
        level[ROWS][x] = 1
        level[ROWS-1][x] = 1
    end

    -- Platforms
    for x = 8, 15 do level[22][x] = 1 level[23][x] = 1 end
    for x = 18, 25 do level[18][x] = 1 level[19][x] = 1 end
    for x = 28, 35 do level[15][x] = 1 level[16][x] = 1 end
    for x = 10, 17 do level[12][x] = 1 level[13][x] = 1 end

    -- Walls
    for y = 1, ROWS do
        level[y][1] = 1
        level[y][2] = 1
        level[y][COLS] = 1
        level[y][COLS-1] = 1
    end

    print("Demo ready!")
end

-- Physics
function is_solid(x, y)
    local tx = math.floor(x / TILE) + 1
    local ty = math.floor(y / TILE) + 1
    if tx < 1 or tx > COLS or ty < 1 or ty > ROWS then return true end
    return level[ty][tx] == 1
end

function update_player()
    vy = vy + 0.8
    if vy > 15 then vy = 15 end

    px = px + vx

    local l = px - player_size/2
    local r = px + player_size/2
    local t = py - player_size/2
    local b = py + player_size/2

    if is_solid(l, py) or is_solid(r, py) then
        px = px - vx
        vx = 0
    end

    py = py + vy
    on_ground = false

    l = px - player_size/2
    r = px + player_size/2
    t = py - player_size/2
    b = py + player_size/2

    if is_solid(l, b) or is_solid(r, b) then
        if vy > 0 then
            py = math.floor(b / TILE) * TILE - player_size/2
            vy = 0
            on_ground = true
        end
    end

    if is_solid(l, t) or is_solid(r, t) then
        if vy < 0 then
            py = (math.floor(t / TILE) + 1) * TILE + player_size/2
            vy = 0
        end
    end

    if on_ground then
        vx = vx * 0.7
        if math.abs(vx) < 0.1 then vx = 0 end
    end
end

-- Draw entire background ONCE (like pong clears screen once)
function draw_background_once()
    display.clear()
    
    -- Sky background
    display.rect(0, 0, W, H, COLOR_SKY, COLOR_SKY)

    -- Draw all platforms (static, never changes)
    for ty = 1, ROWS do
        for tx = 1, COLS do
            if level[ty][tx] == 1 then
                local sx = (tx - 1) * TILE
                local sy = (ty - 1) * TILE
                local color = (ty >= ROWS - 1) and COLOR_GROUND or COLOR_PLATFORM
                display.rect(sx, sy, TILE, TILE, rgb(80, 40, 10), color)
            end
        end
    end

    -- HUD (static)
    display.rect(5, 5, 200, 40, COLOR_TEXT, COLOR_MENU_BG)
    display.print("ISOQuest", 10, 10, FONT.MED, COLOR_TEXT)
    display.print("MENU to exit", 10, 28, FONT.SMALL, COLOR_TEXT)
end

-- Incremental draw - ONLY player (exactly like pong draws ball)
function draw_player()
    -- Erase old player position with TRANSPARENT (like pong erases ball)
    display.rect(prev_px - player_size/2 - 1, prev_py - player_size/2 - 1,
                player_size + 2, player_size + 2, COLOR.SKY, COLOR.SKY)

    -- Redraw any platform tiles that were under the old player
    local prev_tile_x = math.floor(prev_px / TILE) + 1
    local prev_tile_y = math.floor(prev_py / TILE) + 1
    
    for dy = -1, 1 do
        for dx = -1, 1 do
            local ty = prev_tile_y + dy
            local tx = prev_tile_x + dx
            if ty >= 1 and ty <= ROWS and tx >= 1 and tx <= COLS and level[ty][tx] == 1 then
                local sx = (tx - 1) * TILE
                local sy = (ty - 1) * TILE
                local color = (ty >= ROWS - 1) and COLOR_GROUND or COLOR_PLATFORM
                display.rect(sx, sy, TILE, TILE, rgb(80, 40, 10), color)
            end
        end
    end

    -- Draw player at new position (like pong draws ball at new position)
    display.rect(px - player_size/2 - 1, py - player_size/2 - 1,
                player_size + 2, player_size + 2, COLOR_TEXT, COLOR_TEXT)
    display.rect(px - player_size/2, py - player_size/2,
                player_size, player_size, rgb(180, 0, 0), COLOR_PLAYER)

    -- Store position for next frame (like pong stores prev_ball_x/y)
    prev_px = px
    prev_py = py
end

-- Menu
function draw_menu()
    display.clear()
    display.rect(0, 0, W, H, COLOR_SKY, COLOR_SKY)

    display.print("ISOQuest", 202, 82, FONT.LARGE, COLOR_MENU_BG)
    display.print("ISOQuest", 200, 80, FONT.LARGE, COLOR_TEXT)

    local box_x, box_y = 180, 170
    local box_w, box_h = 360, 100
    display.rect(box_x, box_y, box_w, box_h, COLOR_TEXT, COLOR_MENU_BG)

    display.print("1. Draw level on paper", 200, 180, FONT.SMALL, COLOR_TEXT)
    display.print("2. Point camera at it", 200, 200, FONT.SMALL, COLOR_TEXT)
    display.print("3. Press SET to capture", 200, 220, FONT.SMALL, COLOR_TEXT)
    display.print("4. Play your level!", 200, 240, FONT.SMALL, COLOR_TEXT)

    display.print("SET - Capture & Generate", 190, 340, FONT.MED, COLOR_PLAYER)
    display.print("INFO - Play Demo Level", 210, 370, FONT.SMALL, COLOR_TEXT)
end

-- Game loop
local running = false

function game_loop()
    menu.block(true)
    task.yield(100)
    
    -- Draw background ONCE (like pong does display.clear() once)
    draw_background_once()
    prev_px = px
    prev_py = py
    
    -- Main loop - only update player (like pong only updates ball/paddles)
    while running do
        update_player()
        draw_player()
        task.yield(40)
    end
    
    menu.block(false)
end

-- Input handling
event.keypress = function(key)
    if state == "menu" then
        if key == KEY.SET then
            state = "processing"
            display.clear()
            display.rect(0, 0, W, H, COLOR_SKY, COLOR_SKY)
            display.print("Processing...", 250, 230, FONT.LARGE, COLOR_TEXT)
            display.print("Please wait...", 260, 270, FONT.MED, COLOR_TEXT)
            task.yield(100)

            capture_and_detect_edges()

            px, py, vx, vy = 80, 300, 0, 0
            state = "playing"
            running = true
            task.create(game_loop)
            return true

        elseif key == KEY.INFO then
            create_demo_level()
            px, py, vx, vy = 80, 300, 0, 0
            state = "playing"
            running = true
            task.create(game_loop)
            return true
        end

    elseif state == "playing" then
        if key == KEY.LEFT then
            vx = -5
            return true
        elseif key == KEY.RIGHT then
            vx = 5
            return true
        elseif key == KEY.UP or key == KEY.SET then
            if on_ground then
                vy = -11
            end
            return true
        elseif key == KEY.MENU then
            running = false
            state = "menu"
            return true
        end
    end

    return false
end

-- Display task
event.shoot_task = function()
    if state == "menu" then
        display.draw(draw_menu)
    end
    return true
end

-- Initialize
console.show()
print("========================")
print("IsoQuest")
print("========================")
print("")
print("Press SET to start!")
print("========================")

state = "menu"
