-- ZenOS: Highlight menu
-- Instant-save pastel highlight circles on selection + merged edit menu + 1-row category color panel.

local function apply()
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    local Blitbuffer = require("ffi/blitbuffer")
    local ButtonDialog = require("ui/widget/buttondialog")
    local CenterContainer = require("ui/widget/container/centercontainer")
    local ColorCircle = require("common/ui/zen_color_circle")
    local Device = require("device")
    local Event = require("ui/event")
    local Font = require("ui/font")
    local Geom = require("ui/geometry")
    local Handles = require("modules/reader/highlight_handles")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local InputContainer = require("ui/widget/container/inputcontainer")
    local Labels = require("common/ui/button_labels")
    local LookupPluginItems = require("modules/reader/lookup_plugin_items")
    local MenuItems = require("modules/reader/highlight_menu_items")
    local ReaderView = require("apps/reader/modules/readerview")
    local References = require("modules/reader/references")
    local TextBoxWidget = require("ui/widget/textboxwidget")
    local TextWidget = require("ui/widget/textwidget")
    local UIManager = require("ui/uimanager")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local Viewport = require("modules/reader/highlight_viewport")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local GestureRange = require("ui/gesturerange")
    local time = require("ui/time")
    local _ = require("gettext")
    local utils = require("common/utils")
    local plugin_root = require("common/plugin_root")
    local _icons_dir = plugin_root and plugin_root .. "/icons/"
    local _stock_icons_dir = require("libs/libkoreader-lfs").currentdir() .. "/resources/icons/mdlight/"
    local menu_icons = {
        style = utils.resolveLocalIcon(_icons_dir, "font"),
        color = utils.resolveLocalIcon(_icons_dir, "paint_palette"),
        note = utils.resolveLocalIcon(_icons_dir, "edit"),
        delete = utils.resolveLocalIcon(_icons_dir, "trash"),
        more = utils.resolveLocalIcon(_icons_dir, "more_vertical"),
    }
    local settings_icon = utils.resolveLocalIcon(_stock_icons_dir, "appbar.settings")
    local ai_icon = utils.resolveIcon(_icons_dir, "lookup_ai")
    local logger = require("common/zen_logger").new("highlight_menu")

    local paintTo = ReaderView.paintTo
    ReaderView.paintTo = function(self, bb, x, y)
        paintTo(self, bb, x, y)
        Viewport.paintMargins(self, bb, x, y)
    end

    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")

    local function is_enabled()
        local features = _plugin_ref
            and _plugin_ref.config
            and _plugin_ref.config.features
        return type(features) == "table" and features.highlight_lookup == true
    end

    local function get_lookup_cfg()
        return (_plugin_ref and _plugin_ref.config and _plugin_ref.config.highlight_lookup) or {}
    end

    -- Selection uses default highlight color instead of gray, unless user opted out
    if is_enabled() and G_reader_settings:readSetting("highlight_selection_use_highlight_color") == nil then
        G_reader_settings:saveSetting("highlight_selection_use_highlight_color", true)
    end

    local ReaderUI = require("apps/reader/readerui")
    local handleEvent = ReaderUI.handleEvent
    ReaderUI.handleEvent = function(self, event)
        if is_enabled() and event.handler == "onGesture" then
            local highlight = self.highlight
            local deadline = highlight and highlight._zen_highlight_tap_until
            if deadline then
                if time.now() >= deadline then
                    highlight._zen_highlight_tap_until = nil
                elseif event.args[1].ges == "tap" or event.args[1].ges == "double_tap" then
                    return true
                end
            end
        end
        return handleEvent(self, event)
    end

    local onHoldRelease = ReaderHighlight.onHoldRelease
    ReaderHighlight.onHoldRelease = function(self, ...)
        if is_enabled() and self.selected_text then Handles.suppressReaderTaps(self) end
        return onHoldRelease(self, ...)
    end

    local function show_wikipedia()
        return get_lookup_cfg().show_wikipedia == true
    end

    local function show_ai_assistant()
        return get_lookup_cfg().show_ai_assistant ~= false
    end

    local function show_labels()
        return get_lookup_cfg().show_labels == true
    end

    local function apply_highlight_color(hl, index, color_id)
        G_reader_settings:saveSetting("highlight_color", color_id)
        hl.view.highlight.saved_color = color_id
        if hl.setSelectionColor then hl:setSelectionColor() end
        local item = index and hl.ui and hl.ui.annotation and hl.ui.annotation.annotations[index]
        if item and item.color ~= color_id then
            hl:writePdfAnnotation("delete", item)
            item.color = color_id
            if hl.ui.paging then
                hl:writePdfAnnotation("save", item)
                if item.note then
                    hl:writePdfAnnotation("content", item, item.note)
                end
            end
            UIManager:setDirty(hl.dialog, "ui")
            hl.ui:handleEvent(Event:new("AnnotationsModified", { item }))
        end
    end

    local function attach_color_circles(hl, dialog, active_color, index, close_on_pick)
        if not dialog or type(dialog.addWidget) ~= "function" then return end
        local avail_w = dialog:getAddedWidgetAvailableWidth()
        local circle_row = ColorCircle.buildRow(hl, active_color, function(color_id)
            apply_highlight_color(hl, index, color_id)
            if close_on_pick then
                UIManager:close(dialog)
                if hl.selected_text then
                    hl:clear()
                end
            else
                UIManager:setDirty(dialog, "ui")
            end
        end, { width = avail_w })
        circle_row.separator = true
        dialog:addWidget(circle_row)
    end

    local function find_highlight_button(self, index, name)
        if not self._highlight_buttons then return nil end
        for key, fn_button in pairs(self._highlight_buttons) do
            local key_name = key:match("^%d+_(.*)$") or key
            if key_name == name then
                local ok, btn = pcall(fn_button, self, index)
                if ok and type(btn) == "table" and btn.callback then
                    return btn
                end
                return nil
            end
        end
        return nil
    end

    local KNOWN_KEYS = {
        select = true, highlight = true, search = true, translate = true,
        wikipedia = true, dictionary = true, add_note = true,
        ai_assistant = true,
    }

    local function get_selection_anchor(self, dialog, index)
        local boxes = index and self:getHighlightVisibleBoxes(index)
            or (self.selected_text and (self.selected_text.sboxes or self.selected_text.pboxes))
        if not boxes or #boxes == 0 then
            return self:_getDialogAnchor(dialog, index)
        end

        local page = self.ui.paging and (index
            and self.ui.annotation.annotations[index].pos0.page
            or (self.selected_text and self.selected_text.pos0.page))
        local y0, y1
        for _i, box in ipairs(boxes) do
            if page then box = self.view:pageToScreenTransform(page, box) end
            if box then
                y0 = math.min(y0 or box.y, box.y)
                y1 = math.max(y1 or box.y + box.h, box.y + box.h)
            end
        end
        if not y0 then return self:_getDialogAnchor(dialog, index) end

        local padding = require("ui/size").padding.small
        local above = y0 - padding
        local below = self.screen_h - y1 - padding
        local x = math.floor((self.screen_w - dialog:getContentSize().w) / 2)
        return { x = x, y = above, w = 0, h = y1 - y0 + 2 * padding }, below >= above
    end

    -- -------------------------------------------------------------------------
    -- Override: showHighlightColorDialog (1-row-per-category list with descriptions)
    -- -------------------------------------------------------------------------
    local orig_showHighlightColorDialog = ReaderHighlight.showHighlightColorDialog
    ReaderHighlight.showHighlightColorDialog = function(self, caller_callback, item)
        if not is_enabled() then
            return orig_showHighlightColorDialog(self, caller_callback, item)
        end
        local Screen = Device.screen
        local curr_color = (item and item.color)
            or G_reader_settings:readSetting("highlight_color")
            or self.view.highlight.saved_color
            or "yellow"
        local order = self.getHighlightColorOrder and self.getHighlightColorOrder()
            or { "yellow", "blue", "green", "red", "orange" }
        local seen = {}
        local ordered = {}
        for _i, cid in ipairs(order) do
            ordered[#ordered + 1] = cid
            seen[cid] = true
        end
        if curr_color and not seen[curr_color] then
            ordered[#ordered + 1] = curr_color
        end

        local dlg
        dlg = ButtonDialog:new{
            title = _("Highlight category"),
            width_factor = 0.85,
            buttons = {{
                {
                    text = _("Close"),
                    callback = function() UIManager:close(dlg) end,
                },
            }},
        }
        local avail_w = dlg:getAddedWidgetAvailableWidth()
        local pad = Screen:scaleBySize(6)
        local circle_sz = Screen:scaleBySize(34)
        local text_w = math.max(100, avail_w - circle_sz - pad * 3)
        local rows_group = VerticalGroup:new{ align = "left", not_focusable = true }

        for idx, cid in ipairs(ordered) do
            local label = self.getHighlightColorString and self:getHighlightColorString(cid) or cid
            local hex = self.getHighlightColorCode and self:getHighlightColorCode(cid) or "#F6DF96"
            local desc = self.getHighlightColorDescription and self:getHighlightColorDescription(cid) or ""
            local is_curr = cid == curr_color
            local swatch = ColorCircle.ColorCircle:new{
                size = circle_sz,
                color_id = cid,
                hex = hex,
                label = label,
                description = desc,
                selected = is_curr,
                show_caption = false,
            }
            local title_w = TextWidget:new{
                text = label .. (is_curr and "  ✓" or ""),
                face = Font:getFace("smallinfofont", 18),
                bold = true,
                max_width = text_w,
                padding = 0,
            }
            local text_col = VerticalGroup:new{ align = "left", title_w }
            if desc ~= "" then
                table.insert(text_col, VerticalSpan:new{ width = Screen:scaleBySize(2) })
                table.insert(text_col, TextBoxWidget:new{
                    text = desc,
                    face = Font:getFace("xx_smallinfofont", 14),
                    fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                    width = text_w,
                })
            end
            local row_box = HorizontalGroup:new{
                align = "center",
                swatch,
                HorizontalSpan:new{ width = Screen:scaleBySize(10) },
                text_col,
            }
            local row_frame = FrameContainer:new{
                bordersize = is_curr and Screen:scaleBySize(2) or Screen:scaleBySize(1),
                color = is_curr and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_LIGHT_GRAY,
                radius = Screen:scaleBySize(8),
                padding = pad,
                width = avail_w,
                row_box,
            }
            local rf_sz = row_frame:getSize()
            local hit = InputContainer:new{
                dimen = Geom:new{ w = rf_sz.w, h = rf_sz.h },
                row_frame,
            }
            hit.ges_events = {
                TapRow = { GestureRange:new{ ges = "tap", range = hit.dimen } },
            }
            hit.paintTo = function(w_self, bb, x, y)
                w_self.dimen.x = x
                w_self.dimen.y = y
                w_self[1]:paintTo(bb, x, y)
            end
            hit.onTapRow = function()
                UIManager:close(dlg)
                if type(caller_callback) == "function" then
                    caller_callback(cid)
                end
                return true
            end
            table.insert(rows_group, hit)
            if idx < #ordered then
                table.insert(rows_group, VerticalSpan:new{ width = Screen:scaleBySize(6) })
            end
        end

        dlg:addWidget(CenterContainer:new{
            not_focusable = true,
            dimen = Geom:new{ w = avail_w, h = rows_group:getSize().h },
            rows_group,
        })
        UIManager:show(dlg)
    end

    -- -------------------------------------------------------------------------
    -- Override: onShowHighlightMenu (instant-save + compact circle + icon bar)
    -- -------------------------------------------------------------------------
    local orig_onShowHighlightMenu = ReaderHighlight.onShowHighlightMenu
    logger.dbg("orig_onShowHighlightMenu=", tostring(orig_onShowHighlightMenu))

    local function show_menu(self, index, more)
        if not is_enabled() then
            return orig_onShowHighlightMenu(self, index)
        end
        if not self.selected_text then
            return
        end

        local cfg = get_lookup_cfg()
        local instant_save = not index and not more and cfg.instant_save ~= false and self.hold_pos ~= nil
        local function use_default_color()
            local c = G_reader_settings:readSetting("highlight_color") or self._fallback_color or "yellow"
            self.view.highlight.saved_color = c
            self.view.highlight.saved_drawer = self.view.highlight.saved_drawer or "lighten"
            if self.setSelectionColor then self:setSelectionColor() end
            return c
        end

        local saved_idx = index
        local active_color = use_default_color()
        if instant_save then
            local ok_save, res_idx = pcall(self.saveHighlight, self, not self.selected_text._zen_resized)
            if ok_save and type(res_idx) == "number" then
                saved_idx = res_idx
                local saved_item = self.ui and self.ui.annotation and self.ui.annotation.annotations[saved_idx]
                if saved_item and saved_item.color then
                    active_color = saved_item.color
                end
            end
        end

        local buttons = {{}}
        local labels = show_labels()

        if saved_idx then
            table.insert(buttons[1], {
                icon = menu_icons.note,
                text = labels and _("Note") or nil,
                callback = function()
                    local sel_text = self.selected_text and self.selected_text.text
                    self:onClose()
                    self:editNote(saved_idx, true, sel_text and nil or nil)
                end,
            })
        else
            buttons[1][1] = {
                icon = "lookup.highlight",
                text = labels and _("Highlight") or nil,
                enabled = self.hold_pos ~= nil,
                callback = function()
                    use_default_color()
                    self:saveHighlight(not self.selected_text._zen_resized)
                    self:onClose()
                end,
            }
            local note_btn = find_highlight_button(self, nil, "add_note")
            if note_btn then
                buttons[1][2] = {
                    icon = menu_icons.note,
                    text = labels and _("Note") or nil,
                    enabled = note_btn.enabled ~= false,
                    callback = function()
                        use_default_color()
                        note_btn.callback()
                    end,
                }
            end
        end

        if show_wikipedia() then
            table.insert(buttons[1], {
                icon = "lookup.wikipedia",
                text = labels and _("Wikipedia") or nil,
                callback = function()
                    UIManager:scheduleIn(0.1, LookupPluginItems.safeCallback(function()
                        self:lookupWikipedia()
                    end))
                end,
            })
        end

        table.insert(buttons[1], {
            icon = "lookup.dictionary",
            text = labels and _("Dictionary") or nil,
            callback = function()
                self.ui:handleEvent(Event:new("LookupWord", self.selected_text.text, true))
                self:onClose()
            end,
        })
        table.insert(buttons[1], {
            icon = "lookup.translate",
            text = labels and _("Translate") or nil,
            callback = function()
                self:translate(saved_idx)
            end,
        })

        if show_ai_assistant() then
            local ai_btn = find_highlight_button(self, saved_idx, "ai_assistant")
            if ai_btn then
                table.insert(buttons[1], {
                    icon = ai_icon,
                    text = labels and _("AI assistant") or nil,
                    enabled = ai_btn.enabled ~= false,
                    callback = ai_btn.callback,
                })
            end
        end

        table.insert(buttons[1], {
            icon = "lookup.search",
            text = labels and _("Search") or nil,
            callback = function()
                self:onHighlightSearch()
            end,
        })

        if saved_idx then
            table.insert(buttons[1], {
                icon = menu_icons.delete,
                text = labels and _("Delete") or nil,
                callback = function()
                    self:deleteHighlight(saved_idx)
                    self:onClose()
                end,
            })
        end

        -- Recognized companion plugins sit under the icon row; opted-in other items live behind More.
        if self._highlight_buttons then
            local ffiUtil = require("ffi/util")
            local extra, other = {}, {}
            for key, fn_button in ffiUtil.orderedPairs(self._highlight_buttons) do
                local key_name = key:match("^%d+_(.*)$") or key
                local plugin_setting = LookupPluginItems.settingForHighlightKey(key)
                if not KNOWN_KEYS[key_name]
                        and LookupPluginItems.shouldShow(
                            _plugin_ref and _plugin_ref.config, plugin_setting, "highlight_lookup") then
                    local ok, btn = pcall(fn_button, self, saved_idx)
                    if ok and btn then
                        if not btn.show_in_highlight_dialog_func
                            or btn.show_in_highlight_dialog_func() then
                            table.insert((plugin_setting or saved_idx) and extra or other, btn)
                        end
                    end
                end
            end
            if more then
                buttons, extra = {}, other
            elseif #other > 0 then
                table.insert(buttons[1], {
                    id = "zen_highlight_more", icon = menu_icons.more,
                    text = labels and _("More") or nil,
                    callback = function()
                        local controller = self._zen_highlight_handles
                        if controller then controller.reopening = true end
                        UIManager:close(self.highlight_dialog)
                        show_menu(self, saved_idx, true)
                    end,
                })
            end
            local max_cols = 2
            for i = 1, #extra, max_cols do
                local row = {}
                for j = i, math.min(i + max_cols - 1, #extra) do
                    row[#row + 1] = extra[j]
                end
                table.insert(buttons, row)
            end
        end

        if not more then
            References.addPinButton(buttons, self.ui, References.selectionPage(self, saved_idx), function() self:onClose() end)
        end
        LookupPluginItems.protectButtons(buttons)
        if labels then buttons = Labels.prepare(buttons) end
        MenuItems.compact(buttons)
        self.highlight_dialog = ButtonDialog:new{
            buttons = buttons,
            anchor = function()
                return get_selection_anchor(self, self.highlight_dialog, saved_idx)
            end,
            tap_close_callback = function()
                if self.hold_pos or self.selected_text then
                    self:clear()
                end
            end,
        }
        if not more and saved_idx then
            attach_color_circles(self, self.highlight_dialog, active_color, saved_idx, true)
        end
        if labels then Labels.apply(self.highlight_dialog.buttontable, buttons) end
        Handles.attach(self, self.highlight_dialog, saved_idx, function()
            self:onShowHighlightMenu(saved_idx)
        end)
        UIManager:show(self.highlight_dialog, "[ui]")
    end
    ReaderHighlight.onShowHighlightMenu = function(self, index) return show_menu(self, index) end

    local orig_showHighlightDialog = ReaderHighlight.showHighlightDialog
    ReaderHighlight.showHighlightDialog = function(self, index)
        if not is_enabled() then return orig_showHighlightDialog(self, index) end
        local original_new = ButtonDialog.new
        ButtonDialog.new = function(class, spec, ...)
            if spec.name ~= "edit_highlight_dialog" then return original_new(class, spec, ...) end
            local settings = get_lookup_cfg()
            local available = Handles.available(self, index)
            local original_buttons = spec.buttons
            spec.buttons = MenuItems.arrange(spec.buttons, settings, available, menu_icons)
            References.addPinButton(spec.buttons, self.ui, References.selectionPage(self, index), function() self:onClose() end)
            if settings.show_labels then spec.buttons = Labels.prepare(spec.buttons) end
            MenuItems.compact(spec.buttons)
            local empty = #spec.buttons == 0
            if empty then spec.buttons = {{ { text = "", enabled = false } }} end
            local dialog = original_new(class, spec, ...)
            if settings.show_labels then Labels.apply(dialog.buttontable, spec.buttons) end
            if empty then dialog.buttons = {} end
            local item = self.ui and self.ui.annotation and self.ui.annotation.annotations[index]
            attach_color_circles(self, dialog, item and item.color, index, true)
            local controller = Handles.attach(self, dialog, index, function()
                self:showHighlightDialog(index)
            end)
            if available and not controller then
                dialog.buttons = MenuItems.arrange(original_buttons, settings, false, menu_icons)
                References.addPinButton(dialog.buttons, self.ui, References.selectionPage(self, index), function() self:onClose() end)
                if settings.show_labels then dialog.buttons = Labels.prepare(dialog.buttons) end
                MenuItems.compact(dialog.buttons)
                dialog:reinit()
                if settings.show_labels then Labels.apply(dialog.buttontable, dialog.buttons) end
                attach_color_circles(self, dialog, item and item.color, index, true)
            end
            self.highlight_dialog = dialog
            return dialog
        end
        local ok, result = pcall(orig_showHighlightDialog, self, index)
        ButtonDialog.new = original_new
        if not ok then error(result) end
        return result
    end

    local ReaderBookmark = require("apps/reader/modules/readerbookmark")
    local orig_setBookmarkNote = ReaderBookmark.setBookmarkNote
    ReaderBookmark.setBookmarkNote = function(self, item_or_index, ...)
        if not is_enabled() then return orig_setBookmarkNote(self, item_or_index, ...) end
        local index = self.bookmark_menu and self:getBookmarkItemIndex(item_or_index) or item_or_index
        local annotation = self.ui.annotation.annotations[index]
        local InputDialog = require("ui/widget/inputdialog")
        local original_new = InputDialog.new
        InputDialog.new = function(class, spec, ...)
            local T = require("ffi/util").template
            spec.description = "   " .. require("common/date_format").formatISODate(annotation.datetime)
                .. " · " .. T(_("Page %1"), annotation.mandatory or self:getBookmarkPageString(annotation.page))
            spec.add_scroll_buttons = false
            spec.use_available_height = false
            local Screen = require("device").screen
            spec.text_height = math.floor(math.min(Screen:getWidth(), Screen:getHeight()) * 0.25)
            local close = spec.buttons[1][1].callback
            spec.buttons = {{ spec.buttons[1][3] }}
            local dialog = original_new(class, spec, ...)
            local excess = dialog.dialog_frame:getSize().h + Screen:scaleBySize(40)
                - (Screen:getHeight() - dialog._input_widget:getKeyboardDimen().h)
            if excess > 0 then
                dialog.orig_text_height = math.max(dialog._input_widget:getLineHeight(), dialog.text_height - excess)
                dialog:reinit()
            end
            local function close_dialog()
                close()
                return true
            end
            dialog.onCloseDialog = close_dialog
            require("common/ui/zen_modal_close").installDialog(dialog, close_dialog)
            return dialog
        end
        local ok, result = pcall(orig_setBookmarkNote, self, item_or_index, ...)
        InputDialog.new = original_new
        if not ok then error(result) end
        return result
    end

    for _i, method in ipairs({ "clear", "onClose", "onCloseDocument", "onSetDimensions", "onSuspend" }) do
        local original = ReaderHighlight[method]
        ReaderHighlight[method] = function(self, ...)
            self._zen_highlight_viewport = nil
            local controller = self._zen_highlight_handles
            if (method == "clear" or method == "onClose") and is_enabled()
                    and (self.hold_pos or self.highlight_dialog or controller) then
                Handles.suppressReaderTaps(self)
            end
            if controller then
                controller:close()
                UIManager:close(controller.dialog)
            end
            if original then return original(self, ...) end
        end
    end
end

return apply
