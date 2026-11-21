local DEFAULT_COLOR_ORDER = { "yellow", "blue", "green", "red", "orange" }

local DEFAULT_COLOR_NAMES = {
    yellow = "Quotes",
    blue   = "Core Ideas",
    green  = "Context",
    red    = "Reactions",
    orange = "Action",
}

local DEFAULT_COLOR_CODES = {
    yellow = "#F6DF96",
    blue   = "#B8D8F8",
    green  = "#BCE5C8",
    red    = "#DFC5F2",
    orange = "#FAD0B4",
}

local DEFAULT_COLOR_DESCRIPTIONS = {
    yellow = "Great writing, memorable lines, or favourite passages.",
    blue   = "Key story turning points in fiction, or main arguments in non-fiction.",
    green  = "Lore, character backgrounds, historical dates, or definitions.",
    red    = "Scenes that surprised you, made you laugh, or hit hard emotionally.",
    orange = "Questions to research, unfamiliar words, or practical advice to apply.",
}

local function get_lookup(ReaderHighlight)
    local plugin = rawget(ReaderHighlight, "_zen_ui_highlight_names_plugin")
    local lookup = plugin and plugin.config and plugin.config.highlight_lookup
    return type(lookup) == "table" and lookup or nil
end

local function configured_name(ReaderHighlight, color_name)
    local lookup = get_lookup(ReaderHighlight)
    local names = lookup and lookup.color_names
    local name = type(names) == "table" and names[color_name]
    if type(name) == "string" and name:match("%S") then return name end
    return DEFAULT_COLOR_NAMES[color_name]
end

local function configured_color(ReaderHighlight, color_name)
    local lookup = get_lookup(ReaderHighlight)
    local colors = lookup and lookup.color_codes
    local color = type(colors) == "table" and colors[color_name]
    if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then return color end
    return DEFAULT_COLOR_CODES[color_name]
end

local function configured_description(ReaderHighlight, color_name)
    local lookup = get_lookup(ReaderHighlight)
    local descs = lookup and lookup.color_descriptions
    local desc = type(descs) == "table" and descs[color_name]
    if type(desc) == "string" and desc:match("%S") then return desc end
    return DEFAULT_COLOR_DESCRIPTIONS[color_name]
end

local function configured_order(ReaderHighlight)
    local lookup = get_lookup(ReaderHighlight)
    local order = lookup and lookup.color_order
    if type(order) == "table" and #order > 0 then return order end
    return DEFAULT_COLOR_ORDER
end

local function invert_color(color)
    local r, g, b = color:match("^#(%x%x)(%x%x)(%x%x)$")
    return string.format("#%02x%02x%02x",
        255 - tonumber(r, 16), 255 - tonumber(g, 16), 255 - tonumber(b, 16))
end

local function is_night_mode()
    local Device = require("device")
    return Device.screen and Device.screen.night_mode == true
end

local function apply(plugin)
    local ReaderHighlight = require("apps/reader/modules/readerhighlight")
    ReaderHighlight._zen_ui_highlight_names_plugin =
        plugin or rawget(_G, "__ZEN_UI_PLUGIN")

    local original_names = rawget(ReaderHighlight, "_zen_ui_highlight_original_names")
    if type(original_names) ~= "table" then
        original_names = {}
        ReaderHighlight._zen_ui_highlight_original_names = original_names
    end

    local Blitbuffer = require("ffi/blitbuffer")
    local original_colors = rawget(ReaderHighlight, "_zen_ui_highlight_original_colors")
    if type(original_colors) ~= "table" then
        original_colors = {}
        ReaderHighlight._zen_ui_highlight_original_colors = original_colors
    end

    for _i, color in ipairs(ReaderHighlight.highlight_colors or {}) do
        local color_name = color[2]
        if original_names[color_name] == nil then original_names[color_name] = color[1] end
        color[1] = configured_name(ReaderHighlight, color_name) or original_names[color_name]
        if original_colors[color_name] == nil then
            original_colors[color_name] = Blitbuffer.HIGHLIGHT_COLORS[color_name] or false
        end
        Blitbuffer.HIGHLIGHT_COLORS[color_name] = configured_color(ReaderHighlight, color_name)
            or original_colors[color_name] or nil
    end

    if ReaderHighlight._zen_ui_highlight_names_patched then return end
    ReaderHighlight._zen_ui_highlight_names_patched = true

    function ReaderHighlight:getHighlightColorDescription(color_name)
        return configured_description(ReaderHighlight, color_name)
    end

    function ReaderHighlight.getHighlightColorOrder()
        return configured_order(ReaderHighlight)
    end

    local orig_get_string = ReaderHighlight.getHighlightColorString
    if type(orig_get_string) == "function" then
        ReaderHighlight.getHighlightColorString = function(self, color_name, force_orig, ...)
            if force_orig and original_names[color_name] then
                return original_names[color_name]
            end
            if not force_orig then
                local name = configured_name(ReaderHighlight, color_name)
                if name then return name end
            end
            return orig_get_string(self, color_name, force_orig, ...)
        end
    end

    local orig_get_list = ReaderHighlight.getHighlightColorList
    local orig_get_code = ReaderHighlight.getHighlightColorCode
    if type(orig_get_code) == "function" then
        ReaderHighlight.getHighlightColorCode = function(self, color_name, force_orig, honor_night_mode, ...)
            local color = not force_orig and configured_color(ReaderHighlight, color_name)
            if color then
                return honor_night_mode and is_night_mode() and invert_color(color) or color
            end
            return orig_get_code(self, color_name, force_orig, honor_night_mode, ...)
        end
    end

    local orig_get_color = ReaderHighlight.getHighlightColor
    if type(orig_get_color) == "function" then
        ReaderHighlight.getHighlightColor = function(self, color_name, force_orig, honor_night_mode, ...)
            local color = not force_orig and configured_color(ReaderHighlight, color_name)
            if color then
                if is_night_mode() and (honor_night_mode or not orig_get_code) then
                    color = invert_color(color)
                end
                return Blitbuffer.colorFromString(color)
            end
            return orig_get_color(self, color_name, force_orig, honor_night_mode, ...)
        end
    end

    if type(orig_get_list) == "function" then
        ReaderHighlight.getHighlightColorList = function(self, ...)
            local colors = orig_get_list(self, ...)
            for _i, color in ipairs(colors or {}) do
                if type(color) == "table" then
                    color[1] = configured_name(ReaderHighlight, color[2]) or color[1]
                    if configured_color(ReaderHighlight, color[2])
                        and type(self.getHighlightColor) == "function" then
                        color[3] = self:getHighlightColor(color[2], false, true)
                    end
                end
            end
            return colors
        end
    end
end

return apply
