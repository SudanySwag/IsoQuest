print("[BMP] Loader loaded")

local bmp_header_offset       = 0
local bmp_header_pixel_offset = 10
local bmp_header_width        = 18
local bmp_header_height       = 22
local bmp_header_bpp          = 28
local bmp_header_compression  = 30

local function get_data_size(width, height, bpp)
    return math.ceil(width/4)*4 * height * (bpp/8)
end


--------------------------------------------------------------------
-- new_bitmap()
--------------------------------------------------------------------
local function new_bitmap()
    local bmp = {}

    function bmp:read(offset)
        if not self.data[offset] then
            print("[BMP] read(): nil byte at offset " .. offset)
            return nil
        end
        return self.data[offset]:byte()
    end

    function bmp:read_word(offset)
        local b1 = self:read(offset)
        local b2 = self:read(offset+1)
        if not b1 or not b2 then
            print("[BMP] read_word(): failed at " .. offset)
            return nil
        end
        return b2*256 + b1
    end

    function bmp:read_dword(offset)
        local b1 = self:read(offset)
        local b2 = self:read(offset+1)
        local b3 = self:read(offset+2)
        local b4 = self:read(offset+3)
        if not (b1 and b2 and b3 and b4) then
            print("[BMP] read_dword(): failed at " .. offset)
            return nil
        end
        return b4*0x1000000 + b3*0x10000 + b2*0x100 + b1
    end

    function bmp:read_header()
        print("[BMP] Reading header...")

        local magic = self:read_word(bmp_header_offset)
        if magic ~= 0x4D42 then
            print("[BMP] ERROR: Bad magic header ("..tostring(magic)..")")
            return nil, "Bad magic header"
        end

        local compression = self:read_dword(bmp_header_compression)
        if compression ~= 0 then
            print("[BMP] ERROR: Unsupported compression = "..tostring(compression))
            return nil, "Unsupported compression"
        end

        self.bpp = self:read_word(bmp_header_bpp)
        print("[BMP] bpp = " .. tostring(self.bpp))
        if self.bpp ~= 24 and self.bpp ~= 32 then
            print("[BMP] ERROR: Unsupported bpp")
            return nil, "Unsupported bpp"
        end

        self.pixel_offset = self:read_dword(bmp_header_pixel_offset)
        print("[BMP] pixel_offset = "..tostring(self.pixel_offset))

        self.width  = self:read_dword(bmp_header_width)
        self.height = self:read_dword(bmp_header_height)
        print("[BMP] width="..tostring(self.width).." height="..tostring(self.height))

        if not self.width or not self.height then
            print("[BMP] ERROR: Failed to read width/height")
            return nil, "Invalid dimension"
        end

        self.topdown = true
        if self.height < 0 then
            print("[BMP] bottom-up BMP detected")
            self.topdown = false
            self.height = -self.height
        end

        self.data_size = get_data_size(self.width, self.height, self.bpp)
        print("[BMP] data_size = "..tostring(self.data_size))

        print("[BMP] Header OK")
        return true
    end

    return bmp
end


--------------------------------------------------------------------
-- new_bitmap_from_string()
--------------------------------------------------------------------
local function new_bitmap_from_string(data)
    print("[BMP] from_string() size="..tostring(#data))

    local bmp = new_bitmap()
    bmp.data = {}

    for i=1, #data do
        bmp.data[i-1] = data:sub(i,i)
    end

    local ok, err = bmp:read_header()
    if not ok then
        print("[BMP] ERROR in header: " .. tostring(err))
        return nil, err
    end

    return bmp
end


--------------------------------------------------------------------
-- new_bitmap_from_file()
--------------------------------------------------------------------
local function new_bitmap_from_file(path)
    print("[BMP] Loading file: " .. path)

    local f = io.open(path, "rb")
    if not f then
        print("[BMP] ERROR: cannot open file")
        return nil, "open failed"
    end

    local data = f:read("*a")
    f:close()

    if not data or #data == 0 then
        print("[BMP] ERROR: file empty")
        return nil, "empty file"
    end

    print("[BMP] File OK, size="..#data)

    return new_bitmap_from_string(data)
end


return {
    from_file   = new_bitmap_from_file,
    from_string = new_bitmap_from_string,
}
