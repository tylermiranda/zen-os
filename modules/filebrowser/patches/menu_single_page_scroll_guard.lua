local function apply_menu_single_page_scroll_guard()
    -- Prevents a screen flash when the user swipes (or presses a page-turn key)
    -- on a Menu that has only one page.
    --
    -- Stock behaviour: onNextPage/onPrevPage always resolve to page 1 when
    -- page_num == 1, then call onGotoPage(1) → updateItems() → full repaint,
    -- which produces a visible flash even though nothing changed.
    --
    -- The fix: return immediately (consuming the event) when there is nothing to
    -- scroll.  This covers all entry points:
    --   • touch swipe east/west  (FileManager:onSwipeFM → onNextPage/onPrevPage)
    --   • Menu:onSwipe           (history, collections, other non-FM menus)
    --   • hardware page-turn keys (key_events.NextPage / PrevPage → same methods)
    --   • chevron buttons        (their callbacks call the same methods, though
    --                             they are disabled by updatePageInfo when nb==1)
    local Menu = require("ui/widget/menu")
    if Menu._zen_single_page_guard_patched then return end
    Menu._zen_single_page_guard_patched = true

    local orig_next = Menu.onNextPage
    local orig_prev = Menu.onPrevPage

    local zen_plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local function loop_pages_enabled()
        local features = zen_plugin and zen_plugin.config and zen_plugin.config.features
        return type(features) ~= "table" or features.loop_pages ~= false
    end

    Menu.onNextPage = function(self)
        local total = self.page_num or 1
        if total <= 1 then return true end
        if loop_pages_enabled() and (self.page or 1) >= total and type(self.onGotoPage) == "function" then
            return self:onGotoPage(1)
        end
        return orig_next(self)
    end

    Menu.onPrevPage = function(self)
        local total = self.page_num or 1
        if total <= 1 then return true end
        if loop_pages_enabled() and (self.page or 1) <= 1 and type(self.onGotoPage) == "function" then
            return self:onGotoPage(total)
        end
        return orig_prev(self)
    end

    -- Guard FileChooser item taps for 1s after quickstart closes.
    local ok_fc, FileChooser = pcall(require, "ui/widget/filechooser")
    if ok_fc and not FileChooser._zen_tap_cooldown_patched then
        FileChooser._zen_tap_cooldown_patched = true
        local orig_select = FileChooser.onMenuSelect
        FileChooser.onMenuSelect = function(fc_self, item)
            if _G.__ZEN_QUICKSTART_JUST_CLOSED then return true end
            return orig_select and orig_select(fc_self, item)
        end
    end
end

return apply_menu_single_page_scroll_guard
