local ffi = require("ffi")

local M = {}

M.get_hex_under_cursor = function(n)
    -- Get the current line and cursor position
    local line = vim.api.nvim_get_current_line()
    local col = vim.api.nvim_win_get_cursor(0)[2] + 1

    -- Get 'n' characters from the current cursor position
    local hex_candidate = line:sub(col, col + n - 1)

    -- Check if the obtained string is a valid hexadecimal
    if hex_candidate:match("^%x+$") and #hex_candidate == n then
        return hex_candidate
    else
        return nil, "Invalid hexadecimal or insufficient characters"
    end
end

M.swap_endianess = function(hex_string)
    if #hex_string % 2 ~= 0 then
        return nil, "Hex string length must be even to swap endianness."
    end

    local bytes = {}
    for byte in hex_string:gmatch("..") do
        table.insert(bytes, 1, byte)
    end

    local swapped_string = table.concat(bytes)
    return swapped_string
end

local types = { 1, 2, 4, 8 }
for _, bytes in ipairs(types) do
    local ctype = "int" .. (bytes * 8) .. "_t"
    M["hex_to_int" .. bytes * 8] = function(hex_string)
        if #hex_string ~= bytes * 2 then
            return nil, "Hex string must be " .. (bytes * 2) .. " characters long."
        end
        -- Convert the hex string directly to the corresponding integer type
        local num = ffi.new(ctype)
        num = ffi.cast(ctype, tonumber(hex_string, 16))
        return num
    end

    M["hex_to_uint" .. size] = function(hex_string)
        if #hex_string ~= size * 2 then
            return nil, "Hex string must be " .. (size * 2) .. " characters long."
        end

        -- Reverse hex for little-endian and convert to binary string
        local bin_string = reverse_hex(hex_string)
        local num = ffi.new("uint" .. (size * 8) .. "_t[1]")
        ffi.copy(num, ffi.cast("const char *", bin_string), size)
        return num[0]
    end
end

M.hex_to_float = function(hex_string)
    if #hex_string ~= 8 then
        return nil, "Hex string must be 8 characters long to represent a 32-bit float."
    end

    local num = ffi.new("uint32_t", tonumber(hex_string, 16))
    local float_ptr = ffi.cast("float*", ffi.new("uint32_t[1]", num))
    return float_ptr[0]
end

M.hex_to_double = function(hex_string)
    if #hex_string ~= 16 then
        return nil, "Hex string must be 16 characters long to represent a 64-bit double."
    end

    local high_part = tonumber(hex_string:sub(1, 8), 16)
    local low_part = tonumber(hex_string:sub(9, 16), 16)
    local num = ffi.new("uint64_t[1]", high_part)
    num[0] = num[0] * (2 ^ 32) + low_part
    local double_ptr = ffi.cast("double*", num)
    return double_ptr[0]
end

M.hex_to_unixtime = function(hex_string)
    if #hex_string ~= 8 then
        return nil, "Hex string must be 8 characters long to represent a 32-bit Unix timestamp."
    end

    local timestamp = tonumber(hex_string, 16)
    if not timestamp then
        return nil, "Invalid hexadecimal value."
    end

    -- Convert the timestamp to a date table
    local date_table = os.date("*t", timestamp)
    -- Return the date in a human-readable format
    return os.date("%Y-%m-%d %H:%M:%S", timestamp), date_table
end

-- Function to perform all conversions on hex string under cursor
M.convert_hex_under_cursor_all = function()
    local conversions = {}
    local lengths = { 16, 8, 4, 2 } -- Possible lengths of hex strings for conversion
    local hex_string_full, hex_err
    local hex_string

    -- Try to get as many characters as possible
    for _, length in ipairs(lengths) do
        hex_string_full, hex_err = M.get_hex_under_cursor(length)
        if hex_string_full then
            hex_string = hex_string_full -- Use the successfully fetched string
            break -- Exit loop if we've got a valid string
        end
    end

    -- If no valid hex string could be fetched, return the error
    if not hex_string then
        return nil, hex_err
    end

    -- Function to safely perform conversion and capture the result
    local function safe_conversion(convert_func, hex_str)
        if not hex_str or #hex_str == 0 then
            return "?"
        end -- Return "?" if string is empty
        local status, result = pcall(convert_func, hex_str)
        return status and result or "?" -- Return "?" if conversion fails
    end

    -- Perform conversions for each type and endianness, adjust string length as needed
    for _, length in ipairs(lengths) do
        local sub_hex_string = hex_string:sub(1, length)
        if length == 16 then
            -- Perform 64-bit conversions
            table.insert(conversions, {
                type = "double",
                value = safe_conversion(M.hex_to_double, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "uint64_t",
                value = safe_conversion(M.hex_to_uint64, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "int64_t",
                value = safe_conversion(M.hex_to_int64, sub_hex_string),
                hex = sub_hex_string,
            })
        elseif length == 8 then
            -- Perform 32-bit conversions
            table.insert(conversions, {
                type = "float",
                value = safe_conversion(M.hex_to_float, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "uint32_t",
                value = safe_conversion(M.hex_to_uint32, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "int32_t",
                value = safe_conversion(M.hex_to_int32, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "unixtime",
                value = safe_conversion(M.hex_to_unixtime, sub_hex_string),
                hex = sub_hex_string,
            })
        elseif length == 4 then
            -- Perform 16-bit conversions
            table.insert(conversions, {
                type = "uint16_t",
                value = safe_conversion(M.hex_to_uint16, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "int16_t",
                value = safe_conversion(M.hex_to_int16, sub_hex_string),
                hex = sub_hex_string,
            })
        elseif length == 2 then
            -- Perform 8-bit conversions
            table.insert(conversions, {
                type = "uint8_t",
                value = safe_conversion(M.hex_to_uint8, sub_hex_string),
                hex = sub_hex_string,
            })
            table.insert(conversions, {
                type = "int8_t",
                value = safe_conversion(M.hex_to_int8, sub_hex_string),
                hex = sub_hex_string,
            })
        end
    end

    return conversions
end

return M
