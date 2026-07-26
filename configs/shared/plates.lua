local Config = require "configs.shared.main"

local M = {}

local LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
local DIGITS  = '0123456789'

---Generates one plate from the given pattern (defaults to Config.platePattern).
---Pattern characters: A = random letter, 1 = random digit, anything else = literal.
---GTA plate textures are 8 characters; the pattern should be exactly 8 characters.
---@param pattern string?
---@return string
function M.generate(pattern)
    pattern = pattern or Config.platePattern
    local out = {}
    for i = 1, #pattern do
        local c = pattern:sub(i, i)
        if c == 'A' then
            local r = math.random(1, #LETTERS)
            out[i] = LETTERS:sub(r, r)
        elseif c == '1' then
            local r = math.random(1, #DIGITS)
            out[i] = DIGITS:sub(r, r)
        else
            out[i] = c
        end
    end
    return table.concat(out)
end

---@param plate string
---@param pattern string?
---@return boolean
function M.isValid(plate, pattern)
    pattern = pattern or Config.platePattern
    if type(plate) ~= 'string' or #plate ~= 8 then return false end
    for i = 1, #pattern do
        local pc = pattern:sub(i, i)
        local vc = plate:sub(i, i)
        if pc == 'A' then
            if not vc:match('%u') then return false end
        elseif pc == '1' then
            if not vc:match('%d') then return false end
        else
            if vc ~= pc then return false end
        end
    end
    return true
end

return M
