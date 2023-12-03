local hexamine = require("hexamine.module")

local M = {}

M.config = {
    keymap = {
        close = "<Esc>", -- Default key for closing the floating window
    },
    highlights = { "Normal", "Search" },
    -- extra_types = {},
}

M.setup = function(args)
    M.config = vim.tbl_deep_extend("force", M.config, args or {})

    vim.api.nvim_create_user_command("Hexamine", function()
        hexamine.hexamine_cursor(M.config)
    end, {})
    vim.api.nvim_create_user_command("HexamineClose", hexamine.close_float_and_reset, {})
end

return M
