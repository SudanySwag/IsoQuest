--[[IsoQuest
]]

--[[
============================================
PHOTO PLATFORMER - DEBUG BUILD
============================================

CONTROLS:
  Menu: SET = Capture, INFO = Demo
  Game: Arrows = Move, UP/SET = Jump, MENU = Exit
]]

print("[ISOQUEST] Script loading...")

require("keys")

-- Config
local W, H = 720, 480
local TILE = 16
local COLS, ROWS = 45, 30
local player_size = 14

-- State
local state = "load_menu"
local level = {}
local px, py, vx, vy = 100, 200, 0, 0
local on_ground = false
local cam_x = 0
local jumps_remaining = 2

-- Previous player position for erasing
local prev_px, prev_py = 100, 200

-- CUSTOM RGB COLORS (must be defined first)
local function rgb(r, g, b)
    return (r * 65536) + (g * 256) + b
end

-- Load custom images
local menu_image = nil
local sprite_image = nil
local TRANSPARENT_KEY = rgb(255, 0, 255)  -- Magenta as transparent color

local exit_script = false
local bmp_path = "ML/SCRIPTS/screenshots/capture.bmp"

function load_custom_images()
    print("[ISOQUEST] load_custom_images()")

    -- Try to load menu background (BMP preferred for transparency support)
    local menu_path = "ML/SCRIPTS/menu.bmp"
    local f_menu = io.open(menu_path, "rb")
    if f_menu then
        f_menu:close()
        print("[ISOQUEST] Menu image found: " .. menu_path)
        menu_image = display.load(menu_path)
        print("[ISOQUEST] Menu image loaded.")
    else
        print("[ISOQUEST] Menu image not found, using default")
    end
    
    -- Try to load sprite (BMP preferred for transparency support)
    local sprite_path = "ML/SCRIPTS/sprite.bmp"
    local f_sprite = io.open(sprite_path, "rb")
    if f_sprite then
        f_sprite:close()
        print("[ISOQUEST] Sprite image found: " .. sprite_path)
        sprite_image = display.load(sprite_path)
        print("[ISOQUEST] Sprite image loaded.")
    else
        print("[ISOQUEST] Sprite image not found, using default")
    end
end

local COLOR_SKY = rgb(135, 206, 235)
local COLOR_PLATFORM = rgb(139, 69, 19)
local COLOR_PLAYER = rgb(255, 50, 50)
local COLOR_TEXT = rgb(255, 255, 255)
local COLOR_MENU_BG = rgb(50, 50, 50)
local COLOR_GROUND = rgb(101, 67, 33)

-- Fallback to constants if integers don't work
if not pcall(function() display.rect(0,0,1,1,COLOR_SKY) end) then
    print("[ISOQUEST] Using fallback COLOR constants")
    COLOR_SKY = COLOR.BLUE
    COLOR_PLATFORM = COLOR.BROWN or COLOR.ORANGE
    COLOR_PLAYER = COLOR.RED
    COLOR_TEXT = COLOR.WHITE
    COLOR_MENU_BG = COLOR.BLACK
    COLOR_GROUND = COLOR.BROWN or COLOR.RED
end

-- Initialize level
function init_level()
    print("[ISOQUEST] init_level() - clearing "..ROWS.."x"..COLS.." grid")
    for y = 1, ROWS do
        level[y] = {}
        for x = 1, COLS do
            level[y][x] = 0
        end
    end
end

-- threshold for pixel darkness (0 = black, 255 = white)
local DARK_THRESHOLD = 80          
local DARK_RATIO = 0.3           -- % of pixels in tile that must be dark

function generate_level_from_bmp_stream(path)
    print("[STREAM] Opening BMP: " .. path)

    local f = io.open(path, "rb")
    if not f then
        print("[STREAM][ERROR] Cannot open file.")
        return false
    end

    -- Read file header (14 bytes)
    local header = f:read(14)
    if not header or header:sub(1,2) ~= "BM" then
        print("[STREAM][ERROR] Invalid BMP magic header")
        f:close()
        return false
    end

    -- Read DIB header (40 bytes)
    local dib = f:read(40)
    local function dw(off)
        local b1,b2,b3,b4 = dib:byte(off+1, off+4)
        return b1 + b2*256 + b3*65536 + b4*16777216
    end
    local function w(off)
        local b1,b2 = dib:byte(off+1, off+2)
        return b1 + b2*256
    end

    local width  = dw(4)
    local height = dw(8)
    local bpp    = w(14)
    local compression = dw(16)
    local function read_dword_LE(s, offset)
        local b1 = s:byte(offset+1)
        local b2 = s:byte(offset+2)
        local b3 = s:byte(offset+3)
        local b4 = s:byte(offset+4)
        return b1 + b2*256 + b3*65536 + b4*16777216
    end

    local pixel_offset = read_dword_LE(header, 10)
    print("[STREAM] Corrected pixel_offset = " .. pixel_offset)


    print("[STREAM] width="..width..
          " height="..height..
          " bpp="..bpp..
          " compression="..compression)

    if compression ~= 0 then
        print("[STREAM][ERROR] Compressed BMP not supported")
        f:close()
        return false
    end

    if bpp ~= 24 and bpp ~= 32 then
        print("[STREAM][ERROR] Only 24/32 bpp BMP supported")
        f:close()
        return false
    end

    print("[STREAM] Scanning bitmap rows...")

    init_level()

    local Bpp = bpp / 8
    local row_bytes = width * Bpp
    local stride = math.ceil(row_bytes / 4) * 4

    -- determine orientation
    local topdown = (height < 0)
    if topdown then height = -height end

    -- jump to start of pixel data
    f:seek("set", pixel_offset)

    -- Pre-allocate tile counters
    local tiles_x = math.min(COLS, math.floor(width / TILE))
    local tiles_y = math.min(ROWS, math.floor(height / TILE))

    local dark_counts = {}
    local pixel_counts = {}
    for ty = 1, tiles_y do
        dark_counts[ty] = {}
        pixel_counts[ty] = {}
        for tx = 1, tiles_x do
            dark_counts[ty][tx] = 0
            pixel_counts[ty][tx] = TILE*TILE
        end
    end

    -- We will store rows in correct order
    local roworder = {}
    for y = 0, height-1 do
        if topdown then
            table.insert(roworder, y)
        else
            table.insert(roworder, height-1-y)
        end
    end

    -- Process each row
    for logical_y = 1, height do
        local bmp_y = roworder[logical_y]

        -- read one full row including padding
        local raw = f:read(stride)
        if not raw then print("[STREAM] Read row "..logical_y.." (bmp_y="..bmp_y..")") end
        if not raw then break end

        local offset = 1

        -- which tile-row is this?
        local tile_row = math.floor((logical_y-1) / TILE) + 1
        if tile_row > tiles_y then break end

        for x = 0, width-1 do
            local tile_col = math.floor(x / TILE) + 1
            if tile_col <= tiles_x then

                local b = raw:byte(offset)
                local g = raw:byte(offset+1)
                local r = raw:byte(offset+2)

                local brightness = (r + g + b) / 3

                if brightness < DARK_THRESHOLD then
                    dark_counts[tile_row][tile_col] =
                        dark_counts[tile_row][tile_col] + 1
                end
            end

            offset = offset + Bpp
        end
    end

    print("[STREAM] Finished row scan. Now finalizing tiles...")

    for ty = 1, tiles_y do
        for tx = 1, tiles_x do
            local ratio = dark_counts[ty][tx] / pixel_counts[ty][tx]
            if ratio >= DARK_RATIO then
                level[ty][tx] = 1
            else
                level[ty][tx] = 0
            end
        end
    end

    f:close()
    print("[STREAM] Done! Level generated.")
    return true
end


-- Demo level
function create_demo_level()
    print("[ISOQUEST] create_demo_level()")

    init_level()

    print("[ISOQUEST] Creating ground...")
    -- Ground
    for x = 1, COLS do
        level[ROWS][x] = 1
        level[ROWS-1][x] = 1
    end

    print("[ISOQUEST] Creating sample platforms...")
    -- Platforms
    for x = 8, 15 do level[22][x] = 1 level[23][x] = 1 end
    for x = 18, 25 do level[18][x] = 1 level[19][x] = 1 end
    for x = 28, 35 do level[15][x] = 1 level[16][x] = 1 end
    for x = 10, 17 do level[12][x] = 1 level[13][x] = 1 end

    print("[ISOQUEST] Creating walls...")
    -- Walls
    for y = 1, ROWS do
        level[y][1] = 1
        level[y][2] = 1
        level[y][COLS] = 1
        level[y][COLS-1] = 1
    end

    print("[ISOQUEST] Demo level ready")
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
            jumps_remaining = 2  -- Reset jumps when landing
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
    else
        -- Apply air friction when not on ground
        vx = vx * 0.85
    end

    -- Cap horizontal speed
    if vx > 6 then vx = 6 end
    if vx < -6 then vx = -6 end
end

-- Draw entire background (static level)
function draw_level()
    print("[ISOQUEST] draw_level()")
    menu.close()
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

-- Incremental draw - ONLY player
function draw_player()
    -- Erase old player position
    display.rect(prev_px - player_size/2 - 1, prev_py - player_size/2 - 1,
                player_size + 2, player_size + 2, COLOR_SKY, COLOR_SKY)

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

    -- Draw player at new position
    if sprite_image then
        sprite_image:draw(px - player_size/2, py - player_size/2, player_size, player_size)
    else
        display.rect(px - player_size/2 - 1, py - player_size/2 - 1,
                    player_size + 2, player_size + 2, COLOR_TEXT, COLOR_TEXT)
        display.rect(px - player_size/2, py - player_size/2,
                    player_size, player_size, rgb(180, 0, 0), COLOR_PLAYER)
    end

    -- Store position for next frame
    prev_px = px
    prev_py = py
end

-- Menu
function draw_menu()
    print("[ISOQUEST] draw_menu() state="..tostring(state))
    display.clear()
    
    if menu_image then
        display.rect(0, 0, W, H, COLOR.TRANSPARENT, COLOR.TRANSPARENT)
        menu_image:draw(0,0)
    else
        display.rect(0, 0, W, H, COLOR.TRANSPARENT, COLOR.TRANSPARENT)

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
end

-- Game loop flag
local running = false

-- Input handling
function key_handler()
    local handled = false
    while true do
        local key = keys:getkey()
        if key == nil then break end

        print("[ISOQUEST] key_handler() key="..tostring(key).." state="..tostring(state))
        if state == "menu" then
            if key == KEY.SET then
                print("[ISOQUEST] SET pressed → capturing screenshot")

                -- 1. Hide ALL ML + Canon overlays
                print("[ISOQUEST] Overlays hidden")

                -- 2. Trigger autofocus
                -- lens.autofocus()                         
                print("[ISOQUEST] Autofocus started")

                while lens.autofocusing do
                    task.yield(0.1)
                end

                                -- Capture screenshot to valid BMP with proper headers
                menu.close()
                display.clear()
                lv.pause()
                display.screenshot(bmp_path)
                print("[ISOQUEST] Screenshot saved to: " .. bmp_path)

                state = "processing"
                display.print("Processing...", 250, 230, FONT.LARGE, COLOR_TEXT)
                display.print("Please wait...", 260, 270, FONT.MED, COLOR_TEXT)

                -- NOW load the screenshot as BMP
                local ok = generate_level_from_bmp_stream(bmp_path)
                if not ok then
                    print("[ISOQUEST][ERROR] Could not generate level from screenshot.")
                    state = "menu"
                    draw_menu()
                    return true
                end

                -- Start game
                px, py, vx, vy = 80, 300, 0, 0
                state = "playing"
                running = true
                print("[ISOQUEST] Entering PLAYING state (screenshot level)")
                lv.resume()
                draw_level()
                prev_px = px
                prev_py = py
                return true
            elseif key == KEY.INFO then
                print("[ISOQUEST] INFO pressed in MENU → demo level")
                create_demo_level()
                px, py, vx, vy = 80, 300, 0, 0
                state = "playing"
                running = true
                print("[ISOQUEST] Entering PLAYING state (demo level)")
                draw_level()
                prev_px = px
                prev_py = py
                return true
            elseif key == KEY.TRASH then
                print("[ISOQUEST] TRASH pressed → exiting script NOW")
                exit_script = true
                return true
            end

        elseif state == "playing" then
            if key == KEY.LEFT then
                print("[ISOQUEST] LEFT key in PLAYING")
                if on_ground then
                    vx = -5
                else
                    vx = vx - 1.5
                    if vx < -5 then vx = -5 end
                end
                handled = true
            end
            if key == KEY.RIGHT then
                print("[ISOQUEST] RIGHT key in PLAYING")
                if on_ground then
                    vx = 5
                else
                    vx = vx + 1.5
                    if vx > 5 then vx = 5 end
                end
                handled = true
            end
            if key == KEY.UP or key == KEY.SET then
                print("[ISOQUEST] JUMP key in PLAYING, jumps_remaining="..tostring(jumps_remaining))
                if jumps_remaining > 0 then
                    vy = -11
                    jumps_remaining = jumps_remaining - 1
                end
                handled = true
            end
            if key == KEY.MENU then
                print("[ISOQUEST] MENU key in PLAYING → back to menu")
                running = false
                state = "load_menu"
                handled = true
            end
            if key == KEY.PLAY then
                console.show()
            end
        end
    end
    return handled
end


function main()
    print("[ISOQUEST] main() starting up...")
    lv.start()
    keys:start()
    console.hide()
    menu.block(true)

    sleep(0.5)
    display.clear()

    lv.zoom = 1.4

    -- Load custom images
    load_custom_images()

    -- Initialize
    print("========================")
    print("IsoQuest (DEBUG BUILD)")
    print("========================")
    print("")
    print("Press SET to start!")
    print("========================")

    draw_menu()
    state = "menu"

    while true do
        key_handler()

        if running then
            update_player()
            draw_player()
        elseif state == "load_menu" then
            print("[ISOQUEST] Transition state load_menu → menu")
            draw_menu()
            state = "menu"
        end

        if exit_script then
            print("[ISOQUEST] Exiting script as requested.")
            break
        end

        task.yield(20)
    end

    -- Unreachable in practice
    menu.block(false)
    keys:stop()
end

main()
print("[ISOQUEST] main() exited (unexpected)")
