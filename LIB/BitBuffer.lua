local BitBuffer = {
    File = nil,
    ByteArray = nil,      -- Byte array instead of string
    BufferSize = 4096,    -- 4KB default (good balance)
    BufferPos = 1,
    BufferLen = 0,        -- Actual bytes in buffer
    Bit = 0,
    CurrentByte = 0,
    EOF = false,
    RefillCount = 0       -- Track refills for GC
}
BitBuffer.__index = BitBuffer

-- Create buffer from file handle
function BitBuffer.NewFromFile(file_handle, buffer_size)
    local Buffer = setmetatable({}, BitBuffer)
    
    Buffer.File = file_handle
    Buffer.BufferSize = buffer_size or 4096
    Buffer.ByteArray = {}  -- Pre-allocate table
    Buffer.BufferPos = 1
    Buffer.BufferLen = 0
    Buffer.Bit = 0
    Buffer.CurrentByte = 0
    Buffer.EOF = false
    Buffer.RefillCount = 0
    
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
        self.BufferLen = 0
        return false
    end
    
    -- Convert string to byte array ONCE
    self.BufferLen = #chunk
    for i = 1, self.BufferLen do
        self.ByteArray[i] = chunk:byte(i)
    end
    
    -- Clear string immediately
    chunk = nil
    
    self.BufferPos = 1
    self.RefillCount = self.RefillCount + 1
    
    -- More aggressive GC for memory-constrained environments
    if self.RefillCount % 5 == 0 then
        collectgarbage("step", 50)
    end
    
    return true
end

-- Get one byte from buffer (refill if needed)
function BitBuffer:GetByte()
    -- Check if we need to refill buffer
    if self.BufferPos > self.BufferLen then
        if not self:RefillBuffer() then
            return nil  -- EOF
        end
    end
    
    local byte = self.ByteArray[self.BufferPos]
    self.BufferPos = self.BufferPos + 1
    
    return byte
end

function BitBuffer:ReadBit()
    if self.Bit == 0 then
        self.Bit = 0
        local NextByte = self:GetByte()
        
        if not NextByte then
            error("Unexpected end of file", 1)
        end
        
        if NextByte == 0x00 and self.CurrentByte == 0xFF then
            NextByte = self:GetByte()
            if not NextByte then
                error("Unexpected end of file", 1)
            end
        elseif self.CurrentByte == 0xFF then
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
    for i = 1, NumBits do
        Bits = (Bits << 1) | self:ReadBit()
    end
    return Bits
end

function BitBuffer:ReadBytes(NumBytes)
    if self.Bit ~= 0 then
        self:Align()
    end
    
    local Bytes = 0
    for i = 1, NumBytes do
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
    return self.EOF and self.BufferPos > self.BufferLen
end

-- Optional: Manual cleanup
function BitBuffer:Close()
    self.ByteArray = nil
    self.File = nil
    collectgarbage("collect")
end

return BitBuffer