-- modules/global/patches/bento_lockscreen.lua
-- Renders the Bento Home Dashboard (Page 1) as the full-screen sleep/lock screen.

local Blitbuffer = require("ffi/blitbuffer")
local ConfigManager = require("config/manager")
local Device = require("device")
local UIManager = require("ui/uimanager")
local ffiUtil = require("ffi/util")
local logger = require("logger")

local Screen = Device.screen

local function is_bento_lockscreen_enabled()
    local plugin = rawget(_G, "__ZEN_UI_PLUGIN")
    local cfg = plugin and type(plugin.config) == "table" and plugin.config or nil
    if type(cfg) ~= "table" then
        local ok, loaded = pcall(ConfigManager.load)
        if ok and type(loaded) == "table" then
            cfg = loaded
        end
    end
    local features = type(cfg) == "table" and cfg.features or nil
    if type(features) == "table" and features.bento_home == false then
        return false
    end
    return not (type(features) == "table" and features.bento_lockscreen == false)
end

local function wrap_ri_instance(inst)
    if type(inst) ~= "table" then return end
    local target = getmetatable(inst) and getmetatable(inst).__index or inst
    if type(target) ~= "table" or target._zen_bento_ri_patched then return end
    if type(target._screensaverShouldShow) ~= "function" then return end
    target._zen_bento_ri_patched = true
    local orig = target._screensaverShouldShow
    target._screensaverShouldShow = function(self, ...)
        if is_bento_lockscreen_enabled() then
            return false
        end
        return orig(self, ...)
    end
end

local function patch_reading_insights()
    local rui_mod = package.loaded["apps/reader/readerui"]
    if rui_mod and rui_mod.instance then
        wrap_ri_instance(rui_mod.instance.readinginsights)
    end
    local fm_mod = package.loaded["apps/filemanager/filemanager"]
    if fm_mod and fm_mod.instance then
        wrap_ri_instance(fm_mod.instance.readinginsights)
    end
    local ok_pl, PluginLoader = pcall(require, "pluginloader")
    if ok_pl and PluginLoader and type(PluginLoader.loaded_plugins) == "table" then
        wrap_ri_instance(PluginLoader.loaded_plugins.readinginsights)
    end
end

local function install_screensaver_patch()
    local Screensaver = require("ui/screensaver")
    if Screensaver._zen_bento_lockscreen_patched then return end
    Screensaver._zen_bento_lockscreen_patched = true

    local orig_setup = Screensaver.setup
    Screensaver.setup = function(self, event, event_message)
        patch_reading_insights()
        orig_setup(self, event, event_message)
        if event == nil and is_bento_lockscreen_enabled() then
            self.ui = self.ui
                or (package.loaded["apps/reader/readerui"] and package.loaded["apps/reader/readerui"].instance)
                or (package.loaded["apps/filemanager/filemanager"] and package.loaded["apps/filemanager/filemanager"].instance)
            self.screensaver_type = "zen_bento_home"
            self.screensaver_background = "white"
            self.show_message = false
            self.overlay_message = nil
            Device.screen_saver_mode = true
        end
    end

    local orig_expects_portrait = Screensaver.modeExpectsPortrait
    Screensaver.modeExpectsPortrait = function(self, ...)
        if self.screensaver_type == "zen_bento_home" then
            return false
        end
        return orig_expects_portrait(self, ...)
    end

    local orig_is_image = Screensaver.modeIsImage
    Screensaver.modeIsImage = function(self, ...)
        if self.screensaver_type == "zen_bento_home" then
            return true
        end
        return orig_is_image(self, ...)
    end

    local orig_show = Screensaver.show
    Screensaver.show = function(self, ...)
        if self.screensaver_type ~= "zen_bento_home" then
            return orig_show(self, ...)
        end

        local ok_hp, HomePage = pcall(require, "modules/filebrowser/patches/home_page")
        local ok_w, bento_widget
        if ok_hp and HomePage and type(HomePage.buildLockScreenWidget) == "function" then
            ok_w, bento_widget = pcall(HomePage.buildLockScreenWidget)
        end
        if not (ok_w and bento_widget) then
            logger.warn("Bento lock screen build failed, falling back:", tostring(bento_widget))
            return orig_show(self, ...)
        end

        local screen_w, screen_h = Screen:getWidth(), Screen:getHeight()
        if Device:hasEinkScreen() then
            Screen:clear()
            Screen:refreshFull(0, 0, screen_w, screen_h)
            if Device.isKobo and Device:isKobo() and Device.isSunxi and Device:isSunxi() then
                ffiUtil.usleep(150 * 1000)
            end
        end

        UIManager:setIgnoreTouchInput(false)
        local ScreenSaverWidget = require("ui/widget/screensaverwidget")
        self.screensaver_widget = ScreenSaverWidget:new{
            widget = bento_widget,
            background = Blitbuffer.COLOR_WHITE,
            covers_fullscreen = true,
        }
        self.screensaver_widget.modal = true
        self.screensaver_widget.dithered = true
        UIManager:show(self.screensaver_widget, "full")

        if G_reader_settings:readSetting("screensaver_delay") == "gesture" then
            local ScreenSaverLockWidget = require("ui/widget/screensaverlockwidget")
            self.screensaver_lock_widget = ScreenSaverLockWidget:new{
                ui = self.ui,
            }
            UIManager:show(self.screensaver_lock_widget)
        end
    end
end

return function()
    patch_reading_insights()
    if package.loaded["ui/screensaver"] then
        install_screensaver_patch()
    else
        require("common/on_require").whenLoaded("ui/screensaver", install_screensaver_patch)
    end
end
