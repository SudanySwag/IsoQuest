--[[
IsoQuest
]]

require("keys")
local DecodeJpeg = require("DecodeJpeg") 

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
local jumps_remaining = 2
local prev_px, prev_py = 100, 200

-- RGB color helper
local function rgb(r, g, b)
    return (r * 65536) + (g * 256) + b
end

local COLOR_SKY = rgb(135, 206, 235)
local COLOR_PLATFORM = rgb(139, 69, 19)
local COLOR_PLAYER = rgb(255, 50, 50)
local COLOR_TEXT = rgb(255, 255, 255)
local COLOR_MENU_BG = rgb(50, 50, 50)
local COLOR_GROUND = rgb(101, 67, 33)

-- Packed level storage
function init_level()
    for y = 1, ROWS do
        level[y] = string.rep("\0", COLS)
    end
end

local function set_tile(x, y, val)
    if y < 1 or y > ROWS or x < 1 or x > COLS then return end
    local row = level[y]
    level[y] = row:sub(1, x-1) .. (val == 1 and "\1" or "\0") .. row:sub(x+1)
end

local function get_tile(x, y)
    if y < 1 or y > ROWS or x < 1 or x > COLS then return 0 end
    return level[y]:byte(x) or 0
end

-- STREAMING EDGE DETECTION
-- This accumulates edge statistics without storing full pixels
local edge_accumulator = {}
local img_width, img_height = 0, 0

function init_edge_accumulator()
    edge_accumulator = {}
    for ty = 1, ROWS do
        edge_accumulator[ty] = {}
        for tx = 1, COLS do
            edge_accumulator[ty][tx] = {
                samples = 0,
                edge_count = 0,
                prev_brightness = nil
            }
        end
    end
end

-- Block callback function for streaming processing
function process_block_for_edges(block, block_x, block_y, block_w, block_h, channel)
    -- Only process luminance channel (Y = channel 1)
    if channel ~= 1 then return end
    
    -- Extract edge information from this 8x8 block
    local threshold = 30
    
    -- Sample multiple points in the block
    for by = 0, 7, 2 do  -- Sample every 2nd pixel
        for bx = 0, 7, 2 do
            local pixel_x = block_x + math.floor(bx * block_w / 8)
            local pixel_y = block_y + math.floor(by * block_h / 8)
            
            -- Map to tile coordinates
            local tile_x = math.floor(pixel_x / TILE) + 1
            local tile_y = math.floor(pixel_y / TILE) + 1
            
            if tile_x >= 1 and tile_x <= COLS and tile_y >= 1 and tile_y <= ROWS then
                local brightness = block[by * 8 + bx + 1]
                local acc = edge_accumulator[tile_y][tile_x]
                
                -- Check for edge with previous pixel
                if acc.prev_brightness then
                    if math.abs(brightness - acc.prev_brightness) > threshold then
                        acc.edge_count = acc.edge_count + 1
                    end
                end
                
                acc.samples = acc.samples + 1
                acc.prev_brightness = brightness
            end
        end
    end
end

-- Convert edge accumulator to level tiles
function finalize_edge_detection()
    for ty = 1, ROWS do
        for tx = 1, COLS do
            local acc = edge_accumulator[ty][tx]
            if acc.samples > 0 then
                local edge_ratio = acc.edge_count / acc.samples
                if edge_ratio > 0.15 then  -- 15% edge threshold
                    set_tile(tx, ty, 1)
                end
            end
        end
    end
    
    -- Clear accumulator to free memory
    edge_accumulator = nil
    collectgarbage("collect")
end

-- STREAMING CAPTURE AND DECODE
function capture_and_detect_edges()
    print("Capturing image...")

    local image_path
    
    if camera and camera.shoot then
        camera.shoot()
        camera.wait()
        
        if dryos.sd_card then
            image_path = dryos.sd_card:image_path(0)
        elseif dryos.cf_card then
            image_path = dryos.cf_card:image_path(0)
        else
            print("No card found!")
            create_demo_level()
            return true
        end
        
        print("Image: " .. image_path)
    else
        print("Camera not available - using demo")
        create_demo_level()
        return true
    end

    print("Reading image file...")
    local file = io.open(image_path, "rb")
    if not file then
        print("Failed to open image!")
        create_demo_level()
        return true
    end
    
    print("Streaming decode...")
    print("This may take 30-60 seconds...")
    
    -- Initialize level and edge accumulator
    init_level()
    init_edge_accumulator()
    
    -- Force GC before decode
    collectgarbage("collect")
    
    -- STREAMING DECODE: Blocks are processed as they're decoded
    local success, Info = pcall(function()
        return DecodeJpeg(jpeg_binary, process_block_for_edges)
    end)
  
    
    -- Free JPEG data immediately
    file:close()
    collectgarbage("collect")
    
    if not success then
        print("JPEG decode failed: " .. tostring(Info))
        create_demo_level()
        return true
    end
    
    print("Decoded: " .. Info.X .. "x" .. Info.Y)
    print("Finalizing edges...")
    
    img_width = Info.X
    img_height = Info.Y
    
    -- Convert edge accumulator to level tiles
    finalize_edge_detection()
    
    -- Free image info
    Info = nil
    collectgarbage("collect")
    
    -- Add ground
    for x = 1, COLS do
        set_tile(x, ROWS, 1)
        set_tile(x, ROWS-1, 1)
    end

    -- Thicken platforms
    for ty = 1, ROWS - 2 do
        for tx = 1, COLS do
            if get_tile(tx, ty) == 1 and get_tile(tx, ty+1) == 0 then
                set_tile(tx, ty+1, 1)
            end
        end
    end

    -- Add walls
    for y = 1, ROWS do
        set_tile(1, y, 1)
        set_tile(2, y, 1)
        set_tile(COLS, y, 1)
        set_tile(COLS-1, y, 1)
    end

    print("Level generated!")
    collectgarbage("collect")
    return true
end

-- [Keep all other functions the same: create_demo_level, is_solid, 
--  update_player, draw_level, draw_player, draw_menu, key_handler, main]

function create_demo_level()
    console.show()
    print("Loading demo level...")
    init_level()
    for x = 1, COLS do
        set_tile(x, ROWS, 1)
        set_tile(x, ROWS-1, 1)
    end
    for x = 8, 15 do set_tile(x, 22, 1) set_tile(x, 23, 1) end
    for x = 18, 25 do set_tile(x, 18, 1) set_tile(x, 19, 1) end
    for x = 28, 35 do set_tile(x, 15, 1) set_tile(x, 16, 1) end
    for x = 10, 17 do set_tile(x, 12, 1) set_tile(x, 13, 1) end
    for y = 1, ROWS do
        set_tile(1, y, 1)
        set_tile(2, y, 1)
        set_tile(COLS, y, 1)
        set_tile(COLS-1, y, 1)
    end
    print("Demo ready!")
end

function is_solid(x, y)
    local tx = math.floor(x / TILE) + 1
    local ty = math.floor(y / TILE) + 1
    if tx < 1 or tx > COLS or ty < 1 or ty > ROWS then return true end
    return get_tile(tx, ty) == 1
end

function update_player()
    vy = vy + 0.8
    if vy > 15 then vy = 15 end
    px = px + vx
    local l, r = px - player_size/2, px + player_size/2
    local t, b = py - player_size/2, py + player_size/2
    if is_solid(l, py) or is_solid(r, py) then
        px = px - vx
        vx = 0
    end
    py = py + vy
    on_ground = false
    l, r = px - player_size/2, px + player_size/2
    t, b = py - player_size/2, py + player_size/2
    if is_solid(l, b) or is_solid(r, b) then
        if vy > 0 then
            py = math.floor(b / TILE) * TILE - player_size/2
            vy = 0
            on_ground = true
            jumps_remaining = 2
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
        vx = vx * 0.85
    end
    if vx > 6 then vx = 6 end
    if vx < -6 then vx = -6 end
end

function draw_level()
    display.clear()
    display.rect(0, 0, W, H, COLOR.TRANSPARENT, COLOR.TRANSPARENT)
    for ty = 1, ROWS do
        for tx = 1, COLS do
            if get_tile(tx, ty) == 1 then
                local sx = (tx - 1) * TILE
                local sy = (ty - 1) * TILE
                local color = (ty >= ROWS - 1) and COLOR_GROUND or COLOR_PLATFORM
                display.rect(sx, sy, TILE, TILE, rgb(80, 40, 10), color)
            end
        end
    end
    display.rect(5, 5, 200, 40, COLOR_TEXT, COLOR_MENU_BG)
    display.print("ISOQuest", 10, 10, FONT.MED, COLOR_TEXT)
    display.print("MENU to exit", 10, 28, FONT.SMALL, COLOR_TEXT)
end

function draw_player()
    display.rect(prev_px - player_size/2 - 1, prev_py - player_size/2 - 1,
                player_size + 2, player_size + 2, COLOR.TRANSPARENT, COLOR.TRANSPARENT)
    local prev_tile_x = math.floor(prev_px / TILE) + 1
    local prev_tile_y = math.floor(prev_py / TILE) + 1
    for dy = -1, 1 do
        for dx = -1, 1 do
            local ty = prev_tile_y + dy
            local tx = prev_tile_x + dx
            if ty >= 1 and ty <= ROWS and tx >= 1 and tx <= COLS and get_tile(tx, ty) == 1 then
                local sx = (tx - 1) * TILE
                local sy = (ty - 1) * TILE
                local color = (ty >= ROWS - 1) and COLOR_GROUND or COLOR_PLATFORM
                display.rect(sx, sy, TILE, TILE, rgb(80, 40, 10), color)
            end
        end
    end
    display.rect(px - player_size/2 - 1, py - player_size/2 - 1,
                player_size + 2, player_size + 2, COLOR_TEXT, COLOR_TEXT)
    display.rect(px - player_size/2, py - player_size/2,
                player_size, player_size, rgb(180, 0, 0), COLOR_PLAYER)
    prev_px = px
    prev_py = py
end

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

local running = false

function key_handler()
    while true do
        local key = keys:getkey()
        if key == nil then break end
        if state == "menu" then
            if key == KEY.SET then
                state = "processing"
                display.clear()
                display.rect(0, 0, W, H, COLOR_SKY, COLOR_SKY)
                display.print("Processing...", 250, 230, FONT.LARGE, COLOR_TEXT)
                display.print("Streaming decode...", 240, 270, FONT.MED, COLOR_TEXT)
                task.yield(100)
                capture_and_detect_edges()
                px, py, vx, vy = 80, 300, 0, 0
                state = "playing"
                running = true
                draw_level()
                prev_px = px
                prev_py = py
                return true
            elseif key == KEY.INFO then
                create_demo_level()
                px, py, vx, vy = 80, 300, 0, 0
                state = "playing"
                running = true
                draw_level()
                prev_px = px
                prev_py = py
                return true
            end
        elseif state == "playing" then
            if key == KEY.LEFT then
                vx = on_ground and -5 or math.max(vx - 1.5, -5)
            end
            if key == KEY.RIGHT then
                vx = on_ground and 5 or math.min(vx + 1.5, 5)
            end
            if key == KEY.UP or key == KEY.SET then
                if jumps_remaining > 0 then
                    vy = -11
                    jumps_remaining = jumps_remaining - 1
                end
            end
            if key == KEY.MENU then
                running = false
                state = "load_menu"
            end
            if key == KEY.PLAY then
                console.show()
            end
        end
    end
    return false
end

function main()
    keys:start()
    menu.block(true)
    lv.start()
    sleep(0.5)
    display.clear()
    print("========================")
    print("IsoQuest")
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
            draw_menu()
            state = "menu"
        end
        task.yield(20)
    end
    menu.block(false)
    keys:stop()
end

main()
