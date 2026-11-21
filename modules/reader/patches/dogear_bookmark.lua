-- ZenOS: Bigger green folded-corner bookmark indicator (ReaderDogear)

local function apply_dogear_bookmark()
    local BD = require("ui/bidi")
    local Blitbuffer = require("ffi/blitbuffer")
    local Device = require("device")
    local Geom = require("ui/geometry")
    local ReaderDogear = require("apps/reader/modules/readerdogear")
    local RightContainer = require("ui/widget/container/rightcontainer")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local WidgetContainer = require("ui/widget/container/widgetcontainer")
    local Screen = Device.screen

    if ReaderDogear._zen_dogear_patched then return end
    ReaderDogear._zen_dogear_patched = true

    local _plugin_ref = rawget(_G, "__ZEN_UI_PLUGIN")
    local function is_enabled()
        local features = _plugin_ref and _plugin_ref.config and _plugin_ref.config.features
        return type(features) ~= "table" or features.green_folded_bookmark ~= false
    end

    local FoldedCorner = WidgetContainer:extend{
        size = 48,
        mirrored = false,
    }

    function FoldedCorner:init()
        self.dimen = Geom:new{ w = self.size, h = self.size }
        self._bb = nil
    end

    function FoldedCorner:getSize()
        return self.dimen
    end

    function FoldedCorner:_ensureBuffer()
        if self._bb then return self._bb end
        local sz = self.size
        local is_color = Screen.isColorScreen and Screen:isColorScreen()
        local bb_type = is_color and Blitbuffer.TYPE_BBRGB32 or Blitbuffer.TYPE_BB8
        local bb = Blitbuffer.new(sz, sz, bb_type)
        local bg = is_color and Blitbuffer.colorFromString("#FFFFFF") or Blitbuffer.COLOR_WHITE
        local fill = is_color and Blitbuffer.colorFromString("#3DA662") or Blitbuffer.Color8(0x66)
        local edge = is_color and Blitbuffer.colorFromString("#1D5C34") or Blitbuffer.Color8(0x18)
        local border = math.max(1, math.floor(sz * 0.06))

        for py = 0, sz - 1 do
            for px = 0, sz - 1 do
                local lx = self.mirrored and (sz - 1 - px) or px
                if lx > py then
                    bb:setPixel(px, py, bg)
                elseif (py - lx) <= border or lx < border or py >= (sz - border) then
                    bb:setPixel(px, py, edge)
                else
                    bb:setPixel(px, py, fill)
                end
            end
        end
        self._bb = bb
        return bb
    end

    function FoldedCorner:paintTo(bb, x, y)
        self.dimen.x = x
        self.dimen.y = y
        local corner_bb = self:_ensureBuffer()
        bb:blitFrom(corner_bb, x, y, 0, 0, self.size, self.size)
    end

    function FoldedCorner:free()
        if self._bb then
            self._bb:free()
            self._bb = nil
        end
    end

    local orig_init = ReaderDogear.init
    ReaderDogear.init = function(self, ...)
        orig_init(self, ...)
        if not is_enabled() then return end
        local min_dim = math.min(Screen:getWidth(), Screen:getHeight())
        self.dogear_min_size = math.ceil(min_dim * (1 / 22))
        self.dogear_max_size = math.ceil(min_dim * (1 / 16))
        self.dogear_size = nil
        self:setupDogear(self.dogear_max_size)
        self:resetLayout()
    end

    local orig_setup = ReaderDogear.setupDogear
    ReaderDogear.setupDogear = function(self, new_dogear_size, ...)
        if not is_enabled() then
            return orig_setup(self, new_dogear_size, ...)
        end
        if not new_dogear_size then
            new_dogear_size = self.dogear_max_size
        end
        if new_dogear_size ~= self.dogear_size then
            self.dogear_size = new_dogear_size
            if self[1] then
                self[1]:free()
            end
            self.icon = FoldedCorner:new{
                size = self.dogear_size,
                mirrored = BD.mirroredUILayout(),
            }
            self.top_pad = VerticalSpan:new{ width = self.dogear_y_offset }
            self.vgroup = VerticalGroup:new{
                self.top_pad,
                self.icon,
            }
            self[1] = RightContainer:new{
                dimen = Geom:new{ w = Screen:getWidth(), h = self.dogear_y_offset + self.dogear_size },
                self.vgroup,
            }
        end
    end
end

return apply_dogear_bookmark
