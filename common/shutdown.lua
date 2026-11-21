local logger = require("common/zen_logger").new("shutdown")
local SharedState = require("common/shared_state")

local M = {}

function M.closeStandaloneViews(plugin)
    if type(plugin) ~= "table" then return end
    for _i, key in ipairs({ "group_view", "home", "stats" }) do
        local view = SharedState.get(plugin, key)
        if view and type(view.closeAll) == "function" then
            local ok, err = pcall(view.closeAll, true)
            if not ok then
                logger.warn("failed to close standalone view before shutdown", key, err)
            end
        end
    end
end

local function bluetooth_used_this_session()
    if rawget(_G, "__ZEN_BT_USED_THIS_SESSION") == true then return true end
    local ok_bt, kobo_bt = pcall(require, "modules/menu/bluetooth/kobo_bluetooth")
    if ok_bt and type(kobo_bt) == "table" and type(kobo_bt.needsRebootOnExit) == "function" then
        local ok, needs = pcall(kobo_bt.needsRebootOnExit)
        if ok and needs == true then return true end
    end
    return false
end

function M.broadcastExit(plugin)
    if bluetooth_used_this_session() then
        local ConfirmBox = require("ui/widget/confirmbox")
        local UIManager = require("ui/uimanager")
        local Event = require("ui/event")
        local _ = require("gettext")
        UIManager:show(ConfirmBox:new{
            text = _("Bluetooth was used during this session. Returning directly to the Kobo UI can crash Nickel.\n\nReboot instead?"),
            ok_text = _("Reboot"),
            cancel_text = _("Exit anyway"),
            ok_callback = function()
                M.closeStandaloneViews(plugin)
                if type(UIManager.reboot_action) == "function" then
                    UIManager:reboot_action()
                else
                    UIManager:broadcastEvent(Event:new("Reboot"))
                end
            end,
            cancel_callback = function()
                M.closeStandaloneViews(plugin)
                UIManager:broadcastEvent(Event:new("Exit"))
            end,
        })
        return
    end
    M.closeStandaloneViews(plugin)
    require("ui/uimanager"):broadcastEvent(require("ui/event"):new("Exit"))
end

return M
