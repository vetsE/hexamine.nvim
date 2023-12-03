local ffi = require("ffi")

local M = {
    -- Buffer ID of the hexamine floating window.
    float_buf = nil,

    -- Window ID of the hexamine floating window.
    float_win = nil,

    -- ID of the autocommand used for updating the
    -- floating window content on cursor movement.
    autocmd_id = nil,

    -- Buffer ID where the hexamine_cursor function was last called.
    -- Used to ensure actions are taken in the correct buffer.
    active_buf = nil,

    -- Window ID where the hexamine_cursor function was last called.
    -- Used to close hexamine float on window change.
    active_win = nil,

    -- Definition of types for conversion.
    default_types = {
        { name = "u8", char_len = 2, fmt = "%02u", fn = "hex_to_u8" },
        { name = "i8", char_len = 2, fmt = "%02d", fn = "hex_to_i8" },
        { name = "u16", char_len = 4, fmt = "%02u", fn = "hex_to_u16" },
        { name = "i16", char_len = 4, fmt = "%02d", fn = "hex_to_i16" },
        { name = "u32", char_len = 8, fmt = "%02u", fn = "hex_to_u32" },
        { name = "i32", char_len = 8, fmt = "%02d", fn = "hex_to_i32" },
        { name = "u64", char_len = 16, fmt = "%02u", fn = "hex_to_u64" },
        { name = "i64", char_len = 16, fmt = "%02d", fn = "hex_to_i64" },
        { name = "float", char_len = 8, fmt = "%e", fn = "hex_to_float" },
        { name = "double", char_len = 16, fmt = "%e", fn = "hex_to_double" },
        { name = "unixtime", char_len = 8, fmt = "%s", fn = "hex_to_unixtime" },
    },

    -- Configuration table, used to store configuration settings.
    config = {},

    -- TODO
    types = {},
}

--- Resets the internal state of the module.
M.reset_state = function()
    M.float_buf = nil
    M.float_win = nil
    M.active_buf = nil
    M.active_win = nil
    M.autocmd_id = nil
end

--- Fetches and formats the content to be displayed in the floating window.
M.get_content = function()
    local headers = { "Type", "Value" }
    local rows = {}

    for _, type in ipairs(M.default_types) do
        local cursor_text, _ = M.get_hex_under_cursor(type.char_len)
        if cursor_text then
            local val, _ = M[type.fn](cursor_text)
            if val then
                table.insert(rows, { [type.name] = string.format(type.fmt, val) })
            end
        end
    end

    return M.serialize_table(headers, rows)
end

--- Add highlights to the float table.
M.add_highlight_to_table = function()
    local highlight_groups = M.config.highlights
    local current_group_index = 1

    -- Start highlighting from the third line (after headers and separator)
    local start_line = 2

    -- Iterate over each content line in the buffer
    for i = start_line, vim.api.nvim_buf_line_count(M.float_buf) - 1 do
        local line = vim.api.nvim_buf_get_lines(M.float_buf, i, i + 1, false)[1]

        -- Find the start and end indices of the table content in the line
        local content_start, content_end = string.find(line, "│.+│")
        if content_start and content_end then
            -- Apply highlighting to the content part of the line only
            vim.api.nvim_buf_add_highlight(
                M.float_buf,
                -1,
                highlight_groups[current_group_index],
                i,
                content_start + 2,
                content_end - 3
            )
        end

        -- Alternate between highlight groups
        current_group_index = 3 - current_group_index -- Switches between 1 and 2
    end
end

--- Opens a hexamine floating window at the cursor position
--
-- @param config Configuration table.
M.hexamine_cursor = function(config)
    -- Only open one float at a time
    if M.float_buf then
        return
    end

    M.config = config
    M.active_buf = vim.api.nvim_get_current_buf()
    M.active_win = vim.api.nvim_get_current_win()

    local lines, max_width = M.get_content()

    -- If we didn't manage to get any text, there's nothing to do
    if not lines then
        return
    end

    -- Create the float
    local float_opts = {
        relative = "cursor",
        row = 1,
        col = 0,
        width = max_width,
        height = #lines,
        style = "minimal",
    }
    M.float_buf = vim.api.nvim_create_buf(false, true)
    M.float_win = vim.api.nvim_open_win(M.float_buf, false, float_opts)

    -- Set the content of the float
    vim.api.nvim_buf_set_lines(M.float_buf, 0, -1, false, lines)
    M.add_highlight_to_table()

    -- Set highlighting to make the float look different from the main buffer
    vim.api.nvim_win_set_option(M.float_win, "winhl", "Normal:Normal")

    -- Set up an autocommand to update the floating window on cursor movement
    M.autocmd_id = vim.api.nvim_create_autocmd("CursorMoved", {
        pattern = "*",
        callback = M.update_float_content_and_position,
    })

    -- Set the float temporary keymaps
    local keymap_opts = { nowait = true, noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(
        M.float_buf,
        "n",
        config.keymap.close,
        ":HexamineClose<CR>",
        keymap_opts
    )
    vim.api.nvim_buf_set_keymap(
        M.active_buf,
        "n",
        config.keymap.close,
        ":HexamineClose<CR>",
        keymap_opts
    )
end

--- Closes the floating window and resets the module state.
M.close_float_and_reset = function()
    -- Close the floating window if it's valid
    if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
        vim.api.nvim_win_close(M.float_win, true)
        vim.api.nvim_buf_del_keymap(M.float_buf, "n", "<Esc>")
    end

    -- Remove the autocommand
    if M.autocmd_id then
        vim.api.nvim_del_autocmd(M.autocmd_id)
    end

    -- Reset the module internal state
    M.reset_state()
end

--- Updates the content of the floating window based on the current cursor position.
--
-- This function is triggered by a CursorMoved autocommand and updates the content
-- of the floating window if the cursor is in the active buffer and window.
M.update_float_content_and_position = function()
    local current_win = vim.api.nvim_get_current_win()
    local current_buf = vim.api.nvim_get_current_buf()

    -- Only update the float if we didn't change buffer or window
    if current_buf ~= M.active_buf or current_win ~= M.active_win then
        -- Close the float if we changed window different than the the plugin's float.
        if current_win ~= M.float_win then
            M.close_float_and_reset()
        end
        return
    end

    local lines, max_width = M.get_content()
    if not lines then
        return
    end

    -- Update the content of the float window if it's valid
    if M.float_buf and vim.api.nvim_buf_is_valid(M.float_buf) then
        vim.api.nvim_buf_set_lines(M.float_buf, 0, -1, false, lines)
        M.add_highlight_to_table()
    end

    -- Update the position of the floating window
    if M.float_win and vim.api.nvim_win_is_valid(M.float_win) then
        local win_height = vim.api.nvim_win_get_height(0)
        local buf_height = vim.api.nvim_buf_line_count(0)
        local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
        local float_height = vim.api.nvim_win_get_height(M.float_win)

        -- Default position is 2 lines below the cursor
        local float_row = 2

        -- Check if there's enough space below the cursor within the viewport
        if cursor_row + float_height + 2 > win_height then
            -- Not enough space below, place the window above the cursor
            -- Adjust so that the window is above the cursor, including a 2-line gap
            float_row = -float_height - 2
        end

        local float_opts = {
            relative = "cursor",
            row = float_row,
            col = 0,
            width = max_width,
            height = #lines,
            style = "minimal",
        }

        -- Update the position of the floating window
        vim.api.nvim_win_set_config(M.float_win, float_opts)
    end
end

M.serialize_table = function(headers, rows)
    local table_lines = {}
    local max_type_width = #headers[1]
    local max_value_width = #headers[2]

    -- Calculate the maximum width for each column
    for _, row in ipairs(rows) do
        for key, value in pairs(row) do
            max_type_width = math.max(max_type_width, #key)
            max_value_width = math.max(max_value_width, #tostring(value))
        end
    end

    -- Helper function to create a row
    local function create_row(col1, col2, end_col)
        local format = "│ %-"
            .. max_type_width
            .. "s │ %-"
            .. max_value_width
            .. "s "
            .. end_col
        return string.format(format, col1, col2)
    end

    -- Top border
    table.insert(
        table_lines,
        "┌"
            .. string.rep("─", max_type_width + 2)
            .. "┬"
            .. string.rep("─", max_value_width + 2)
            .. "┐"
    )

    -- Header row
    table.insert(table_lines, create_row(headers[1], headers[2], "│"))

    -- Separator
    table.insert(
        table_lines,
        "├"
            .. string.rep("─", max_type_width + 2)
            .. "┼"
            .. string.rep("─", max_value_width + 2)
            .. "┤"
    )

    -- Data rows
    for _, row in ipairs(rows) do
        for key, value in pairs(row) do
            table.insert(table_lines, create_row(key, tostring(value), "│"))
        end
    end

    -- Bottom border
    table.insert(
        table_lines,
        "└"
            .. string.rep("─", max_type_width + 2)
            .. "┴"
            .. string.rep("─", max_value_width + 2)
            .. "┘"
    )

    -- Calculate the maximum width of all the lines
    local max_width = max_type_width + max_value_width + 7 -- 7 for borders and separators

    return table_lines, max_width
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

local types = { 1, 2, 4, 8 }
for _, byte_size in ipairs(types) do
    local bit_size = byte_size * 8
    local char_size = byte_size * 2

    M["hex_to_u" .. bit_size] = function(hex_string)
        if #hex_string ~= char_size then
            return nil, "Hex string must be " .. char_size .. " characters long."
        end
        return tonumber(hex_string, 16)
    end

    M["hex_to_i" .. bit_size] = function(hex_string)
        local number = tonumber(hex_string, 16)
        if not number then
            return nil, "Invalid hexadecimal number"
        end

        local max_value = 2 ^ (bit_size - 1)
        if number >= max_value then
            number = number - 2 * max_value
        end

        return number
    end
end

--- Converts a hexadecimal string to a 32-bit floating-point number.
--
-- @param hex_string The hexadecimal string to be converted.
-- @return The floating-point number, or nil if the conversion fails.
M.hex_to_float = function(hex_string)
    if #hex_string ~= 8 then
        return nil, "Hex string must be 8 characters long to represent a 32-bit float."
    end

    local num = ffi.new("uint32_t", tonumber(hex_string, 16))
    local float_ptr = ffi.cast("float*", ffi.new("uint32_t[1]", num))
    return tonumber(float_ptr[0])
end

--- Converts a hexadecimal string to a 64-bit double-precision floating-point number.
--
-- @param hex_string The hexadecimal string to be converted.
-- @return The double-precision floating-point number, or nil if the conversion fails.
M.hex_to_double = function(hex_string)
    if #hex_string ~= 16 then
        return nil, "Hex string must be 16 characters long to represent a 64-bit double."
    end

    local high_part = tonumber(hex_string:sub(1, 8), 16)
    local low_part = tonumber(hex_string:sub(9, 16), 16)
    local num = ffi.new("uint64_t[1]", high_part)
    num[0] = num[0] * (2 ^ 32) + low_part
    local double_ptr = ffi.cast("double*", num)
    local nbr = tonumber(double_ptr[0])
    if nbr ~= nbr then
        return nil
    end
    return nbr
end

--- Converts a hexadecimal string to a Unix timestamp and formats it as a human-readable date string.
--
-- @param hex_string The hexadecimal string representing the Unix timestamp.
-- @return A formatted date string representing the Unix timestamp.
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

return M
