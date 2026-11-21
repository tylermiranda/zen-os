local Blitbuffer = require("ffi/blitbuffer")
local ButtonFeedback = require("common/ui/button_feedback")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local SolidCircle = require("common/ui/zen_solid_circle")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")

local Screen = Device.screen

local GRAY_SHADES = {
    yellow = "#E8E8E8",
    blue   = "#D0D0D0",
    green  = "#B8B8B8",
    red    = "#9E9E9E",
    orange = "#848484",
}

local GRAY_MONOGRAMS = {
    yellow = "Q",
    blue   = "I",
    green  = "C",
    red    = "R",
    orange = "A",
}

local ColorCircle = InputContainer:extend{
    size = nil,
    color_id = "yellow",
    hex = "#F6DF96",
    label = "",
    description = nil,
    selected = false,
    show_caption = false,
    on_tap = nil,
    on_hold = nil,
}

function ColorCircle:init()
    local size = self.size or Screen:scaleBySize(36)
    self.size = size
    local is_color = Screen.isColorScreen and Screen:isColorScreen()
    local fill_hex = is_color and self.hex or (GRAY_SHADES[self.color_id] or "#CCCCCC")
    local fill = Blitbuffer.colorFromString(fill_hex)
    local border = self.selected and math.max(2, Screen:scaleBySize(2.5)) or math.max(1, Screen:scaleBySize(1))

    local inner
    if not is_color then
        local glyph = GRAY_MONOGRAMS[self.color_id]
            or (type(self.label) == "string" and self.label:match("%a") or "?"):upper()
        local text_col = (self.color_id == "orange") and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK
        inner = CenterContainer:new{
            dimen = Geom:new{ w = size - border * 2, h = size - border * 2 },
            TextWidget:new{
                text = glyph,
                face = Font:getFace("smallinfofont", math.max(12, math.floor(size * 0.42))),
                bold = true,
                fgcolor = text_col,
                padding = 0,
            },
        }
    elseif self.selected then
        inner = CenterContainer:new{
            dimen = Geom:new{ w = size - border * 2, h = size - border * 2 },
            TextWidget:new{
                text = "✓",
                face = Font:getFace("smallinfofont", math.max(12, math.floor(size * 0.42))),
                bold = true,
                fgcolor = Blitbuffer.COLOR_BLACK,
                padding = 0,
            },
        }
    end

    local circle = SolidCircle:new{
        width = size,
        height = size,
        bordersize = border,
        background = fill,
        inner,
    }

    local widget = circle
    if self.show_caption and type(self.label) == "string" and self.label ~= "" then
        local short = self.label:match("^(%S+)") or self.label
        local cap = TextWidget:new{
            text = short,
            face = Font:getFace("xx_smallinfofont", 13),
            bold = self.selected == true,
            max_width = size + Screen:scaleBySize(14),
            padding = 0,
        }
        widget = VerticalGroup:new{
            align = "center",
            circle,
            VerticalSpan:new{ width = Screen:scaleBySize(2) },
            cap,
        }
    end

    self._circle = circle
    self[1] = widget
    local sz = widget:getSize()
    self.dimen = Geom:new{ w = sz.w, h = sz.h }
    self.ges_events = {
        TapCircle = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
        HoldCircle = {
            GestureRange:new{ ges = "hold", range = self.dimen },
        },
    }
end

function ColorCircle:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    if self._circle and self._circle.dimen then
        self._circle.dimen.x = x + math.floor((self.dimen.w - self._circle.dimen.w) / 2)
        self._circle.dimen.y = y
    end
    self[1]:paintTo(bb, x, y)
end

function ColorCircle:onTapCircle()
    if self._circle and self._circle.dimen then
        ButtonFeedback.flash(self._circle.dimen, self._circle.radius)
    end
    if type(self.on_tap) == "function" then
        self.on_tap(self.color_id)
    end
    return true
end

function ColorCircle:onHoldCircle()
    if type(self.on_hold) == "function" then
        self.on_hold(self.color_id)
        return true
    end
    if type(self.description) == "string" and self.description ~= "" then
        UIManager:show(InfoMessage:new{
            text = (self.label ~= "" and (self.label .. "\n\n") or "") .. self.description,
            timeout = 4,
        })
    end
    return true
end

local M = {}

M.ColorCircle = ColorCircle

function M.buildRow(hl, active_color, on_select, opts)
    opts = opts or {}
    local order = hl.getHighlightColorOrder and hl.getHighlightColorOrder()
        or { "yellow", "blue", "green", "red", "orange" }
    local size = opts.size or Screen:scaleBySize(36)
    local gap = opts.gap or Screen:scaleBySize(10)
    local row = HorizontalGroup:new{ align = "center" }
    for i, color_id in ipairs(order) do
        if i > 1 then
            table.insert(row, HorizontalSpan:new{ width = gap })
        end
        local label = hl.getHighlightColorString and hl:getHighlightColorString(color_id) or color_id
        local hex = hl.getHighlightColorCode and hl:getHighlightColorCode(color_id) or "#F6DF96"
        local desc = hl.getHighlightColorDescription and hl:getHighlightColorDescription(color_id)
        table.insert(row, ColorCircle:new{
            size = size,
            color_id = color_id,
            hex = hex,
            label = label,
            description = desc,
            selected = active_color == color_id,
            show_caption = opts.show_caption ~= false,
            on_tap = on_select,
        })
    end
    local sz = row:getSize()
    return CenterContainer:new{
        not_focusable = true,
        dimen = Geom:new{ w = opts.width or sz.w, h = sz.h },
        row,
    }
end

return M
