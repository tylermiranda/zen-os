local Blitbuffer = require("ffi/blitbuffer")
local Accent = require("common/ui/accent")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local IconWidget = require("ui/widget/iconwidget")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local ButtonLabelWidth = require("common/ui/button_label_width")
local ButtonFeedback = require("common/ui/button_feedback")
local utils = require("common/utils")
local Screen = Device.screen
local root = require("common/plugin_root")
local function icon_spec(name)
    name = type(name) == "string" and name ~= "" and name or "app_launcher"
    if type(name) == "string" and name:sub(1, 1) == "/" then return name end
    local path = root and utils.resolveIcon(root .. "/icons/", name)
    return path, name
end

local LauncherCell = InputContainer:extend{}

function LauncherCell:init()
    self.dimen = self.dimen or Geom:new{ w = self.width, h = self.height }
    self.ges_events = {
        TapSelect = {
            GestureRange:new{ ges = "tap", range = self.dimen },
        },
    }
end

function LauncherCell:paintTo(bb, x, y)
    self.dimen.x = x
    self.dimen.y = y
    self[1]:paintTo(bb, x, y)
end

function LauncherCell:onTapSelect()
    if self.callback then
        self.callback()
    end
    return true
end

function LauncherCell:onFocus()
    self.frame.invert = true
    if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
    return true
end

function LauncherCell:onUnfocus()
    self.frame.invert = false
    if self.dimen then UIManager:setDirty(nil, "fast", self.dimen) end
    return true
end

local function make_cell(opts)
    local icon_path, icon_name = icon_spec(opts.icon)
    local icon_size = opts.icon_size
    local rendered_icon_size = math.floor(
        icon_size * utils.iconOpticalScale(opts.icon, icon_path) + 0.5)
    local circle_size = opts.circle_size
    local circle_border = opts.circle_border
    local active = opts.active == true and not opts.dimmed
    local label_face = opts.label_face
    local fg = opts.dim and Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
    local show_label = opts.show_label ~= false
    local wide_card = (tonumber(opts.span) or 1) >= 2 or opts.card == true
    local icon = IconWidget:new{
        file = icon_path or nil,
        icon = icon_path and nil or icon_name,
        width = rendered_icon_size,
        height = rendered_icon_size,
        alpha = true,
    }
    local border = circle_border
    local icon_circle = FrameContainer:new{
        width = circle_size,
        height = circle_size,
        padding = 0,
        bordersize = border,
        radius = math.floor(circle_size / 2),
        background = opts.dimmed and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_WHITE,
        CenterContainer:new{
            dimen = Geom:new{
                w = circle_size - border * 2,
                h = circle_size - border * 2,
            },
            icon,
        },
    }
    Accent.styleButton(icon_circle, icon, active)
    local frame
    if wide_card then
        local Font = require("ui/font")
        local card_w = math.max(circle_size + Screen:scaleBySize(24), opts.cell_w - Screen:scaleBySize(10))
        local card_h = math.max(circle_size + Screen:scaleBySize(12), opts.cell_h - Screen:scaleBySize(6))
        local card_pad = Screen:scaleBySize(10)
        local text_w = math.max(40, card_w - circle_size - card_pad * 3)
        local label = TextWidget:new{
            text = opts.label,
            face = label_face,
            bold = true,
            fgcolor = fg,
            max_width = text_w,
        }
        local text_col = VerticalGroup:new{ align = "left", label }
        if type(opts.subtitle) == "string" and opts.subtitle ~= "" then
            table.insert(text_col, VerticalSpan:new{ width = Screen:scaleBySize(2) })
            table.insert(text_col, TextWidget:new{
                text = opts.subtitle,
                face = Font:getFace("xx_smallinfofont", 14),
                fgcolor = Blitbuffer.COLOR_DARK_GRAY,
                max_width = text_w,
            })
        end
        local card_row = HorizontalGroup:new{
            align = "center",
            icon_circle,
            HorizontalSpan:new{ width = card_pad },
            text_col,
        }
        local card_box = FrameContainer:new{
            width = card_w,
            height = card_h,
            padding = 0,
            padding_left = card_pad,
            padding_right = card_pad,
            bordersize = border,
            radius = Screen:scaleBySize(14),
            color = active and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_DARK_GRAY,
            background = opts.dimmed and Blitbuffer.COLOR_GRAY or Blitbuffer.COLOR_WHITE,
            CenterContainer:new{
                dimen = Geom:new{ w = card_w - card_pad * 2 - border * 2, h = card_h - border * 2 },
                card_row,
            },
        }
        frame = FrameContainer:new{
            width = opts.cell_w,
            height = opts.cell_h,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
                card_box,
            },
        }
    else
        local content_items = {
            align = "center",
            icon_circle,
        }
        if show_label then
            local label_max_width = ButtonLabelWidth.maxWidth(opts.cell_w, opts.label_side_padding)
            local label = TextWidget:new{
                text = opts.label,
                face = label_face,
                fgcolor = fg,
                max_width = label_max_width,
            }
            table.insert(content_items, 1, VerticalSpan:new{ width = opts.pad })
            content_items[#content_items + 1] = VerticalSpan:new{ width = Screen:scaleBySize(4) }
            content_items[#content_items + 1] = label
        end
        local content = VerticalGroup:new(content_items)
        frame = FrameContainer:new{
            width = opts.cell_w,
            height = opts.cell_h,
            bordersize = 0,
            background = Blitbuffer.COLOR_WHITE,
            padding = 0,
            CenterContainer:new{
                dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
                content,
            },
        }
    end
    local cell = LauncherCell:new{
        width = opts.cell_w,
        height = opts.cell_h,
        dimen = Geom:new{ w = opts.cell_w, h = opts.cell_h },
        callback = opts.callback and function()
            ButtonFeedback.flash(icon_circle.dimen, icon_circle.radius)
            opts.callback()
        end or nil,
        frame = frame,
        frame,
    }
    return cell
end


return make_cell
