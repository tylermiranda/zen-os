-- modules/filebrowser/patches/home/bento_board.lua
-- Full-screen Bento-Box Home Dashboard (inspired by Aleph + u/emdigi setup)
-- 4 looping pages: Home, Shelves, Insights, Apps. Also supports readonly Lock Screen mode.

local Blitbuffer = require("ffi/blitbuffer")
local Accent = require("common/ui/accent")
local ButtonDialog = require("ui/widget/buttondialog")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Event = require("ui/event")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local Widget = require("ui/widget/widget")
local CoverCommon = require("modules/filebrowser/patches/home/widgets/cover_common")
local LibraryDB = require("common/db_library")
local ReadingGoals = require("common/reading_goals")
local StatsDB = require("common/db_stats")
local getFullRefreshMode = require("common/ui/refresh")
local library_font = require("modules/filebrowser/patches/library_font")
local logger = require("logger")
local plugin_root = require("common/plugin_root")
local utils = require("common/utils")
local _ = require("gettext")

local Screen = Device.screen
local M = {}
local _readonly_mode = false

M.PAGE_COUNT = 4
local PAGE_NAMES = { _("Home"), _("Shelves"), _("Insights"), _("Apps") }

local function make_rgb(r, g, b)
    return Blitbuffer.ColorRGB32(r, g, b, 0xFF)
end

local function get_palette()
    local is_color = type(Screen.isColorScreen) == "function" and Screen:isColorScreen()
    return {
        is_color = is_color,
        canvas_bg = is_color and make_rgb(0xF1, 0xF0, 0xEA) or Blitbuffer.Color8(0xEC),
        card_bg = Blitbuffer.COLOR_WHITE,
        card_border = is_color and make_rgb(0xD2, 0xD0, 0xC6) or Blitbuffer.Color8(0xB4),
        hero_bg = is_color and make_rgb(0x3D, 0x42, 0x1E) or Blitbuffer.Color8(0x20),
        hero_border = is_color and make_rgb(0x2F, 0x33, 0x16) or Blitbuffer.Color8(0x20),
        hero_fg = Blitbuffer.COLOR_WHITE,
        hero_muted = is_color and make_rgb(0xD7, 0xDC, 0xC2) or Blitbuffer.Color8(0xD6),
        hero_track = is_color and make_rgb(0x63, 0x69, 0x43) or Blitbuffer.Color8(0x52),
        hero_fill = Blitbuffer.COLOR_WHITE,
        quote_bg = is_color and make_rgb(0xFA, 0xF0, 0xBE) or Blitbuffer.Color8(0xE8),
        quote_border = is_color and make_rgb(0xDF, 0xD0, 0x8C) or Blitbuffer.Color8(0xA6),
        chip_bg = is_color and make_rgb(0xED, 0xEC, 0xE5) or Blitbuffer.Color8(0xE6),
        chip_active_bg = Blitbuffer.COLOR_BLACK,
        fg = Blitbuffer.COLOR_BLACK,
        muted = Blitbuffer.COLOR_DARK_GRAY,
        track = is_color and make_rgb(0xE2, 0xE1, 0xDA) or Blitbuffer.Color8(0xD6),
        fill = Blitbuffer.COLOR_BLACK,
        heat_0 = is_color and make_rgb(0xE8, 0xE7, 0xE0) or Blitbuffer.Color8(0xE2),
        heat_1 = is_color and make_rgb(0xB7, 0xCE, 0xAE) or Blitbuffer.Color8(0xB4),
        heat_2 = is_color and make_rgb(0x76, 0xA1, 0x6A) or Blitbuffer.Color8(0x74),
        heat_3 = is_color and make_rgb(0x2F, 0x5D, 0x2A) or Blitbuffer.COLOR_BLACK,
    }
end

local function paint_rounded_fill(bb, x, y, w, h, color, r)
    if w <= 0 or h <= 0 then return end
    local rad = math.max(0, math.min(math.floor(tonumber(r) or 0), math.floor(math.min(w, h) / 2)))
    if bb.paintRoundedRectRGB32 and not Blitbuffer.isColor8(color) then
        bb:paintRoundedRectRGB32(x, y, w, h, color, rad)
    else
        bb:paintRoundedRect(x, y, w, h, color, rad)
    end
end

local TapBox = InputContainer:extend{}

function TapBox:init()
    self.dimen = self.dimen or Geom:new{ w = self.width or 1, h = self.height or 1 }
    self.ges_events = {}
    if self.tap_callback then
        self.ges_events.TapSelect = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        }
    end
    if self.hold_callback then
        self.ges_events.HoldSelect = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        }
    end
end

function TapBox:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if self[1] then
        self[1]:paintTo(bb, x, y)
    end
end

function TapBox:onTapSelect(_arg, ges)
    if self.dimen and ges and ges.pos and not self.dimen:contains(ges.pos) then
        return false
    end
    if self.tap_callback then
        self.tap_callback()
        return true
    end
    return false
end

function TapBox:onHoldSelect(_arg, ges)
    if self.dimen and ges and ges.pos and not self.dimen:contains(ges.pos) then
        return false
    end
    if self.hold_callback then
        self.hold_callback()
        return true
    end
    return false
end

local function wrap_tap(widget, w, h, tap_cb, hold_cb)
    if _readonly_mode or (not tap_cb and not hold_cb) then return widget end
    return TapBox:new{
        width = w,
        height = h,
        tap_callback = tap_cb,
        hold_callback = hold_cb,
        widget,
    }
end

local function make_card(w, h, inner, pal, opts)
    opts = opts or {}
    local pad_h = opts.pad_h ~= nil and opts.pad_h or Screen:scaleBySize(12)
    local pad_v = opts.pad_v ~= nil and opts.pad_v or Screen:scaleBySize(10)
    local bordersize = opts.bordersize ~= nil and opts.bordersize or math.max(1, Screen:scaleBySize(1.5))
    local radius = opts.radius ~= nil and opts.radius or Screen:scaleBySize(14)
    local bg = opts.bg or pal.card_bg
    local border_color = opts.border_color or pal.card_border
    local inner_w = math.max(1, w - bordersize * 2 - pad_h * 2)
    local inner_h = math.max(1, h - bordersize * 2 - pad_v * 2)

    local boxed = opts.center
        and CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, inner }
        or LeftContainer:new{ dimen = Geom:new{ w = inner_w, h = inner_h }, inner }

    local frame = FrameContainer:new{
        width = w,
        height = h,
        padding_left = pad_h,
        padding_right = pad_h,
        padding_top = pad_v,
        padding_bottom = pad_v,
        bordersize = bordersize,
        radius = radius,
        color = border_color,
        background = bg,
        boxed,
    }
    return wrap_tap(frame, w, h, opts.on_tap, opts.on_hold)
end

local function resolve_icon_path(name)
    if type(name) ~= "string" or name == "" or not plugin_root then return nil end
    return utils.resolveIcon(plugin_root .. "/icons/", name)
end

local function make_icon(name, px, fallback_glyph, color)
    local path = resolve_icon_path(name)
    if path then
        return IconWidget:new{
            file = path,
            width = px,
            height = px,
            alpha = true,
        }
    end
    return TextWidget:new{
        text = fallback_glyph or "?",
        face = Font:getFace("smallinfofont", math.max(10, math.floor(px * 0.72))),
        fgcolor = color or Blitbuffer.COLOR_BLACK,
        padding = 0,
    }
end

local function make_progress_bar(w, h, ratio, fg, bg)
    local r = tonumber(ratio) or 0
    if r > 1 then r = r / 100 end
    if r < 0 then r = 0 end
    if r > 1 then r = 1 end
    local rad = math.max(1, math.floor(h / 2))
    local bar = Widget:new{ dimen = Geom:new{ w = w, h = h } }
    bar.paintTo = function(_self, bb, x, y)
        paint_rounded_fill(bb, x, y, w, h, bg, rad)
        local fill_w = math.floor(w * r + 0.5)
        if fill_w > 0 then
            fill_w = math.min(w, math.max(h, fill_w))
            paint_rounded_fill(bb, x, y, fill_w, h, fg, rad)
        end
    end
    return bar
end

local function format_duration(secs)
    secs = math.floor(tonumber(secs) or 0)
    if secs <= 0 then return "0m" end
    local hours = math.floor(secs / 3600)
    local mins = math.floor((secs % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", math.max(1, mins))
end

local function pct_ratio(book)
    local p = tonumber(book and (book.percent_finished or book.percent)) or 0
    if p > 1 then p = p / 100 end
    if p < 0 then p = 0 end
    if p > 1 then p = 1 end
    return p
end

local function get_font_face(size_pt, bold)
    local px = math.max(10, Screen:scaleBySize(size_pt))
    return library_font.getFace(px) or Font:getFace(bold and "cfont" or "smallinfofont", px)
end

local function single_line_text(text, size_pt, bold, color, max_w)
    return TextWidget:new{
        text = tostring(text or ""),
        face = get_font_face(size_pt, bold),
        bold = bold == true,
        fgcolor = color or Blitbuffer.COLOR_BLACK,
        max_width = max_w,
        padding = 0,
    }
end

local function make_bento_cover(data, book, max_w, max_h, opts)
    if book and book.path and book.has_real_cover == true and not book.cover_bb
            and data and type(data.warmStripCover) == "function" then
        local tw, th = CoverCommon.target_dims(book, max_w, max_h, opts)
        pcall(data.warmStripCover, data, book, tw, th)
    end
    return CoverCommon.make_cover_widget(book, max_w, max_h, opts)
end

local function is_callable(value)
    if type(value) == "function" then return true end
    local mt = type(value) == "table" and getmetatable(value) or nil
    return type(mt) == "table" and type(mt.__call) == "function"
end

local function match_plugin_in_ui(ui, key)
    if type(ui) ~= "table" then return nil end
    if type(ui[key]) == "table" then return ui[key] end
    local lower_key = key:lower()
    local pat = "/" .. lower_key .. "%.koplugin/?$"
    for _i, child in ipairs(ui) do
        if type(child) == "table" then
            if child.name == key or child.id == key
                    or (type(child.plugin_path) == "string" and child.plugin_path:lower():match(pat))
                    or (type(child.path) == "string" and child.path:lower():match(pat)) then
                return child
            end
        end
    end
    for k, v in pairs(ui) do
        if type(k) == "string" and k:lower() == lower_key and type(v) == "table" then
            return v
        end
    end
    return nil
end

local function find_plugin(key)
    if type(key) ~= "string" or key == "" then return nil end
    local ok_rui, ReaderUI = pcall(function() return package.loaded["apps/reader/readerui"] end)
    if ok_rui and ReaderUI and ReaderUI.instance then
        local found = match_plugin_in_ui(ReaderUI.instance, key)
        if found then return found end
    end
    local ok_fm, FileManager = pcall(require, "apps/filemanager/filemanager")
    if ok_fm and FileManager and FileManager.instance then
        local found = match_plugin_in_ui(FileManager.instance, key)
        if found then return found end
    end
    local ok_pl, PluginLoader = pcall(require, "pluginloader")
    if ok_pl and PluginLoader then
        if type(PluginLoader.getPluginInstance) == "function" then
            local ok_inst, inst = pcall(PluginLoader.getPluginInstance, PluginLoader, key)
            if ok_inst and type(inst) == "table" then return inst end
        end
        if type(PluginLoader.loaded_plugins) == "table" then
            if type(PluginLoader.loaded_plugins[key]) == "table" then
                return PluginLoader.loaded_plugins[key]
            end
            local lower_key = key:lower()
            for k, v in pairs(PluginLoader.loaded_plugins) do
                if type(k) == "string" and k:lower() == lower_key and type(v) == "table" then
                    return v
                end
            end
        end
    end
    return nil
end

local function launch_plugin(key, preferred_methods, title, ...)
    local extra_args = { ... }
    local p = find_plugin(key)
    local fn
    if p and type(preferred_methods) == "table" then
        for _i, method in ipairs(preferred_methods) do
            if is_callable(p[method]) then
                fn = function()
                    return p[method](p, unpack(extra_args))
                end
                break
            end
        end
    end
    if not fn then
        local ok_ps, PluginScan = pcall(require, "modules/menu/app_launcher/plugin_scan")
        if ok_ps and PluginScan then
            fn = PluginScan.resolve(key, PluginScan.SENTINEL)
                or PluginScan.resolve(key, PluginScan.SUBMENU)
        end
    end
    if not fn then
        UIManager:show(InfoMessage:new{
            text = (title or key) .. " " .. _("is not installed or enabled."),
            timeout = 2,
        })
        return false
    end
    UIManager:nextTick(function()
        local ok, err = pcall(fn)
        if not ok then
            logger.warn("Bento plugin launch failed", key, err)
            UIManager:show(InfoMessage:new{
                text = (title or key) .. " " .. _("could not be opened."),
                timeout = 2,
            })
        end
    end)
    return true
end

local function open_zlibrary(mode)
    local ok_ps, PluginScan = pcall(require, "modules/menu/app_launcher/plugin_scan")
    if mode == "menu" then
        local sub_fn = ok_ps and PluginScan and (
            PluginScan.resolve("zlibrary", PluginScan.SUBMENU)
            or PluginScan.resolve("zlibrary", PluginScan.SENTINEL)
        )
        if sub_fn then
            UIManager:nextTick(function()
                local ok, err = pcall(sub_fn)
                if not ok then logger.warn("Bento Z-Library menu failed", err) end
            end)
            return true
        end
    end
    if mode == "mybooks" then
        local p = find_plugin("zlibrary")
        if p and is_callable(p.onZlibrarySearch) then
            return launch_plugin("zlibrary", { "onZlibrarySearch" }, "Z-Library", "mybooks")
        end
    end
    return launch_plugin("zlibrary", { "onZlibrarySearch", "showMultiSearchDialog" }, "Z-Library")
end

local function open_tab(ctx, tab_id)
    local fn = rawget(_G, "__ZEN_UI_NAVBAR_OPEN_TAB")
    if type(fn) == "function" and fn(tab_id) == true then
        return true
    end
    local fm = require("apps/filemanager/filemanager").instance
    if tab_id == "books" then
        if ctx.menu and ctx.menu.close_callback then
            ctx.menu.close_callback()
        elseif ctx.menu then
            UIManager:close(ctx.menu)
        end
        return true
    elseif tab_id == "search" and fm and fm.filesearcher then
        fm.filesearcher:onShowFileSearch()
        return true
    elseif tab_id == "history" and fm and fm.history then
        fm.history:onShowHist()
        return true
    elseif tab_id == "favorites" and fm and fm.collections then
        fm.collections:onShowColl()
        return true
    elseif tab_id == "collections" and fm and fm.collections then
        fm.collections:onShowCollList()
        return true
    end
    return false
end

local function open_games_dialog()
    local dialog
    local function launch_game(key, methods, title)
        if dialog then UIManager:close(dialog) end
        launch_plugin(key, methods, title)
    end
    dialog = ButtonDialog:new{
        title = _("Games"),
        buttons = {
            {
                {
                    text = _("Solitaire"),
                    callback = function()
                        launch_game("solitaire", { "startGame" }, _("Solitaire"))
                    end,
                },
                {
                    text = _("Sudoku"),
                    callback = function()
                        launch_game("sudoku", { "showGame" }, _("Sudoku"))
                    end,
                },
            },
            {
                {
                    text = _("Minesweeper"),
                    callback = function()
                        launch_game("boardgames", { "onShowMinesweeper" }, _("Minesweeper"))
                    end,
                },
                {
                    text = _("Murdoku"),
                    callback = function()
                        launch_game("murdoku", { "openCaseList", "onOpenMurdoku" }, _("Murdoku"))
                    end,
                },
            },
            {
                {
                    text = _("Board Games Hub"),
                    callback = function()
                        launch_game("boardgames", { "show_board" }, _("Board Games"))
                    end,
                },
            },
            {
                {
                    text = _("Close"),
                    callback = function() UIManager:close(dialog) end,
                },
            },
        },
    }
    UIManager:show(dialog)
end

local function build_status_cluster(ctx, pal, btn_h)
    local NetworkMgr = require("ui/network/manager")
    local wifi_on = NetworkMgr and type(NetworkMgr.isWifiOn) == "function" and NetworkMgr:isWifiOn() == true
    local power = Device:getPowerDevice()
    local cap = power and type(power.getCapacity) == "function" and power:getCapacity() or nil
    local charging = power and type(power.isCharging) == "function" and power:isCharging() == true
    local bat_text = cap and (tostring(cap) .. "%" .. (charging and "+" or "")) or ""
    local sb_cfg = type(ctx.zen_config) == "table" and ctx.zen_config.status_bar or {}
    local time_12h = sb_cfg.time_12h ~= false
    local clock_str = time_12h and (os.date("%I:%M %p"):gsub("^0", "")) or os.date("%H:%M")

    local status_gap = Screen:scaleBySize(8)
    local cluster = HorizontalGroup:new{ align = "center" }
    cluster[#cluster + 1] = make_icon(wifi_on and "quick_wifi" or "settings_wifi_off",
        Screen:scaleBySize(16), wifi_on and "W" or "-", pal.fg)
    if bat_text ~= "" then
        cluster[#cluster + 1] = HorizontalSpan:new{ width = status_gap }
        cluster[#cluster + 1] = single_line_text(bat_text, 11, false, pal.muted)
    end
    cluster[#cluster + 1] = HorizontalSpan:new{ width = status_gap }
    cluster[#cluster + 1] = single_line_text(clock_str, 12, true, pal.fg)

    return FrameContainer:new{
        height = btn_h,
        padding_left = Screen:scaleBySize(10),
        padding_right = Screen:scaleBySize(10),
        padding_top = 0,
        padding_bottom = 0,
        bordersize = math.max(1, Screen:scaleBySize(1)),
        radius = math.floor(btn_h / 2),
        color = pal.card_border,
        background = pal.card_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = cluster:getSize().w, h = btn_h - 2 },
            cluster,
        },
    }
end

local function build_header(ctx, pal, width, height)
    local hour = tonumber(os.date("%H")) or 12
    local base_greeting = hour < 12 and _("Good morning")
        or (hour < 18 and _("Good afternoon") or _("Good evening"))
    local raw_name = type(ctx.zen_config) == "table" and ctx.zen_config.bento_user_name or nil
    if raw_name == nil then raw_name = "Tyler" end
    local user_name = tostring(raw_name):gsub("^%s+", ""):gsub("%s+$", "")
    local greeting = user_name ~= "" and string.format("%s, %s", base_greeting, user_name) or base_greeting
    local date_str = os.date("%A, %d %B")

    local btn_h = math.min(Screen:scaleBySize(34), math.max(24, height - Screen:scaleBySize(8)))
    local btn_r = math.floor(btn_h / 2)
    local gap = Screen:scaleBySize(8)

    local status_pill = build_status_cluster(ctx, pal, btn_h)
    if not ctx.readonly and type(ctx.registerClockRefresh) == "function" then
        ctx.registerClockRefresh(function()
            if ctx.rebuildHome then ctx.rebuildHome(false, "ui") end
            return false
        end, status_pill, { "time", "battery", "wifi" })
    end

    local right_group = HorizontalGroup:new{ align = "center", status_pill }
    if ctx.readonly then
        local lock_txt = single_line_text("☾  " .. _("Sleeping"), 11, true, pal.hero_fg)
        local lock_w = lock_txt:getSize().w + Screen:scaleBySize(18)
        local lock_pill = FrameContainer:new{
            width = lock_w,
            height = btn_h,
            padding = 0,
            bordersize = 0,
            radius = btn_r,
            background = pal.hero_bg,
            CenterContainer:new{
                dimen = Geom:new{ w = lock_w, h = btn_h },
                lock_txt,
            },
        }
        right_group[#right_group + 1] = HorizontalSpan:new{ width = gap }
        right_group[#right_group + 1] = lock_pill
    else
        local search_btn = wrap_tap(FrameContainer:new{
            width = btn_h,
            height = btn_h,
            padding = 0,
            bordersize = math.max(1, Screen:scaleBySize(1)),
            radius = btn_r,
            color = pal.card_border,
            background = pal.card_bg,
            CenterContainer:new{
                dimen = Geom:new{ w = btn_h - 2, h = btn_h - 2 },
                make_icon("quick_search", math.floor(btn_h * 0.56), "?", pal.fg),
            },
        }, btn_h, btn_h, function() open_tab(ctx, "search") end)

        local menu_btn = wrap_tap(FrameContainer:new{
            width = btn_h,
            height = btn_h,
            padding = 0,
            bordersize = math.max(1, Screen:scaleBySize(1)),
            radius = btn_r,
            color = pal.card_border,
            background = pal.card_bg,
            CenterContainer:new{
                dimen = Geom:new{ w = btn_h - 2, h = btn_h - 2 },
                make_icon("app_menu", math.floor(btn_h * 0.56), "=", pal.fg),
            },
        }, btn_h, btn_h, function()
            local fm = require("apps/filemanager/filemanager").instance
            local fm_menu = fm and fm.menu
            if fm_menu and type(fm_menu.onShowMenu) == "function" then
                fm_menu:onShowMenu()
            end
        end)

        right_group[#right_group + 1] = HorizontalSpan:new{ width = gap }
        right_group[#right_group + 1] = search_btn
        right_group[#right_group + 1] = HorizontalSpan:new{ width = gap }
        right_group[#right_group + 1] = menu_btn
    end

    local right_w = right_group:getSize().w
    local left_w = math.max(1, width - right_w - gap)

    local left_col = VerticalGroup:new{
        align = "left",
        single_line_text(greeting, 21, true, pal.fg, left_w),
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        single_line_text(date_str, 11, false, pal.muted, left_w),
    }
    local left_box = LeftContainer:new{ dimen = Geom:new{ w = left_w, h = height }, left_col }
    left_box = wrap_tap(left_box, left_w, height, function()
        local plugin = ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN")
        local cfg = type(ctx.zen_config) == "table" and ctx.zen_config
            or (plugin and plugin.config) or {}
        local dlg
        dlg = InputDialog:new{
            title = _("Greeting name"),
            input = user_name,
            input_hint = _("Tyler"),
            buttons = {
                {
                    {
                        text = _("Cancel"),
                        id = "close",
                        callback = function() UIManager:close(dlg) end,
                    },
                    {
                        text = _("Clear"),
                        callback = function()
                            cfg.bento_user_name = ""
                            if plugin and type(plugin.saveConfig) == "function" then
                                plugin:saveConfig()
                            end
                            UIManager:close(dlg)
                            if ctx.rebuildHome then ctx.rebuildHome(false, "ui") end
                        end,
                    },
                    {
                        text = _("Save"),
                        is_enter_default = true,
                        callback = function()
                            local val = tostring(dlg:getInputText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
                            cfg.bento_user_name = val
                            if plugin and type(plugin.saveConfig) == "function" then
                                plugin:saveConfig()
                            end
                            UIManager:close(dlg)
                            if ctx.rebuildHome then ctx.rebuildHome(false, "ui") end
                        end,
                    },
                },
            },
        }
        UIManager:show(dlg)
        dlg:onShowKeyboard()
    end)

    return HorizontalGroup:new{
        align = "center",
        left_box,
        HorizontalSpan:new{ width = gap },
        RightContainer:new{ dimen = Geom:new{ w = right_w, h = height }, right_group },
    }
end

local function build_hero_card(ctx, pal, w, h, hero, go_insights)
    local pad_h = Screen:scaleBySize(14)
    local pad_v = Screen:scaleBySize(12)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    if not hero then
        local empty = VerticalGroup:new{
            align = "center",
            single_line_text(_("Ready to read"), 16, true, pal.hero_fg, inner_w),
            VerticalSpan:new{ width = Screen:scaleBySize(6) },
            single_line_text(_("Tap to browse Library"), 12, false, pal.hero_muted, inner_w),
        }
        return make_card(w, h, empty, pal, {
            bg = pal.hero_bg,
            border_color = pal.hero_border,
            pad_h = pad_h,
            pad_v = pad_v,
            center = true,
            on_tap = function() open_tab(ctx, "books") end,
        })
    end

    local col_gap = Screen:scaleBySize(12)
    local cover_max_w = math.floor(inner_w * 0.38)
    local cover_max_h = inner_h
    local cover_widget, actual_cw, _ch = make_bento_cover(
        ctx.data, hero, cover_max_w, cover_max_h,
        { border = 1, background = Blitbuffer.Color8(0x38) }
    )
    local text_w = math.max(1, inner_w - actual_cw - col_gap)
    local ratio = pct_ratio(hero)
    local pct_str = string.format("%d%%", math.floor(ratio * 100 + 0.5))
    local pages_num = tonumber(hero.stable_pages) or tonumber(hero.pages)
    local meta_str = pages_num and (pct_str .. " · " .. tostring(pages_num) .. " " .. _("pages")) or pct_str

    local pill_h = math.max(Screen:scaleBySize(28), math.floor(inner_h * 0.21))
    local pill_w = math.min(text_w, math.max(Screen:scaleBySize(108), math.floor(text_w * 0.68)))
    local resume_pill = FrameContainer:new{
        width = pill_w,
        height = pill_h,
        padding = 0,
        bordersize = 0,
        radius = math.floor(pill_h / 2),
        background = pal.hero_fill,
        CenterContainer:new{
            dimen = Geom:new{ w = pill_w, h = pill_h },
            single_line_text("▶  " .. _("Resume"), 11, true, Blitbuffer.COLOR_BLACK, pill_w - 12),
        },
    }

    local bar_h = math.max(4, Screen:scaleBySize(5))
    local top_block = VerticalGroup:new{
        align = "left",
        single_line_text(_("CONTINUE READING"), 9, true, pal.hero_muted, text_w),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        TextBoxWidget:new{
            text = tostring(hero.title or ""),
            face = get_font_face(15, true),
            bold = true,
            width = text_w,
            height = Screen:scaleBySize(44),
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            fgcolor = pal.hero_fg,
        },
        VerticalSpan:new{ width = Screen:scaleBySize(3) },
        single_line_text(hero.authors or "", 11, false, pal.hero_muted, text_w),
    }

    local bottom_block = VerticalGroup:new{
        align = "left",
        make_progress_bar(text_w, bar_h, ratio, pal.hero_fill, pal.hero_track),
        VerticalSpan:new{ width = Screen:scaleBySize(5) },
        single_line_text(meta_str, 10, false, pal.hero_muted, text_w),
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        resume_pill,
    }

    local right_col = VerticalGroup:new{
        align = "left",
        top_block,
        VerticalSpan:new{ width = math.max(2, inner_h - top_block:getSize().h - bottom_block:getSize().h) },
        bottom_block,
    }

    local body = HorizontalGroup:new{
        align = "center",
        CenterContainer:new{ dimen = Geom:new{ w = actual_cw, h = inner_h }, cover_widget },
        HorizontalSpan:new{ width = col_gap },
        LeftContainer:new{ dimen = Geom:new{ w = text_w, h = inner_h }, right_col },
    }

    return make_card(w, h, body, pal, {
        bg = pal.hero_bg,
        border_color = pal.hero_border,
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = function() if ctx.openBook then ctx.openBook(hero.path) end end,
        on_hold = function() if ctx.showBookMenu then ctx.showBookMenu(hero.path, "recently_read", "featured") end end,
    })
end

local function weekday_letter(date_str)
    local y, m, d = tostring(date_str or ""):match("^(%d+)%-(%d+)%-(%d+)$")
    if not y then return "" end
    local wday = tonumber(os.date("%w", os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
    local map = { [0] = "S", "M", "T", "W", "T", "F", "S" }
    return map[wday or 0] or ""
end

local function build_streak_card(pal, w, h, stats, series7, on_tap)
    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(8)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local streak_num = tonumber(stats and stats.streak) or 0
    local header = HorizontalGroup:new{
        align = "center",
        single_line_text(_("Streak"), 11, false, pal.muted, inner_w - Screen:scaleBySize(18)),
        HorizontalSpan:new{ width = math.max(2, inner_w - Screen:scaleBySize(16) - single_line_text(_("Streak"), 11, false, pal.muted):getSize().w) },
        make_icon("flame", Screen:scaleBySize(15), "*", pal.fg),
    }

    local big_val = single_line_text(
        tostring(streak_num) .. (streak_num == 1 and _("d") or _(" days")),
        17, true, pal.fg, inner_w
    )

    local dots_row = HorizontalGroup:new{ align = "center" }
    local dot_d = math.max(8, math.min(Screen:scaleBySize(13), math.floor(inner_w / 10)))
    local slot_w = math.floor(inner_w / 7)
    for i = 1, 7 do
        local day = series7[i] or {}
        local active = (tonumber(day.duration) or 0) > 0 or (tonumber(day.pages) or 0) > 0
        local dot = FrameContainer:new{
            width = dot_d,
            height = dot_d,
            padding = 0,
            bordersize = active and 0 or 1,
            radius = math.floor(dot_d / 2),
            color = pal.card_border,
            background = active and pal.fill or pal.heat_0,
            Widget:new{ dimen = Geom:new{ w = dot_d - (active and 0 or 2), h = dot_d - (active and 0 or 2) } },
        }
        dots_row[#dots_row + 1] = CenterContainer:new{
            dimen = Geom:new{ w = slot_w, h = dot_d + Screen:scaleBySize(14) },
            VerticalGroup:new{
                align = "center",
                dot,
                VerticalSpan:new{ width = Screen:scaleBySize(2) },
                single_line_text(weekday_letter(day.date), 8, false, active and pal.fg or pal.muted, slot_w),
            },
        }
    end

    local body = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        big_val,
        VerticalSpan:new{ width = math.max(2, inner_h - header:getSize().h - big_val:getSize().h - dots_row:getSize().h - Screen:scaleBySize(4)) },
        CenterContainer:new{ dimen = Geom:new{ w = inner_w, h = dots_row:getSize().h }, dots_row },
    }

    return make_card(w, h, body, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = on_tap,
    })
end

local function build_toggles_card(ctx, pal, w, h)
    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(8)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)
    local cell_gap = Screen:scaleBySize(8)
    local btn_d = math.max(20, math.min(
        math.floor((inner_w - cell_gap) / 2),
        math.floor((inner_h - cell_gap) / 2)
    ))

    local NetworkMgr = require("ui/network/manager")
    local wifi_on = NetworkMgr and type(NetworkMgr.isWifiOn) == "function" and NetworkMgr:isWifiOn() == true
    local power = Device:getPowerDevice()
    local fl_on = power and type(power.isFrontlightOn) == "function" and power:isFrontlightOn() == true
    local night_on = G_reader_settings:isTrue("night_mode")

    local function toggle_btn(icon_name, fallback_txt, is_on, cb)
        local icon_w = make_icon(icon_name, math.floor(btn_d * 0.56), fallback_txt, pal.fg)
        local frame = FrameContainer:new{
            width = btn_d,
            height = btn_d,
            padding = 0,
            bordersize = math.max(1, Screen:scaleBySize(1.2)),
            radius = math.floor(btn_d / 2),
            color = is_on and Blitbuffer.COLOR_BLACK or pal.card_border,
            background = is_on and Blitbuffer.COLOR_WHITE or pal.chip_bg,
            CenterContainer:new{
                dimen = Geom:new{ w = btn_d - 2, h = btn_d - 2 },
                icon_w,
            },
        }
        if is_on then
            Accent.styleButton(frame, icon_w, true)
        end
        return wrap_tap(frame, btn_d, btn_d, cb)
    end

    local b_wifi = toggle_btn("quick_wifi", "W", wifi_on, function()
        if NetworkMgr and type(NetworkMgr.toggleWifi) == "function" then
            NetworkMgr:toggleWifi()
        elseif NetworkMgr and NetworkMgr.turnOnWifi and NetworkMgr.turnOffWifi then
            if wifi_on then NetworkMgr:turnOffWifi() else NetworkMgr:turnOnWifi() end
        end
        UIManager:scheduleIn(1.2, function()
            if ctx.rebuildHome then ctx.rebuildHome(false, "ui") end
        end)
    end)

    local b_light = toggle_btn("brightness", "L", fl_on, function()
        UIManager:sendEvent(Event:new("ShowFlDialog"))
    end)

    local b_night = toggle_btn("quick_nightmode", "N", night_on, function()
        UIManager:broadcastEvent(Event:new("ToggleNightMode"))
        UIManager:nextTick(function()
            if ctx.rebuildHome then ctx.rebuildHome(false, getFullRefreshMode()) end
        end)
    end)

    local b_settings = toggle_btn("zen_ui", "S", false, function()
        local sp = require("modules/settings/zen_settings_page")
        if sp and type(sp.show) == "function" then
            sp.show(ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN"))
        end
    end)

    local grid = CenterContainer:new{
        dimen = Geom:new{ w = inner_w, h = inner_h },
        VerticalGroup:new{
            align = "center",
            HorizontalGroup:new{ align = "center", b_wifi, HorizontalSpan:new{ width = cell_gap }, b_light },
            VerticalSpan:new{ width = cell_gap },
            HorizontalGroup:new{ align = "center", b_night, HorizontalSpan:new{ width = cell_gap }, b_settings },
        },
    }

    return make_card(w, h, grid, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        center = true,
    })
end

local function build_week_card(pal, w, h, stats, series7, on_tap)
    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(8)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local lbl = single_line_text(_("This week"), 11, false, pal.muted, inner_w)
    local val = single_line_text(format_duration(stats and stats.week_duration or 0), 17, true, pal.fg, inner_w)
    local chart_h = math.max(Screen:scaleBySize(18), inner_h - lbl:getSize().h - val:getSize().h - Screen:scaleBySize(8))

    local max_dur = 1
    for i = 1, 7 do
        local d = tonumber(series7[i] and series7[i].duration) or 0
        if d > max_dur then max_dur = d end
    end

    local bars_w = inner_w
    local bar_gap = math.max(3, Screen:scaleBySize(4))
    local bar_w = math.max(4, math.floor((bars_w - bar_gap * 6) / 7))
    local chart = Widget:new{ dimen = Geom:new{ w = inner_w, h = chart_h } }
    chart.paintTo = function(_self, bb, x, y)
        local start_x = x + math.floor((inner_w - (bar_w * 7 + bar_gap * 6)) / 2)
        for i = 1, 7 do
            local dur = tonumber(series7[i] and series7[i].duration) or 0
            local frac = max_dur > 0 and (dur / max_dur) or 0
            local bh = dur > 0 and math.max(Screen:scaleBySize(5), math.floor(chart_h * frac)) or Screen:scaleBySize(3)
            local bx = start_x + (i - 1) * (bar_w + bar_gap)
            local by = y + chart_h - bh
            local col = dur > 0 and (i == 7 and pal.fg or Blitbuffer.COLOR_GRAY_5) or pal.track
            paint_rounded_fill(bb, bx, by, bar_w, bh, col, 2)
        end
    end

    local body = VerticalGroup:new{
        align = "left",
        lbl,
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        val,
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        chart,
    }

    return make_card(w, h, body, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = on_tap,
    })
end

local function build_goal_card(ctx, pal, w, h, stats, on_tap)
    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(8)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local goals = ReadingGoals.normalize(type(ctx.config) == "table" and ctx.config.goals or nil)
    local metric = type(goals.metrics) == "table" and goals.metrics.daily or "pages"
    local cur, target, unit
    if metric == "time" then
        cur = math.floor((tonumber(stats and stats.today_duration) or 0) / 60)
        target = tonumber(goals.daily_time_target_min) or 30
        unit = "m"
    else
        cur = tonumber(stats and stats.today_pages) or 0
        target = tonumber(goals.daily_pages_target) or 30
        unit = "p"
    end
    local ratio = target > 0 and math.min(1, cur / target) or 0
    local status_str = cur >= target and _("Goal reached!") or (tostring(target - cur) .. unit .. " " .. _("left"))

    local lbl = single_line_text(_("Daily goal"), 11, false, pal.muted, inner_w)
    local val = single_line_text(tostring(cur) .. " / " .. tostring(target) .. unit, 16, true, pal.fg, inner_w)
    local sub = single_line_text(status_str, 10, false, pal.muted, inner_w)
    local bar_h = math.max(5, Screen:scaleBySize(6))
    local bar = make_progress_bar(inner_w, bar_h, ratio, pal.fill, pal.track)

    local body = VerticalGroup:new{
        align = "left",
        lbl,
        VerticalSpan:new{ width = Screen:scaleBySize(3) },
        val,
        VerticalSpan:new{ width = math.max(4, inner_h - lbl:getSize().h - val:getSize().h - bar_h - sub:getSize().h - Screen:scaleBySize(10)) },
        bar,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        sub,
    }

    return make_card(w, h, body, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = on_tap,
    })
end

local function build_also_reading_card(ctx, pal, w, h, books)
    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(10)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local see_all_w = Screen:scaleBySize(56)
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - see_all_w, h = Screen:scaleBySize(22) },
            single_line_text(_("Also reading"), 13, true, pal.fg, inner_w - see_all_w),
        },
        wrap_tap(RightContainer:new{
            dimen = Geom:new{ w = see_all_w, h = Screen:scaleBySize(22) },
            single_line_text(_("All ›"), 11, false, pal.muted, see_all_w),
        }, see_all_w, Screen:scaleBySize(22), function() open_tab(ctx, "history") end),
    }

    local list_h = math.max(1, inner_h - header:getSize().h - Screen:scaleBySize(8))
    local count = math.min(3, #books)
    local col = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
    }

    if count == 0 then
        col[#col + 1] = CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = list_h },
            single_line_text(_("No other active books"), 11, false, pal.muted, inner_w),
        }
    else
        local row_gap = Screen:scaleBySize(6)
        local row_h = math.floor((list_h - row_gap * 2) / 3)
        local cov_w = math.floor(row_h * 2 / 3)
        local text_w = math.max(1, inner_w - cov_w - Screen:scaleBySize(10))
        local pct_w = Screen:scaleBySize(38)
        for i = 1, count do
            local b = books[i]
            local ratio = pct_ratio(b)
            local pct_str = string.format("%d%%", math.floor(ratio * 100 + 0.5))
            local cov = make_bento_cover(ctx.data, b, cov_w, row_h, { border = 1 })
            local bar_w = math.max(20, text_w - pct_w - Screen:scaleBySize(8))
            local row_info = VerticalGroup:new{
                align = "left",
                single_line_text(b.title or "", 11, true, pal.fg, text_w),
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                HorizontalGroup:new{
                    align = "center",
                    make_progress_bar(bar_w, math.max(4, Screen:scaleBySize(4)), ratio, pal.fill, pal.track),
                    HorizontalSpan:new{ width = Screen:scaleBySize(8) },
                    single_line_text(pct_str, 10, false, pal.muted, pct_w),
                },
            }
            local row_widget = HorizontalGroup:new{
                align = "center",
                CenterContainer:new{ dimen = Geom:new{ w = cov_w, h = row_h }, cov },
                HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                LeftContainer:new{ dimen = Geom:new{ w = text_w, h = row_h }, row_info },
            }
            col[#col + 1] = wrap_tap(row_widget, inner_w, row_h,
                function() if ctx.openBook then ctx.openBook(b.path) end end,
                function() if ctx.showBookMenu then ctx.showBookMenu(b.path, "recently_read", "strip") end end
            )
            if i < count then
                col[#col + 1] = VerticalSpan:new{ width = row_gap }
            end
        end
    end

    return make_card(w, h, col, pal, { pad_h = pad_h, pad_v = pad_v })
end

local function build_quote_card(ctx, pal, w, h)
    local pad_h = Screen:scaleBySize(14)
    local pad_v = Screen:scaleBySize(12)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local quote = ctx.data and type(ctx.data.getCurrentQuote) == "function"
        and ctx.data:getCurrentQuote() or nil
    local text = quote and quote.text or _("Open a book and highlight passages you love to collect them here.")
    local attr = quote and ((quote.attribution ~= "" and quote.attribution) or quote.title) or _("ZenOS Reader")

    local hdr = single_line_text("❞  " .. _("Highlight of the day"), 11, true, pal.muted, inner_w)
    local attr_w = single_line_text(attr, 10, true, pal.fg, inner_w)
    local body_h = math.max(Screen:scaleBySize(36), inner_h - hdr:getSize().h - attr_w:getSize().h - Screen:scaleBySize(16))
    local quote_box = TextBoxWidget:new{
        text = text,
        face = get_font_face(13, false),
        width = inner_w,
        height = body_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        fgcolor = pal.fg,
    }

    local col = VerticalGroup:new{
        align = "left",
        hdr,
        VerticalSpan:new{ width = Screen:scaleBySize(8) },
        quote_box,
        VerticalSpan:new{ width = math.max(4, inner_h - hdr:getSize().h - quote_box:getSize().h - attr_w:getSize().h - Screen:scaleBySize(8)) },
        attr_w,
    }

    return make_card(w, h, col, pal, {
        bg = pal.quote_bg,
        border_color = pal.quote_border,
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = function()
            if ctx.data and type(ctx.data.nextQuote) == "function" then
                ctx.data:nextQuote(function()
                    if ctx.rebuildHome then ctx.rebuildHome(false, "ui") end
                end)
            end
        end,
        on_hold = function()
            if quote and quote.is_annotation and ctx.data and type(ctx.data.openQuote) == "function" then
                ctx.data:openQuote(quote)
            end
        end,
    })
end

local function build_shelf_card(ctx, pal, w, h, title, books, cols, tab_id, source_key)
    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(10)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local see_w = Screen:scaleBySize(64)
    local hdr_h = Screen:scaleBySize(22)
    local header = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w - see_w, h = hdr_h },
            single_line_text(title, 13, true, pal.fg, inner_w - see_w),
        },
        wrap_tap(RightContainer:new{
            dimen = Geom:new{ w = see_w, h = hdr_h },
            single_line_text(_("See all ›"), 10, false, pal.muted, see_w),
        }, see_w, hdr_h, function() if tab_id then open_tab(ctx, tab_id) end end),
    }

    local shelf_top_gap = Screen:scaleBySize(8)
    local title_h = Screen:scaleBySize(20)
    local slot_gap = Screen:scaleBySize(10)
    local slot_w = math.floor((inner_w - slot_gap * (cols - 1)) / cols)
    local cov_max_h = math.max(Screen:scaleBySize(56), inner_h - hdr_h - shelf_top_gap - title_h - Screen:scaleBySize(4))

    local row = HorizontalGroup:new{ align = "top" }
    for i = 1, cols do
        local b = books[i]
        local slot_widget
        if b then
            local cov = make_bento_cover(ctx.data, b, slot_w, cov_max_h, { border = 1 })
            slot_widget = VerticalGroup:new{
                align = "center",
                CenterContainer:new{ dimen = Geom:new{ w = slot_w, h = cov_max_h }, cov },
                VerticalSpan:new{ width = Screen:scaleBySize(4) },
                CenterContainer:new{
                    dimen = Geom:new{ w = slot_w, h = title_h },
                    single_line_text(b.title or "", 10, false, pal.fg, slot_w),
                },
            }
            slot_widget = wrap_tap(slot_widget, slot_w, cov_max_h + title_h + Screen:scaleBySize(4),
                function() if ctx.openBook then ctx.openBook(b.path) end end,
                function() if ctx.showBookMenu then ctx.showBookMenu(b.path, source_key, "strip") end end
            )
        else
            local placeholder = CoverCommon.make_empty_placeholder_cover(slot_w, cov_max_h, { border = 1 })
            slot_widget = CenterContainer:new{
                dimen = Geom:new{ w = slot_w, h = cov_max_h + title_h + Screen:scaleBySize(4) },
                placeholder,
            }
        end
        row[#row + 1] = slot_widget
        if i < cols then
            row[#row + 1] = HorizontalSpan:new{ width = slot_gap }
        end
    end

    local col = VerticalGroup:new{
        align = "left",
        header,
        VerticalSpan:new{ width = shelf_top_gap },
        row,
    }
    return make_card(w, h, col, pal, { pad_h = pad_h, pad_v = pad_v })
end

local function build_wide_library_tile(ctx, pal, w, h, total_books, preview_books)
    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(10)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local cov_h = math.max(Screen:scaleBySize(36), inner_h)
    local cov_w = math.floor(cov_h * 2 / 3)
    local mini_gap = Screen:scaleBySize(6)
    local thumbs = HorizontalGroup:new{ align = "center" }
    local shown = math.min(2, #preview_books)
    for i = 1, shown do
        thumbs[#thumbs + 1] = make_bento_cover(ctx.data, preview_books[i], cov_w, cov_h, { border = 1 })
        if i < shown then
            thumbs[#thumbs + 1] = HorizontalSpan:new{ width = mini_gap }
        end
    end
    local thumbs_w = shown > 0 and thumbs:getSize().w or 0
    local left_w = math.max(1, inner_w - thumbs_w - (thumbs_w > 0 and Screen:scaleBySize(10) or 0))
    local count_text = total_books > 0 and (tostring(total_books) .. " " .. _("books")) or _("Browse all")

    local icon_d = Screen:scaleBySize(30)
    local left_col = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "center",
            make_icon("bookshelf", icon_d, "L", pal.fg),
            HorizontalSpan:new{ width = Screen:scaleBySize(8) },
            VerticalGroup:new{
                align = "left",
                single_line_text(_("Library"), 14, true, pal.fg, left_w - icon_d - 8),
                single_line_text(count_text, 10, false, pal.muted, left_w - icon_d - 8),
            },
        },
    }

    local row = HorizontalGroup:new{
        align = "center",
        LeftContainer:new{ dimen = Geom:new{ w = left_w, h = inner_h }, left_col },
    }
    if thumbs_w > 0 then
        row[#row + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(10) }
        row[#row + 1] = thumbs
    end

    return make_card(w, h, row, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = function() open_tab(ctx, "books") end,
    })
end

local function build_small_tile(pal, w, h, icon_name, fallback_glyph, title, subtitle, on_tap, on_hold)
    local pad_h = Screen:scaleBySize(10)
    local pad_v = Screen:scaleBySize(8)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local icon_sz = math.min(Screen:scaleBySize(26), math.max(18, math.floor(h * 0.28)))
    local title_pt = inner_w < Screen:scaleBySize(130) and 11 or 13

    local col = VerticalGroup:new{
        align = "left",
        make_icon(icon_name, icon_sz, fallback_glyph, pal.fg),
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        single_line_text(title, title_pt, true, pal.fg, inner_w),
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        single_line_text(subtitle, 9, false, pal.muted, inner_w),
    }
    return make_card(w, h, col, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = on_tap,
        on_hold = on_hold,
    })
end

local function build_get_next_book_card(pal, w, h, discover)
    local pad_h = Screen:scaleBySize(12)
    local pad_v = Screen:scaleBySize(10)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local badge_txt = single_line_text("Z-LIBRARY", 8, true, pal.muted)
    local badge_w = badge_txt:getSize().w + Screen:scaleBySize(12)
    local badge_h = math.max(Screen:scaleBySize(18), badge_txt:getSize().h + Screen:scaleBySize(6))
    local badge = FrameContainer:new{
        width = badge_w,
        height = badge_h,
        padding = 0,
        bordersize = 1,
        radius = math.floor(badge_h / 2),
        color = pal.card_border,
        background = pal.chip_bg,
        CenterContainer:new{ dimen = Geom:new{ w = badge_w - 2, h = badge_h - 2 }, badge_txt },
    }

    local icon_px = Screen:scaleBySize(20)
    local title_txt = single_line_text(_("Get next book"), 14, true, pal.fg,
        math.max(1, inner_w - badge_w - icon_px - Screen:scaleBySize(14)))
    local left_hdr = HorizontalGroup:new{
        align = "center",
        make_icon("quick_zlib", icon_px, "Z", pal.fg),
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        title_txt,
    }
    local hdr = HorizontalGroup:new{
        align = "center",
        left_hdr,
        HorizontalSpan:new{ width = math.max(4, inner_w - left_hdr:getSize().w - badge_w) },
        badge,
    }

    local btn_h = math.max(Screen:scaleBySize(26), math.min(Screen:scaleBySize(32), math.floor(inner_h * 0.25)))
    local btn_gap = Screen:scaleBySize(8)
    local primary_w = math.floor((inner_w - btn_gap) * 0.62)
    local secondary_w = math.max(1, inner_w - btn_gap - primary_w)

    local primary_btn = wrap_tap(FrameContainer:new{
        width = primary_w,
        height = btn_h,
        padding = 0,
        bordersize = 0,
        radius = math.floor(btn_h / 2),
        background = pal.hero_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = primary_w, h = btn_h },
            single_line_text("⌕  " .. _("Search Z-Lib ›"), 10, true, pal.hero_fg, primary_w - 10),
        },
    }, primary_w, btn_h, function() open_zlibrary("search") end)

    local secondary_btn = wrap_tap(FrameContainer:new{
        width = secondary_w,
        height = btn_h,
        padding = 0,
        bordersize = 1,
        radius = math.floor(btn_h / 2),
        color = pal.card_border,
        background = pal.chip_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = secondary_w - 2, h = btn_h - 2 },
            single_line_text(_("My Books"), 10, true, pal.fg, secondary_w - 10),
        },
    }, secondary_w, btn_h, function() open_zlibrary("mybooks") end)

    local actions_row = HorizontalGroup:new{
        align = "center",
        primary_btn,
        HorizontalSpan:new{ width = btn_gap },
        secondary_btn,
    }

    local next_tbr = discover and discover[1]
    local tbr_w = (next_tbr and type(next_tbr.title) == "string" and next_tbr.title ~= "")
        and single_line_text(_("Next in TBR: ") .. next_tbr.title, 10, false, pal.muted, inner_w)
        or nil

    local fixed_gaps = Screen:scaleBySize(6) + (tbr_w and Screen:scaleBySize(4) or 0) + Screen:scaleBySize(6)
    local sub_h = math.max(Screen:scaleBySize(22),
        inner_h - hdr:getSize().h - (tbr_w and tbr_w:getSize().h or 0) - btn_h - fixed_gaps)
    local desc = TextBoxWidget:new{
        text = _("Search millions of books and download straight to your Kobo."),
        face = get_font_face(11, false),
        width = inner_w,
        height = sub_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        fgcolor = pal.muted,
    }

    local used_h = hdr:getSize().h + desc:getSize().h + (tbr_w and tbr_w:getSize().h or 0) + btn_h + fixed_gaps
    local extra_gap = math.max(Screen:scaleBySize(2), inner_h - used_h)

    local col = VerticalGroup:new{
        align = "left",
        hdr,
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        desc,
    }
    if tbr_w then
        col[#col + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
        col[#col + 1] = tbr_w
    end
    col[#col + 1] = VerticalSpan:new{ width = extra_gap }
    col[#col + 1] = actions_row

    return make_card(w, h, col, pal, {
        pad_h = pad_h,
        pad_v = pad_v,
        border_color = pal.fg,
        on_tap = function() open_zlibrary("search") end,
        on_hold = function() open_zlibrary("menu") end,
    })
end

local function build_featured_app_card(pal, w, h, icon_name, fallback_glyph, tag_label, title, subtitle, action_text, on_tap, on_hold, dark)
    local pad_h = Screen:scaleBySize(14)
    local pad_v = Screen:scaleBySize(12)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local bg = dark and pal.hero_bg or pal.card_bg
    local border = dark and pal.hero_border or pal.card_border
    local fg = dark and pal.hero_fg or pal.fg
    local muted = dark and pal.hero_muted or pal.muted
    local pill_bg = dark and pal.hero_fill or pal.hero_bg
    local pill_fg = dark and Blitbuffer.COLOR_BLACK or pal.hero_fg

    local icon_px = Screen:scaleBySize(26)
    local top_row = HorizontalGroup:new{
        align = "center",
        make_icon(icon_name, icon_px, fallback_glyph, fg),
        HorizontalSpan:new{ width = Screen:scaleBySize(8) },
        single_line_text(tag_label, 10, true, muted, math.max(1, inner_w - icon_px - 8)),
    }

    local title_w = single_line_text(title, 16, true, fg, inner_w)
    local sub_h = math.max(Screen:scaleBySize(20), math.floor(inner_h * 0.28))
    local sub_w = TextBoxWidget:new{
        text = subtitle,
        face = get_font_face(11, false),
        width = inner_w,
        height = sub_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        fgcolor = muted,
    }

    local pill_h = math.max(Screen:scaleBySize(26), math.min(Screen:scaleBySize(32), math.floor(inner_h * 0.24)))
    local pill_w = math.min(inner_w, math.max(Screen:scaleBySize(118), math.floor(inner_w * 0.56)))
    local action_pill = FrameContainer:new{
        width = pill_w,
        height = pill_h,
        padding = 0,
        bordersize = 0,
        radius = math.floor(pill_h / 2),
        background = pill_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = pill_w, h = pill_h },
            single_line_text(action_text, 10, true, pill_fg, pill_w - 12),
        },
    }

    local top_block = VerticalGroup:new{
        align = "left",
        top_row,
        VerticalSpan:new{ width = Screen:scaleBySize(6) },
        title_w,
        VerticalSpan:new{ width = Screen:scaleBySize(3) },
        sub_w,
    }
    local spacer = math.max(Screen:scaleBySize(4), inner_h - top_block:getSize().h - pill_h)
    local col = VerticalGroup:new{
        align = "left",
        top_block,
        VerticalSpan:new{ width = spacer },
        action_pill,
    }
    return make_card(w, h, col, pal, {
        bg = bg,
        border_color = border,
        pad_h = pad_h,
        pad_v = pad_v,
        on_tap = on_tap,
        on_hold = on_hold,
    })
end

local function unique_skipping(books, skip_set, limit)
    local out = {}
    for _i, b in ipairs(books or {}) do
        if b and b.path and not skip_set[b.path] then
            skip_set[b.path] = true
            out[#out + 1] = b
            if #out >= limit then break end
        end
    end
    return out
end

local function build_page_home(ctx, pal, content_w, grid_h, gap, go_page)
    local left_w = math.floor((content_w - gap) / 2)
    local right_w = content_w - gap - left_w
    local q3_w = math.floor((right_w - gap) / 2)
    local q4_w = right_w - gap - q3_w

    local rows_h = grid_h - gap * 3
    local mini_h = math.floor((math.floor(rows_h * 0.30) - gap) / 2)
    local r1_h = mini_h * 2 + gap
    local r2_h = math.floor(rows_h * 0.25)
    local r3_h = math.floor(rows_h * 0.31)
    local r4_h = math.max(Screen:scaleBySize(64), rows_h - r1_h - r2_h - r3_h)

    local data = ctx.data
    local hero = data and data:getFeaturedBook("recently_read", "default", false,
        { w = math.floor(left_w * 0.38), h = r1_h - Screen:scaleBySize(24) }) or nil

    local used = {}
    if hero and hero.path then used[hero.path] = true end

    local active_pool = data and data:getBooksForStripPage("currently_reading", 6, "default", "bento_active", 0) or {}
    local also_books = unique_skipping(active_pool, used, 3)

    local recent_pool = data and data:getBooksForStripPage("recently_read", 12, "default", "bento_recent", 0) or {}
    local pick_back_up = unique_skipping(recent_pool, used, 3)

    local tbr_pool = data and data:getBooksForStripPage("to_be_read", 10, "default", "bento_tbr", 0) or {}
    local discover = unique_skipping(tbr_pool, used, 3)
    if #discover < 3 then
        local fav_pool = data and data:getBooksForStripPage("favorites", 8, "default", "bento_fav", 0) or {}
        for _i, b in ipairs(unique_skipping(fav_pool, used, 3 - #discover)) do
            discover[#discover + 1] = b
        end
    end
    if #discover < 3 then
        for _i, b in ipairs(unique_skipping(recent_pool, used, 3 - #discover)) do
            discover[#discover + 1] = b
        end
    end

    local preview_pool = {}
    if hero then preview_pool[#preview_pool + 1] = hero end
    for _i, b in ipairs(recent_pool) do
        if #preview_pool >= 2 then break end
        if not hero or b.path ~= hero.path then
            preview_pool[#preview_pool + 1] = b
        end
    end

    local stats = StatsDB.queryHomeStats({
        today_pages = true,
        today_duration = true,
        week_pages = true,
        week_duration = true,
        streak = true,
    }) or {}
    local series7 = StatsDB.queryDailySeries(7) or {}
    local counts = LibraryDB.getBookCounts(false) or {}

    local row1_right = VerticalGroup:new{
        align = "left",
        HorizontalGroup:new{
            align = "top",
            build_streak_card(pal, q3_w, mini_h, stats, series7, function() go_page(3) end),
            HorizontalSpan:new{ width = gap },
            build_toggles_card(ctx, pal, q4_w, mini_h),
        },
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "top",
            build_week_card(pal, q3_w, mini_h, stats, series7, function() go_page(3) end),
            HorizontalSpan:new{ width = gap },
            build_goal_card(ctx, pal, q4_w, mini_h, stats, function() go_page(3) end),
        },
    }

    local row1 = HorizontalGroup:new{
        align = "top",
        build_hero_card(ctx, pal, left_w, r1_h, hero, function() go_page(3) end),
        HorizontalSpan:new{ width = gap },
        row1_right,
    }

    local row2 = HorizontalGroup:new{
        align = "top",
        build_also_reading_card(ctx, pal, left_w, r2_h, also_books),
        HorizontalSpan:new{ width = gap },
        build_quote_card(ctx, pal, right_w, r2_h),
    }

    local row3 = HorizontalGroup:new{
        align = "top",
        build_shelf_card(ctx, pal, left_w, r3_h, _("Pick back up"), pick_back_up, 3, "history", "recently_read"),
        HorizontalSpan:new{ width = gap },
        build_get_next_book_card(pal, right_w, r3_h, discover),
    }

    local row4 = HorizontalGroup:new{
        align = "top",
        build_wide_library_tile(ctx, pal, left_w, r4_h, tonumber(counts.total) or 0, preview_pool),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, q3_w, r4_h, "quick_chess", "G", _("Games"), _("Solitaire · Sudoku"),
            open_games_dialog),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, q4_w, r4_h, "app_launcher", "A", _("Apps"), _("Z-Lib · Store"),
            function() go_page(4) end),
    }

    return VerticalGroup:new{
        align = "left",
        row1,
        VerticalSpan:new{ width = gap },
        row2,
        VerticalSpan:new{ width = gap },
        row3,
        VerticalSpan:new{ width = gap },
        row4,
    }
end

local function build_page_shelves(ctx, pal, content_w, grid_h, gap)
    local left_w = math.floor((content_w - gap) / 2)
    local right_w = content_w - gap - left_w
    local q1_w = math.floor((left_w - gap) / 2)
    local q2_w = left_w - gap - q1_w
    local q3_w = math.floor((right_w - gap) / 2)
    local q4_w = right_w - gap - q3_w

    local s_rows = grid_h - gap * 2
    local s1_h = math.floor(s_rows * 0.39)
    local s2_h = math.floor(s_rows * 0.39)
    local s3_h = math.max(Screen:scaleBySize(72), s_rows - s1_h - s2_h)

    local data = ctx.data
    local recent = data and data:getBooksForStripPage("recently_read", 6, "default", "bento_shelves_recent", 0) or {}
    local favs = data and data:getBooksForStripPage("favorites", 6, "default", "bento_shelves_fav", 0) or {}
    local tbr = data and data:getBooksForStripPage("to_be_read", 6, "default", "bento_shelves_tbr", 0) or {}

    return VerticalGroup:new{
        align = "left",
        build_shelf_card(ctx, pal, content_w, s1_h, _("Recently Read"), recent, 5, "history", "recently_read"),
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "top",
            build_shelf_card(ctx, pal, left_w, s2_h, _("Favorites"), favs, 3, "favorites", "favorites"),
            HorizontalSpan:new{ width = gap },
            build_shelf_card(ctx, pal, right_w, s2_h, _("To Be Read"), tbr, 3, "books", "to_be_read"),
        },
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "top",
            build_small_tile(pal, q1_w, s3_h, "tab_authors", "A", _("Authors"), _("Browse authors"),
                function() open_tab(ctx, "authors") end),
            HorizontalSpan:new{ width = gap },
            build_small_tile(pal, q2_w, s3_h, "tab_collections", "C", _("Collections"), _("Saved shelves"),
                function() open_tab(ctx, "collections") end),
            HorizontalSpan:new{ width = gap },
            build_small_tile(pal, q3_w, s3_h, "quick_chess", "G", _("Games"), _("Solitaire · Sudoku"),
                open_games_dialog),
            HorizontalSpan:new{ width = gap },
            build_small_tile(pal, q4_w, s3_h, "tab_exit", "E", _("Exit"), _("Quit KOReader"),
                function()
                    require("common/shutdown").broadcastExit(ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN"))
                end),
        },
    }
end

local function build_heatmap_card(pal, w, h, stats, series90)
    local pad_h = Screen:scaleBySize(14)
    local pad_v = Screen:scaleBySize(12)
    local inner_w = math.max(1, w - pad_h * 2 - 4)
    local inner_h = math.max(1, h - pad_v * 2 - 4)

    local hdr = single_line_text(_("Reading Activity (Last 12 Weeks)"), 13, true, pal.fg, inner_w)
    local body_h = math.max(1, inner_h - hdr:getSize().h - Screen:scaleBySize(10))

    -- Slice trailing 84 days from 90-day series
    local total_90 = #series90
    local start_idx = math.max(1, total_90 - 83)
    local days84 = {}
    local active_days, sum_secs, sum_pages = 0, 0, 0
    for idx = start_idx, total_90 do
        local row = series90[idx]
        days84[#days84 + 1] = row
        local d = tonumber(row.duration) or 0
        local p = tonumber(row.pages) or 0
        sum_secs = sum_secs + d
        sum_pages = sum_pages + p
        if d > 0 or p > 0 then active_days = active_days + 1 end
    end

    local map_w = math.floor(inner_w * 0.58)
    local kpi_w = inner_w - map_w - Screen:scaleBySize(14)
    local cols, rows_cnt = 12, 7
    local cell_gap = Screen:scaleBySize(4)
    local cell = math.max(8, math.min(
        math.floor((map_w - cell_gap * (cols - 1)) / cols),
        math.floor((body_h - cell_gap * (rows_cnt - 1)) / rows_cnt)
    ))

    local grid_widget = Widget:new{ dimen = Geom:new{ w = map_w, h = body_h } }
    grid_widget.paintTo = function(_self, bb, x, y)
        local gy = y + math.floor((body_h - (rows_cnt * cell + (rows_cnt - 1) * cell_gap)) / 2)
        for i = 1, 84 do
            local col_i = math.floor((i - 1) / 7)
            local row_i = (i - 1) % 7
            local d = tonumber(days84[i] and days84[i].duration) or 0
            local fill_col = d <= 0 and pal.heat_0
                or (d < 900 and pal.heat_1 or (d < 2700 and pal.heat_2 or pal.heat_3))
            local cx = x + col_i * (cell + cell_gap)
            local cy = gy + row_i * (cell + cell_gap)
            paint_rounded_fill(bb, cx, cy, cell, cell, fill_col, math.max(2, math.floor(cell * 0.25)))
        end
    end

    local hours_str = string.format("%.1fh", sum_secs / 3600)
    local half_kpi = math.floor((kpi_w - Screen:scaleBySize(8)) / 2)
    local function kpi_box(label, value)
        return VerticalGroup:new{
            align = "left",
            single_line_text(value, 16, true, pal.fg, half_kpi),
            VerticalSpan:new{ width = Screen:scaleBySize(2) },
            single_line_text(label, 10, false, pal.muted, half_kpi),
        }
    end

    local kpis = CenterContainer:new{
        dimen = Geom:new{ w = kpi_w, h = body_h },
        VerticalGroup:new{
            align = "left",
            HorizontalGroup:new{
                align = "top",
                LeftContainer:new{ dimen = Geom:new{ w = half_kpi, h = Screen:scaleBySize(44) }, kpi_box(_("Hours (84d)"), hours_str) },
                HorizontalSpan:new{ width = Screen:scaleBySize(8) },
                LeftContainer:new{ dimen = Geom:new{ w = half_kpi, h = Screen:scaleBySize(44) }, kpi_box(_("Active days"), tostring(active_days)) },
            },
            VerticalSpan:new{ width = Screen:scaleBySize(12) },
            HorizontalGroup:new{
                align = "top",
                LeftContainer:new{ dimen = Geom:new{ w = half_kpi, h = Screen:scaleBySize(44) }, kpi_box(_("Streak"), tostring(stats.streak or 0) .. _("d")) },
                HorizontalSpan:new{ width = Screen:scaleBySize(8) },
                LeftContainer:new{ dimen = Geom:new{ w = half_kpi, h = Screen:scaleBySize(44) }, kpi_box(_("Pages (84d)"), tostring(sum_pages)) },
            },
        },
    }

    local col = VerticalGroup:new{
        align = "left",
        hdr,
        VerticalSpan:new{ width = Screen:scaleBySize(10) },
        HorizontalGroup:new{
            align = "center",
            grid_widget,
            HorizontalSpan:new{ width = Screen:scaleBySize(14) },
            kpis,
        },
    }
    return make_card(w, h, col, pal, { pad_h = pad_h, pad_v = pad_v })
end

local function build_page_insights(ctx, pal, content_w, grid_h, gap)
    local left_w = math.floor((content_w - gap) / 2)
    local right_w = content_w - gap - left_w

    local i_rows = grid_h - gap * 2
    local i1_h = math.floor(i_rows * 0.41)
    local i2_h = math.floor(i_rows * 0.31)
    local i3_h = math.max(Screen:scaleBySize(90), i_rows - i1_h - i2_h)

    local stats = StatsDB.queryHomeStats({
        today_pages = true,
        today_duration = true,
        week_pages = true,
        week_duration = true,
        streak = true,
    }) or {}
    -- Note: StatsDB.queryDailySeries only accepts 7, 14, 30, 90.
    local series90 = StatsDB.queryDailySeries(90) or {}
    local series14 = {}
    for idx = math.max(1, #series90 - 13), #series90 do
        series14[#series14 + 1] = series90[idx]
    end

    local hero = ctx.data and ctx.data:getFeaturedBook("recently_read", "default", false,
        { w = Screen:scaleBySize(56), h = Screen:scaleBySize(84) }) or nil

    -- Row 2 Left: Finish Forecast
    local forecast_card
    do
        local pad_h = Screen:scaleBySize(12)
        local pad_v = Screen:scaleBySize(10)
        local iw = math.max(1, left_w - pad_h * 2 - 4)
        local ih = math.max(1, i2_h - pad_v * 2 - 4)
        local hdr = single_line_text(_("Finish forecast"), 13, true, pal.fg, iw)
        local content_widget
        if hero then
            local ratio = pct_ratio(hero)
            local total_p = tonumber(hero.stable_pages) or tonumber(hero.pages) or 0
            local rem_p = total_p > 0 and math.max(0, math.floor(total_p * (1 - ratio) + 0.5)) or 0
            local t_left = tonumber(hero.time_left_secs)
            local eta_str = (t_left and t_left > 0) and (format_duration(t_left) .. " " .. _("remaining"))
                or (rem_p > 0 and (tostring(rem_p) .. " " .. _("pages remaining")) or _("Ready to open"))
            local cov_h = math.max(Screen:scaleBySize(44), ih - hdr:getSize().h - Screen:scaleBySize(8))
            local cov_w = math.floor(cov_h * 2 / 3)
            local cov = make_bento_cover(ctx.data, hero, cov_w, cov_h, { border = 1 })
            local tw = math.max(1, iw - cov_w - Screen:scaleBySize(10))
            content_widget = HorizontalGroup:new{
                align = "center",
                cov,
                HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                VerticalGroup:new{
                    align = "left",
                    single_line_text(hero.title or "", 12, true, pal.fg, tw),
                    VerticalSpan:new{ width = Screen:scaleBySize(4) },
                    single_line_text(eta_str, 11, false, pal.muted, tw),
                    VerticalSpan:new{ width = Screen:scaleBySize(6) },
                    make_progress_bar(tw, math.max(4, Screen:scaleBySize(5)), ratio, pal.fill, pal.track),
                },
            }
        else
            content_widget = single_line_text(_("Open a book to see ETA"), 11, false, pal.muted, iw)
        end
        forecast_card = make_card(left_w, i2_h, VerticalGroup:new{
            align = "left",
            hdr,
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            content_widget,
        }, pal, {
            pad_h = pad_h,
            pad_v = pad_v,
            on_tap = function() if hero and ctx.openBook then ctx.openBook(hero.path) end end,
        })
    end

    -- Row 2 Right: Last 14 Days Chart
    local rhythm_card
    do
        local pad_h = Screen:scaleBySize(12)
        local pad_v = Screen:scaleBySize(10)
        local iw = math.max(1, right_w - pad_h * 2 - 4)
        local ih = math.max(1, i2_h - pad_v * 2 - 4)
        local dur14, max14 = 0, 1
        for _i, r in ipairs(series14) do
            local d = tonumber(r.duration) or 0
            dur14 = dur14 + d
            if d > max14 then max14 = d end
        end
        local hdr = HorizontalGroup:new{
            align = "center",
            single_line_text(_("14-Day Rhythm"), 13, true, pal.fg, math.floor(iw * 0.65)),
            HorizontalSpan:new{ width = math.max(2, iw - math.floor(iw * 0.65) - single_line_text(format_duration(dur14), 11, true, pal.muted):getSize().w) },
            single_line_text(format_duration(dur14), 11, true, pal.muted),
        }
        local ch = math.max(Screen:scaleBySize(28), ih - hdr:getSize().h - Screen:scaleBySize(10))
        local n_bars = math.max(1, #series14)
        local gap14 = Screen:scaleBySize(4)
        local bw = math.max(4, math.floor((iw - gap14 * (n_bars - 1)) / n_bars))
        local chart14 = Widget:new{ dimen = Geom:new{ w = iw, h = ch } }
        chart14.paintTo = function(_self, bb, x, y)
            local sx = x + math.floor((iw - (bw * n_bars + gap14 * (n_bars - 1))) / 2)
            for idx = 1, n_bars do
                local d = tonumber(series14[idx] and series14[idx].duration) or 0
                local bh = d > 0 and math.max(Screen:scaleBySize(5), math.floor(ch * (d / max14))) or Screen:scaleBySize(3)
                local col = d > 0 and (idx == n_bars and pal.fg or Blitbuffer.COLOR_GRAY_5) or pal.track
                paint_rounded_fill(bb, sx + (idx - 1) * (bw + gap14), y + ch - bh, bw, bh, col, 2)
            end
        end
        rhythm_card = make_card(right_w, i2_h, VerticalGroup:new{
            align = "left",
            hdr,
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            chart14,
        }, pal, { pad_h = pad_h, pad_v = pad_v })
    end

    -- Row 3 Left: Reading Goals
    local goals_card
    do
        local pad_h = Screen:scaleBySize(12)
        local pad_v = Screen:scaleBySize(10)
        local iw = math.max(1, left_w - pad_h * 2 - 4)
        local goals = ReadingGoals.normalize(type(ctx.config) == "table" and ctx.config.goals or nil)
        local d_metric = goals.metrics and goals.metrics.daily or "pages"
        local d_cur = d_metric == "time" and math.floor((stats.today_duration or 0) / 60) or (stats.today_pages or 0)
        local d_tgt = d_metric == "time" and (goals.daily_time_target_min or 30) or (goals.daily_pages_target or 30)
        local w_metric = goals.metrics and goals.metrics.weekly or "pages"
        local w_cur = w_metric == "time" and math.floor((stats.week_duration or 0) / 60) or (stats.week_pages or 0)
        local w_tgt = w_metric == "time" and (goals.weekly_time_target_min or 210) or (goals.weekly_pages_target or 210)
        local bh = math.max(5, Screen:scaleBySize(6))
        local col = VerticalGroup:new{
            align = "left",
            single_line_text(_("Reading Goals"), 13, true, pal.fg, iw),
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            single_line_text(string.format("%s: %d / %d%s", _("Daily"), d_cur, d_tgt, d_metric == "time" and "m" or "p"), 10, false, pal.muted, iw),
            VerticalSpan:new{ width = Screen:scaleBySize(3) },
            make_progress_bar(iw, bh, d_tgt > 0 and (d_cur / d_tgt) or 0, pal.fill, pal.track),
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            single_line_text(string.format("%s: %d / %d%s", _("Weekly"), w_cur, w_tgt, w_metric == "time" and "m" or "p"), 10, false, pal.muted, iw),
            VerticalSpan:new{ width = Screen:scaleBySize(3) },
            make_progress_bar(iw, bh, w_tgt > 0 and (w_cur / w_tgt) or 0, pal.fill, pal.track),
        }
        goals_card = make_card(left_w, i3_h, col, pal, { pad_h = pad_h, pad_v = pad_v })
    end

    -- Row 3 Right: Quick Tools & Plugins
    local tools_card
    do
        local pad_h = Screen:scaleBySize(12)
        local pad_v = Screen:scaleBySize(10)
        local iw = math.max(1, right_w - pad_h * 2 - 4)
        local ih = math.max(1, i3_h - pad_v * 2 - 4)
        local hdr = single_line_text(_("Tools & Plugins"), 13, true, pal.fg, iw)
        local b_gap = Screen:scaleBySize(8)
        local bw = math.floor((iw - b_gap) / 2)
        local bh = math.max(Screen:scaleBySize(26), math.floor((ih - hdr:getSize().h - b_gap - Screen:scaleBySize(8)) / 2))

        local function chip(label, icon_name, cb)
            local box = FrameContainer:new{
                width = bw,
                height = bh,
                padding = 0,
                bordersize = 1,
                radius = Screen:scaleBySize(10),
                color = pal.card_border,
                background = pal.chip_bg,
                CenterContainer:new{
                    dimen = Geom:new{ w = bw - 2, h = bh - 2 },
                    HorizontalGroup:new{
                        align = "center",
                        make_icon(icon_name, Screen:scaleBySize(15), "*", pal.fg),
                        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
                        single_line_text(label, 11, true, pal.fg, bw - Screen:scaleBySize(30)),
                    },
                },
            }
            return wrap_tap(box, bw, bh, cb)
        end

        tools_card = make_card(right_w, i3_h, VerticalGroup:new{
            align = "left",
            hdr,
            VerticalSpan:new{ width = Screen:scaleBySize(8) },
            HorizontalGroup:new{
                align = "center",
                chip("ZenPM", "zenpm", function() launch_plugin("zenpm", { "onOpenZenPM", "onZenPM", "show" }, "ZenPM") end),
                HorizontalSpan:new{ width = b_gap },
                chip("ZenFM", "zenfm", function() launch_plugin("zenfm", { "onShowZenFMStatus", "onToggleZenFM" }, "ZenFM") end),
            },
            VerticalSpan:new{ width = b_gap },
            HorizontalGroup:new{
                align = "center",
                chip(_("Games"), "quick_chess", open_games_dialog),
                HorizontalSpan:new{ width = b_gap },
                chip(_("Settings"), "zen_ui", function()
                    local sp = require("modules/settings/zen_settings_page")
                    if sp and type(sp.show) == "function" then
                        sp.show(ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN"))
                    end
                end),
            },
        }, pal, { pad_h = pad_h, pad_v = pad_v })
    end

    return VerticalGroup:new{
        align = "left",
        build_heatmap_card(pal, content_w, i1_h, stats, series90),
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "top",
            forecast_card,
            HorizontalSpan:new{ width = gap },
            rhythm_card,
        },
        VerticalSpan:new{ width = gap },
        HorizontalGroup:new{
            align = "top",
            goals_card,
            HorizontalSpan:new{ width = gap },
            tools_card,
        },
    }
end

local function split_widths(total_w, n, gap)
    local base = math.floor((total_w - gap * (n - 1)) / n)
    local rem = total_w - gap * (n - 1) - base * n
    local out = {}
    for i = 1, n do
        out[i] = base + (i <= rem and 1 or 0)
    end
    return out
end

local function build_page_apps(ctx, pal, content_w, grid_h, gap)
    local left_w = math.floor((content_w - gap) / 2)
    local right_w = content_w - gap - left_w

    local rows_h = grid_h - gap * 3
    local a1_h = math.floor(rows_h * 0.28)
    local a2_h = math.floor(rows_h * 0.23)
    local a3_h = math.floor(rows_h * 0.25)
    local a4_h = math.max(Screen:scaleBySize(64), rows_h - a1_h - a2_h - a3_h)

    local row1 = HorizontalGroup:new{
        align = "top",
        build_featured_app_card(
            pal, left_w, a1_h,
            "quick_zlib", "Z", _("FEATURED · Z-LIBRARY"),
            _("Get next book"),
            _("Search millions of titles, popular picks & My Books"),
            "⌕  " .. _("Search Z-Lib ›"),
            function() open_zlibrary("search") end,
            function() open_zlibrary("menu") end,
            true
        ),
        HorizontalSpan:new{ width = gap },
        build_featured_app_card(
            pal, right_w, a1_h,
            "settings_download", "S", _("DISCOVER & INSTALL"),
            _("App Store"),
            _("Browse community plugins and KOReader user patches"),
            _("Open Store ›"),
            function()
                launch_plugin("appstore", { "showBrowser", "onOpenAppStoreMenu", "onShowAppStore" }, _("App Store"))
            end,
            nil,
            false
        ),
    }

    local w4 = split_widths(content_w, 4, gap)
    local row2 = HorizontalGroup:new{
        align = "top",
        build_small_tile(pal, w4[1], a2_h, "zenpm", "P", "ZenPM", _("Packages & patches"),
            function() launch_plugin("zenpm", { "onOpenZenPM", "onZenPM", "show" }, "ZenPM") end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[2], a2_h, "zenfm", "F", "ZenFM", _("Wi-Fi file server"),
            function() launch_plugin("zenfm", { "onShowZenFMStatus", "onToggleZenFM" }, "ZenFM") end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[3], a2_h, "quick_opds", "O", "OPDS", _("Online catalogs"),
            function() launch_plugin("opds", { "onShowOPDSCatalog" }, "OPDS") end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[4], a2_h, "quick_calibre", "C", "Calibre", _("Wireless sync"),
            function() launch_plugin("calibre", { "onCalibreSearch", "onStartWirelessConnection" }, "Calibre") end),
    }

    local w5 = split_widths(content_w, 5, gap)
    local row3 = HorizontalGroup:new{
        align = "top",
        build_small_tile(pal, w5[1], a3_h, "quick_chess", "S", _("Solitaire"), _("Klondike cards"),
            function() launch_plugin("solitaire", { "startGame" }, _("Solitaire")) end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w5[2], a3_h, "quick_puzzle", "9", _("Sudoku"), _("Number puzzle"),
            function() launch_plugin("sudoku", { "showGame" }, _("Sudoku")) end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w5[3], a3_h, "quick_puzzle", "M", _("Minesweeper"), _("Clear the grid"),
            function() launch_plugin("boardgames", { "onShowMinesweeper" }, _("Minesweeper")) end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w5[4], a3_h, "quick_crossword", "?", _("Murdoku"), _("Logic mystery"),
            function() launch_plugin("murdoku", { "openCaseList", "onOpenMurdoku" }, _("Murdoku")) end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w5[5], a3_h, "quick_chess", "B", _("Board Games"), _("Chess · Checkers"),
            function() launch_plugin("boardgames", { "show_board" }, _("Board Games")) end),
    }

    local row4 = HorizontalGroup:new{
        align = "top",
        build_small_tile(pal, w4[1], a4_h, "quick_stats_progress", "I", _("Insights"), _("Reading Insights"),
            function() launch_plugin("readinginsights", { "onShowReadingInsights" }, _("Reading Insights")) end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[2], a4_h, "quick_sync", "Y", _("Cloud Sync"), _("KoInsight / Readest"),
            function()
                if find_plugin("koinsight") then
                    launch_plugin("koinsight", { "onKoInsightSync" }, "KoInsight")
                else
                    launch_plugin("readest", nil, "Readest")
                end
            end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[3], a4_h, "terminal", "$", "SSH", _("Remote terminal"),
            function() launch_plugin("SSH", { "onToggleSSHServer" }, "SSH") end),
        HorizontalSpan:new{ width = gap },
        build_small_tile(pal, w4[4], a4_h, "zen_ui", "Z", _("Zen Settings"), _("Customize ZenOS"),
            function()
                local sp = require("modules/settings/zen_settings_page")
                if sp and type(sp.show) == "function" then
                    sp.show(ctx.plugin or rawget(_G, "__ZEN_UI_PLUGIN"))
                end
            end),
    }

    return VerticalGroup:new{
        align = "left",
        row1,
        VerticalSpan:new{ width = gap },
        row2,
        VerticalSpan:new{ width = gap },
        row3,
        VerticalSpan:new{ width = gap },
        row4,
    }
end

local function build_footer(ctx, pal, width, height, page, go_page)
    if ctx.readonly then
        return CenterContainer:new{
            dimen = Geom:new{ w = width, h = height },
            single_line_text("☾  " .. _("Lock Screen  ·  Press power button to wake"), 11, false, pal.muted, width),
        }
    end
    local btn_w = Screen:scaleBySize(64)
    local prev_btn = wrap_tap(FrameContainer:new{
        width = btn_w,
        height = height,
        padding = 0,
        bordersize = 1,
        radius = math.floor(height / 2),
        color = pal.card_border,
        background = pal.card_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = btn_w - 2, h = height - 2 },
            single_line_text("‹  " .. _("Prev"), 11, true, pal.fg, btn_w - 8),
        },
    }, btn_w, height, function() go_page((page - 2) % M.PAGE_COUNT + 1) end)

    local next_btn = wrap_tap(FrameContainer:new{
        width = btn_w,
        height = height,
        padding = 0,
        bordersize = 1,
        radius = math.floor(height / 2),
        color = pal.card_border,
        background = pal.card_bg,
        CenterContainer:new{
            dimen = Geom:new{ w = btn_w - 2, h = height - 2 },
            single_line_text(_("Next") .. "  ›", 11, true, pal.fg, btn_w - 8),
        },
    }, btn_w, height, function() go_page(page % M.PAGE_COUNT + 1) end)

    local dots = HorizontalGroup:new{ align = "center" }
    local dot_d = Screen:scaleBySize(8)
    for p = 1, M.PAGE_COUNT do
        local is_active = p == page
        local dw = is_active and Screen:scaleBySize(18) or dot_d
        local dot = FrameContainer:new{
            width = dw,
            height = dot_d,
            padding = 0,
            bordersize = 0,
            radius = math.floor(dot_d / 2),
            background = is_active and pal.fg or pal.card_border,
            Widget:new{ dimen = Geom:new{ w = dw, h = dot_d } },
        }
        dots[#dots + 1] = wrap_tap(
            CenterContainer:new{ dimen = Geom:new{ w = dw + 6, h = height }, dot },
            dw + 6, height, function() go_page(p) end
        )
        if p < M.PAGE_COUNT then
            dots[#dots + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(6) }
        end
    end
    dots[#dots + 1] = HorizontalSpan:new{ width = Screen:scaleBySize(10) }
    dots[#dots + 1] = single_line_text(PAGE_NAMES[page] or "", 12, true, pal.fg)

    local center_w = math.max(1, width - btn_w * 2 - Screen:scaleBySize(16))
    return HorizontalGroup:new{
        align = "center",
        prev_btn,
        HorizontalSpan:new{ width = Screen:scaleBySize(8) },
        CenterContainer:new{ dimen = Geom:new{ w = center_w, h = height }, dots },
        HorizontalSpan:new{ width = Screen:scaleBySize(8) },
        next_btn,
    }
end

local function build_board_internal(ctx)
    local menu = ctx.menu
    local pal = get_palette()
    local screen_w = Screen:getWidth()
    local screen_h = Screen:getHeight()

    local page = ctx.readonly and 1 or (tonumber(menu and menu._zen_bento_page) or 1)
    if page < 1 or page > M.PAGE_COUNT then page = 1 end
    if menu and not ctx.readonly then menu._zen_bento_page = page end

    local function go_page(target_page)
        if ctx.readonly then return end
        local p = ((tonumber(target_page) or 1) - 1) % M.PAGE_COUNT + 1
        if menu then menu._zen_bento_page = p end
        if ctx.rebuildHome then
            ctx.rebuildHome(false, getFullRefreshMode())
        end
    end

    local side_pad = math.max(12, math.floor(screen_w * 0.026))
    local content_w = screen_w - side_pad * 2
    local gap = math.max(8, math.floor(screen_w * 0.013))
    local pad_top = math.max(8, math.floor(screen_h * 0.011))
    local pad_bottom = math.max(6, math.floor(screen_h * 0.008))
    local header_h = math.floor(screen_h * 0.064)
    local footer_h = math.floor(screen_h * 0.038)
    local grid_h = math.max(200, screen_h - pad_top - header_h - gap - footer_h - gap - pad_bottom)

    local header = build_header(ctx, pal, content_w, header_h)
    local grid
    if page == 2 then
        grid = build_page_shelves(ctx, pal, content_w, grid_h, gap)
    elseif page == 3 then
        grid = build_page_insights(ctx, pal, content_w, grid_h, gap)
    elseif page == 4 then
        grid = build_page_apps(ctx, pal, content_w, grid_h, gap)
    else
        grid = build_page_home(ctx, pal, content_w, grid_h, gap, go_page)
    end
    local footer = build_footer(ctx, pal, content_w, footer_h, page, go_page)

    local root_col = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = pad_top },
        header,
        VerticalSpan:new{ width = gap },
        LeftContainer:new{ dimen = Geom:new{ w = content_w, h = grid_h }, grid },
        VerticalSpan:new{ width = gap },
        footer,
        VerticalSpan:new{ width = pad_bottom },
    }

    return FrameContainer:new{
        width = screen_w,
        height = screen_h,
        padding_left = side_pad,
        padding_right = side_pad,
        padding_top = 0,
        padding_bottom = 0,
        bordersize = 0,
        background = pal.canvas_bg,
        root_col,
    }
end

function M.build(ctx)
    local prev_ro = _readonly_mode
    _readonly_mode = (type(ctx) == "table" and ctx.readonly == true)
    local ok, res = pcall(build_board_internal, ctx or {})
    _readonly_mode = prev_ro
    if not ok then
        error(res)
    end
    return res
end

function M.buildLockScreen(ctx)
    local lock_ctx = {}
    if type(ctx) == "table" then
        for k, v in pairs(ctx) do
            lock_ctx[k] = v
        end
    end
    lock_ctx.readonly = true
    lock_ctx.menu = nil
    return M.build(lock_ctx)
end

return M
