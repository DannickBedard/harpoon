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

---@class HarpoonUI
---@field win_id number
---@field split_win_id number
---@field bufnr number
---@field split_bufnr number
---@field settings HarpoonSettings
---@field active_list HarpoonList
---@field split_active_list HarpoonList
local HarpoonUI = {}

---@param list HarpoonList
---@return string
local function list_name(list)
    return list and list.name or "nil"
end

HarpoonUI.__index = HarpoonUI

---@param settings HarpoonSettings
---@return HarpoonUI
function HarpoonUI:new(settings)
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
function HarpoonUI:close_menu()
    if self.closing then
        return
    end

    self.closing = true
    Logger:log(
        "ui#close_menu name: ",
        list_name(self.active_list),
        "win and bufnr",
        {
            win = self.win_id,
            bufnr = self.bufnr,
        }
    )

    if self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
        vim.api.nvim_buf_delete(self.bufnr, { force = true })
    end

    if self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id) then
        vim.api.nvim_win_close(self.win_id, true)
    end

    self.active_list = nil
    self.win_id = nil
    self.bufnr = nil

    self.closing = false
end

function HarpoonUI:split_close()
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

    -- if self.bufnr ~= nil and vim.api.nvim_buf_is_valid(self.bufnr) then
    --     vim.api.nvim_buf_delete(self.bufnr, { force = true })
    -- end

    -- if self.win_id ~= nil and vim.api.nvim_win_is_valid(self.win_id) then
    --     vim.api.nvim_win_close(self.win_id, true)
    -- end
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
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end, 10) -- 10ms delay
    end)

    self.split_closing = false
end

--- TODO: Toggle_opts should be where we get extra style and border options
--- and we should create a nice minimum window
---@param toggle_opts HarpoonToggleOptions
---@return number,number
function HarpoonUI:_create_window(toggle_opts)
    local win = vim.api.nvim_list_uis()

    local width = toggle_opts.ui_fallback_width

    if #win > 0 then
        -- no ackshual reason for 0.62569, just looks complicated, and i want
        -- to make my boss think i am smart
        width = math.floor(win[1].width * toggle_opts.ui_width_ratio)
    end

    if toggle_opts.ui_max_width and width > toggle_opts.ui_max_width then
        width = toggle_opts.ui_max_width
    end

    local height = toggle_opts.height_in_lines or 8 -- 8 lines is default height
    local bufnr = vim.api.nvim_create_buf(false, true)
    local win_id = vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        title = toggle_opts.title or "Harpoon",
        title_pos = toggle_opts.title_pos or "left",
        row = math.floor(((vim.o.lines - height) / 2) - 1),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = toggle_opts.border or "single",
    })

    if win_id == 0 then
        Logger:log(
            "ui#_create_window failed to create window, win_id returned 0"
        )
        self.bufnr = bufnr
        self:close_menu()
        error("Failed to create window")
    end

    Buffer.setup_autocmds_and_keymaps(bufnr)

    self.win_id = win_id
    vim.api.nvim_set_option_value("number", true, {
        win = win_id,
    })

    return win_id, bufnr
end

function HarpoonUI:_create_side_split(toggle_opts)
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

    -- Set up the buffer with autocmds and keymaps
    Buffer.setup_autocmds_and_keymaps_split(bufnr)

    -- Set window options
    vim.api.nvim_set_option_value("number", true, {
        win = win_id,
    })

    -- Additional options you might want to set
    if toggle_opts.set_split_options then
        vim.api.nvim_set_option_value("winfixwidth", true, {
            win = win_id,
        })
    end

    -- Ensure the buffer stays open
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")

    -- Set window options
    vim.api.nvim_set_option_value("number", false, { win = win_id }) -- Disable line numbers

    if toggle_opts.set_split_options then
        vim.api.nvim_set_option_value("winfixwidth", true, { win = win_id })
    end

    -- Highlight a specific line (e.g., 3rd line)
    local ns_id = vim.api.nvim_create_namespace("harpoon_highlight")
    vim.api.nvim_buf_add_highlight(bufnr, ns_id, "IncSearch", 2, 0, -1) -- Adjust index (0-based)

    -- Store window and buffer IDs
    self.win_id = win_id
    self.bufnr = bufnr

    return win_id, bufnr
end

---@param list? HarpoonList
---TODO: @param opts? HarpoonToggleOptions
function HarpoonUI:toggle_quick_menu(list, opts, split)
    opts = toggle_config(opts)
    if list == nil or self.win_id ~= nil then
        Logger:log("ui#toggle_quick_menu#closing", list and list.name)
        if self.settings.save_on_toggle then
            self:save()
        end
        print("toggling quickmenue...")
        self:close_menu()
        return
    end

    -- grab the current file before opening the quick menu
    local current_file = vim.api.nvim_buf_get_name(0)

    Logger:log("ui#toggle_quick_menu#opening", list and list.name)
    local win_id, bufnr = self:_create_window(opts)

    if split then
        win_id, bufnr = self:_create_side_split(opts)
    end

    self.win_id = win_id
    self.bufnr = bufnr
    self.active_list = list

    local contents = self.active_list:display()

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, contents)

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = win_id,
        bufnr = bufnr,
        current_file = current_file,
        contents = contents,
    })
end

function HarpoonUI:toggle_split(list, opts)
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
    local win_id, bufnr = self:_create_side_split(opts)

    self.split_win_id = win_id
    self.split_bufnr = bufnr
    self.split_active_list = list

    local contents = self.split_active_list:display()

    vim.api.nvim_buf_set_lines(self.split_bufnr, 0, -1, false, contents)

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = self.win_id,
        bufnr = self.bufnr,
        current_file = current_file,
        contents = contents,
    })
end

function HarpoonUI:refresh_content()

    local current_file = vim.api.nvim_buf_get_name(0)
    local contents = self.active_list:display()

    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, contents)

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = self.win_id,
        bufnr = self.bufnr,
        current_file = current_file,
        contents = contents,
    })
end
function HarpoonUI:refresh_content_split()

    local current_file = vim.api.nvim_buf_get_name(0)
    local contents = self.split_active_list:display()

    vim.api.nvim_buf_set_lines(self.split_bufnr, 0, -1, false, contents)

    Extensions.extensions:emit(Extensions.event_names.UI_CREATE, {
        win_id = self.split_win_id,
        bufnr = self.split_bufnr,
        current_file = current_file,
        contents = contents,
    })
end
function HarpoonUI:_get_processed_ui_contents()
    local list = Buffer.get_contents(self.bufnr)
    local length = #list
    return list, length
end

---@param options? any
function HarpoonUI:select_menu_item(options)
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

function HarpoonUI:save()
    local list, length = self:_get_processed_ui_contents()

    Logger:log("ui#save", list)
    self.active_list:resolve_displayed(list, length)
    if self.settings.sync_on_ui_close then
        require("harpoon"):sync()
    end
end

---@param settings HarpoonSettings
function HarpoonUI:configure(settings)
    self.settings = settings
end

return HarpoonUI
