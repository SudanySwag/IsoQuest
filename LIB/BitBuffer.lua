local BitBuffer = {
    File = nil,           -- File handle instead of complete data
    Buffer = "",          -- Small read buffer (4-8KB)
    BufferSize = 512,    -- 8KB buffer size
    BufferPos = 1,        -- Current position in buffer
    TotalBytesRead = 0,   -- Track total bytes read from file
    Bit = 0,
    CurrentByte = 0,
    EOF = false
}

BitBuffer.__index = BitBuffer

-- Create buffer from file handle instead of data string
function BitBuffer.NewFromFile(file_handle, buffer_size)
    local Buffer = setmetatable({}, BitBuffer)
    
    Buffer.File = file_handle
    Buffer.BufferSize = buffer_size or 512  -- Default 8KB
    Buffer.Buffer = ""
    Buffer.BufferPos = 1
    Buffer.TotalBytesRead = 0
    Buffer.Bit = 0
    Buffer.CurrentByte = 0
    Buffer.EOF = false
    
    -- Read first chunk
    Buffer:RefillBuffer()
    
    return Buffer
end

-- Refill buffer from file when needed
function BitBuffer:RefillBuffer()
    if not self.File or self.EOF then
        return false
    end
    
    -- Read next chunk from file
    local chunk = self.File:read(self.BufferSize)
    
    if not chunk or #chunk == 0 then
        self.EOF = true
        self.Buffer = ""
        return false
    end
    
    self.Buffer = chunk
    self.BufferPos = 1
    
    -- Optional: Force GC every few refills to keep memory low
    if self.TotalBytesRead % (self.BufferSize * 10) == 0 then
        collectgarbage("step", 100)
    end
    
    return true
end

-- Get one byte from buffer (refill if needed)
function BitBuffer:GetByte()
    -- Check if we need to refill buffer
    if self.BufferPos > #self.Buffer then
        if not self:RefillBuffer() then
            return nil  -- EOF
        end
    end
    
    local byte = self.Buffer:byte(self.BufferPos)
    self.BufferPos = self.BufferPos + 1
    self.TotalBytesRead = self.TotalBytesRead + 1
    
    return byte
end

function BitBuffer:ReadBit()
    if (self.Bit == 0) then
        self.Bit = 0
        local NextByte = self:GetByte()
        
        if not NextByte then
            error("Unexpected end of file", 1)
        end

        if (NextByte == 0x00 and self.CurrentByte == 0xFF) then
            NextByte = self:GetByte()
            if not NextByte then
                error("Unexpected end of file", 1)
            end
        elseif (self.CurrentByte == 0xFF) then
            error("Unexpected marker in entropy stream: "..tostring(self.CurrentByte), 1)
        end

        self.CurrentByte = NextByte
    end

    local Bit = (self.CurrentByte >> (7 - self.Bit)) & 1
    self.Bit = (self.Bit + 1) & 0x7

    return Bit
end

function BitBuffer:ReadBits(NumBits)
    local Bits = 0

    for i = 1, NumBits, 1 do
        Bits = (Bits << 1) | self:ReadBit()
    end

    return Bits
end

function BitBuffer:ReadBytes(NumBytes)
    if (self.Bit ~= 0) then
        self:Align()
    end

    local Bytes = 0

    for i = 1, NumBytes, 1 do
        local byte = self:GetByte()
        if not byte then
            error("Unexpected end of file", 1)
        end
        self.CurrentByte = byte
        Bytes = (Bytes << 8) | self.CurrentByte
    end

    return Bytes
end

function BitBuffer:Align()
    self.Bit = 0
end

function BitBuffer:IsEmpty()
    -- Check if buffer is exhausted AND file is at EOF
    return self.EOF and self.BufferPos > #self.Buffer
end

-- Keep old constructor for compatibility (loads entire data)
function BitBuffer.New(Data)
    local Buffer = setmetatable({}, BitBuffer)
    
    -- Convert to buffered approach internally
    Buffer.Buffer = Data
    Buffer.BufferPos = 1
    Buffer.File = nil
    Buffer.EOF = true  -- No file, so "EOF" after buffer is consumed
    Buffer.Bit = 0
    Buffer.CurrentByte = 0
    Buffer.TotalBytesRead = 0
    
    return Buffer
end

return BitBuffer
