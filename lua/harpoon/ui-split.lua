
local Buffer = require("harpoon.buffer")
local Logger = require("harpoon.logger")
local Extensions = require("harpoon.extensions")

---@class HarpoonToggleOptions
---@field border? any this value is directly passed to nvim_open_win
---@field title_pos? any this value is directly passed to nvim_open_win
---@field title? string this value is directly passed to nvim_open_win
---@field ui_fallback_width? number used if we can't get the current window
---@field ui_width_ratio? number this is the ratio of the editor window to use
---@field ui_max_width? number this is the max width the window can be
---@field height_in_lines? number this is the max height in lines that the window can be

---@return HarpoonToggleOptions
local function toggle_config(config)
    return vim.tbl_extend("force", {
        ui_fallback_width = 69,
        ui_width_ratio = 0.62569,
    }, config or {})
end

---@class HarpoonUISplit
---@field win_id number
---@field split_win_id number
---@field bufnr number
---@field split_bufnr number
---@field settings HarpoonSettings
---@field active_list HarpoonList
---@field split_active_list HarpoonList
local HarpoonUISplit = {}

---@param list HarpoonList
---@return string
local function list_name(list)
    return list and list.name or "nil"
end

HarpoonUISplit.__index = HarpoonUISplit

---@param settings HarpoonSettings
---@return HarpoonUISplit
function HarpoonUISplit:new(settings)
    return setmetatable({
        win_id = nil,
        split_win_id = nil,
        bufnr = nil,
        split_bufnr = nil,
        active_list = nil,
        split_active_list = nil,
        settings = settings,
    }, self)
end

function HarpoonUISplit:split_close()
    if self.split_closing then
        return
    end

    self.split_closing = true
    Logger:log(
        "ui#split_close name: ",
        list_name(self.split_active_list),
        "win and bufnr",
        {
            win = self.split_win_id,
            bufnr = self.split_bufnr,
        }
    )

    local win_id = self.split_win_id
    local bufnr = self.split_bufnr
    self.split_active_list = nil
    self.split_win_id = nil
    self.split_bufnr = nil

    -- Use vim.schedule to defer the buffer deletion to after the current event
    vim.schedule(function()
        if win_id ~= nil and vim.api.nvim_win_is_valid(win_id) then
            pcall(vim.api.nvim_win_close, win_id, true)
        end

        -- Give it a small delay before trying to delete the buffer
        vim.defer_fn(function()
            if bufnr ~= nil and vim.api.nvim_buf_is_valid(bufnr) then
                -- Make the buffer modifiable before deleting it
                pcall(vim.api.nvim_buf_set_option, bufnr, "readonly", false)
                pcall(vim.api.nvim_buf_set_option, bufnr, "modifiable", true)
                pcall(vim.api.nvim_buf_set_option, bufnr, "modified", false)
                
                -- Now delete the buffer
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end, 10) -- 10ms delay
    end)

    self.split_closing = false
end

function HarpoonUISplit:_create_side_split_with_content(list, toggle_opts)
    local win = vim.api.nvim_list_uis()
    -- Default width for the side split - can be adjusted in toggle_opts
    local width = toggle_opts.split_width or 40

    -- Create a new buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Create a vertical split on the right
    vim.cmd("botright vertical split")

    -- Resize the split to the desired width
    vim.cmd("vertical resize " .. width)

    -- Get the window ID of the newly created split
    local win_id = vim.api.nvim_get_current_win()

    -- Set the buffer in the new window
    vim.api.nvim_win_set_buf(win_id, bufnr)

    -- Set buffer options to prevent "No write since last change" error
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")      -- Buffer doesn't represent a file
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)        -- Don't create a swapfile
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")      -- Wipe the buffer when hidden
    
    -- Set the buffer content BEFORE making it readonly
    local contents = list:display()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, contents)
    
    -- Mark as not modified
    vim.api.nvim_buf_set_option(bufnr, "modified", false)
    
    -- NOW make the buffer read-only
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "readonly", true)

    -- Set up the buffer with autocmds and keymaps
    Buffer.setup_autocmds_and_keymaps_split(bufnr)

    -- Set window options
    vim.api.nvim_set_option_value("number", false, { win = win_id }) -- Disable line numbers

    if toggle_opts.set_split_options then
        vim.api.nvim_set_option_value("winfixwidth", true, { win = win_id })
    end

    -- Highlight a specific line (e.g., 3rd line)
    local ns_id = vim.api.nvim_create_namespace("harpoon_highlight")
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "IncSearch", 2, 0, -1) -- Adjust index (0-based)

    return win_id, bufnr
end

function HarpoonUISplit:_create_side_split(toggle_opts)
    local win = vim.api.nvim_list_uis()
    -- Default width for the side split - can be adjusted in toggle_opts
    local width = toggle_opts.split_width or 40

    -- Create a new buffer
    local bufnr = vim.api.nvim_create_buf(false, true)

    -- Create a vertical split on the right
    vim.cmd("botright vertical split")

    -- Resize the split to the desired width
    vim.cmd("vertical resize " .. width)

    -- Get the window ID of the newly created split
    local win_id = vim.api.nvim_get_current_win()

    -- Set the buffer in the new window
    vim.api.nvim_win_set_buf(win_id, bufnr)

    -- Set buffer options to prevent "No write since last change" error
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")      -- Buffer doesn't represent a file
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)        -- Don't create a swapfile
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")      -- Wipe the buffer when hidden
    vim.api.nvim_buf_set_option(bufnr, "modified", false)        -- Mark as not modified

    -- Make the buffer read-only
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "readonly", true)

    -- Set up the buffer with autocmds and keymaps
    Buffer.setup_autocmds_and_keymaps_split(bufnr)

    -- Set window options
    vim.api.nvim_set_option_value("number", false, { win = win_id }) -- Disable line numbers

    if toggle_opts.set_split_options then
        vim.api.nvim_set_option_value("winfixwidth", true, { win = win_id })
    end

    -- Highlight a specific line (e.g., 3rd line)
    local ns_id = vim.api.nvim_create_namespace("harpoon_highlight")
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "IncSearch", 2, 0, -1) -- Adjust index (0-based)

    -- Store window and buffer IDs
    self.split_win_id = win_id
    self.split_bufnr = bufnr

    return win_id, bufnr
end

function HarpoonUISplit:toggle_split(list, opts)
    opts = toggle_config(opts)
    if list == nil or self.split_win_id ~= nil then
        Logger:log("ui#toggle_quick_menu#closing", list and list.name)
        if self.settings.save_on_toggle then
            -- self:save()
        end
        print("toggling split...")
        self:split_close()
        return
    end

    -- grab the current file before opening the quick menu
    local current_file = vim.api.nvim_buf_get_name(0)

    Logger:log("ui#toggle_quick_menu#opening", list and list.name)
    
    -- Create the split - but make sure we don't set readonly until AFTER setting content
    local win_id, bufnr = self:_create_side_split_with_content(list, opts)

    self.split_win_id = win_id
    self.split_bufnr = bufnr
    self.split_active_list = list

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = self.win_id,
        bufnr = self.bufnr,
        current_file = current_file,
        contents = self.split_active_list:display(),
    })
end

function HarpoonUISplit:refresh_content_split()
    if not self.split_active_list or not self.split_bufnr then
        return
    end

    local current_file = vim.api.nvim_buf_get_name(0)
    local contents = self.split_active_list:display()
    
    -- Temporarily make the buffer modifiable to update its contents
    if vim.api.nvim_buf_is_valid(self.split_bufnr) then
        vim.api.nvim_buf_set_option(self.split_bufnr, "readonly", false)
        vim.api.nvim_buf_set_option(self.split_bufnr, "modifiable", true)
        
        -- Update the contents
        vim.api.nvim_buf_set_lines(self.split_bufnr, 0, -1, false, contents)
        
        -- Mark as not modified and make read-only again
        vim.api.nvim_buf_set_option(self.split_bufnr, "modified", false)
        vim.api.nvim_buf_set_option(self.split_bufnr, "modifiable", false)
        vim.api.nvim_buf_set_option(self.split_bufnr, "readonly", true)
    end

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = self.split_win_id,
        bufnr = self.split_bufnr,
        current_file = current_file,
        contents = contents,
    })
end
function HarpoonUISplit:_get_processed_ui_contents()
    local list = Buffer.get_contents(self.bufnr)
    local length = #list
    return list, length
end

---@param options? any
function HarpoonUISplit:select_menu_item(options)
    local idx = vim.fn.line(".")

    -- must first save any updates potentially made to the list before
    -- navigating
    local list, length = self:_get_processed_ui_contents()
    self.active_list:resolve_displayed(list, length)

    Logger:log(
        "ui#select_menu_item selecting item",
        idx,
        "from",
        list,
        "options",
        options
    )

    list = self.active_list
    -- self:close_menu()
    list:select(idx, options)
end

function HarpoonUISplit:save()
    -- split should not be editable
    -- local list, length = self:_get_processed_ui_contents()

    -- Logger:log("ui#save", list)
    -- self.active_list:resolve_displayed(list, length)
    -- if self.settings.sync_on_ui_close then
        -- require("harpoon"):sync()
    -- end
end

---@param settings HarpoonSettings
function HarpoonUISplit:configure(settings)
    self.settings = settings
end

return HarpoonUISplit
