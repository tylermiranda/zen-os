local applied = false

local function apply_kobo_bluetooth_fix()
    if applied then return end

    local Device = require("device")
    if not (Device.isKobo and Device:isKobo()) then return end

    local UIManager = require("ui/uimanager")
    local logger = require("common/zen_logger").new("kobo_bluetooth_fix")

    -- Track whether Bluetooth was turned on at any point during this KOReader session
    -- across all Kobo models (not only MTK) so Exit can safely ask to reboot.
    local ok_bt, kobo_bt = pcall(require, "modules/menu/bluetooth/kobo_bluetooth")
    if ok_bt and type(kobo_bt) == "table" and type(kobo_bt.setEnabled) == "function"
            and not kobo_bt._zen_bt_session_tracked then
        kobo_bt._zen_bt_session_tracked = true
        local orig_setEnabled = kobo_bt.setEnabled
        kobo_bt.setEnabled = function(enabled, ...)
            if enabled then
                _G.__ZEN_BT_USED_THIS_SESSION = true
            end
            return orig_setEnabled(enabled, ...)
        end
        if type(kobo_bt.isEnabled) == "function" then
            local ok_en, is_on = pcall(kobo_bt.isEnabled)
            if ok_en and is_on then
                _G.__ZEN_BT_USED_THIS_SESSION = true
            end
        end
    end

    -- MTK Bluetooth use can make Nickel restart panic, even with the radio off (#12739).
    if Device.isMTK and Device:isMTK() then
        local orig_quit = UIManager.quit
        UIManager.quit = function(self, exit_code, ...)
            if exit_code ~= false and (exit_code or self._exit_code or 0) == 0
                    and not self._entered_poweroff_stage
                    and ok_bt and kobo_bt and kobo_bt.needsRebootOnExit() then
                logger.info("Rebooting after MTK Bluetooth use for safe Nickel startup")
                return self.reboot_action()
            end
            return orig_quit(self, exit_code, ...)
        end
    end
    applied = true
end

return apply_kobo_bluetooth_fix
