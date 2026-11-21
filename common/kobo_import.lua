local DocSettings = require("docsettings")
local InfoMessage = require("ui/widget/infomessage")
local SQ3 = require("lua-ljsqlite3/init")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local M = {}

local KOBO_DB_PATH = "/mnt/onboard/.kobo/KoboReader.sqlite"

local function normalize_volume_path(vol)
    if type(vol) ~= "string" or vol == "" then return nil end
    local p = vol:gsub("^file://", "")
    if lfs.attributes(p, "mode") == "file" then return p end
    local onboard = "/mnt/onboard/" .. p:gsub("^/+", "")
    if lfs.attributes(onboard, "mode") == "file" then return onboard end
end

local function normalize_date(iso)
    if type(iso) ~= "string" or iso == "" then return os.date("%Y-%m-%d %H:%M:%S") end
    local y, mo, d, h, mi, s = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)[T ](%d%d):(%d%d):(%d%d)")
    if y then
        return string.format("%s-%s-%s %s:%s:%s", y, mo, d, h, mi, s)
    end
    return iso
end

function M.importAll()
    if lfs.attributes(KOBO_DB_PATH, "mode") ~= "file" then
        UIManager:show(InfoMessage:new{
            text = _("KoboReader.sqlite not found at /mnt/onboard/.kobo/."),
            timeout = 4,
        })
        return
    end

    local ok, conn = pcall(SQ3.open, KOBO_DB_PATH, "ro")
    if not ok or not conn then
        UIManager:show(InfoMessage:new{
            text = _("Could not open KoboReader.sqlite."),
            timeout = 4,
        })
        return
    end

    local by_book = {}
    local total_rows = 0
    local q_ok = pcall(function()
        for row in conn:rows(
            "SELECT VolumeID, ContentID, Text, Annotation, DateCreated, ChapterProgress, Type "
            .. "FROM Bookmark WHERE (Hidden = 0 OR Hidden IS NULL)"
        ) do
            total_rows = total_rows + 1
            local book_path = normalize_volume_path(row[1])
            if book_path then
                by_book[book_path] = by_book[book_path] or {}
                by_book[book_path][#by_book[book_path] + 1] = {
                    content_id = row[2],
                    text = type(row[3]) == "string" and row[3]:match("^%s*(.-)%s*$") or nil,
                    note = type(row[4]) == "string" and row[4]:match("^%s*(.-)%s*$") or nil,
                    datetime = normalize_date(row[5]),
                    progress = tonumber(row[6]) or 0,
                    kobo_type = tostring(row[7] or ""),
                }
            end
        end
    end)
    conn:close()

    if not q_ok or total_rows == 0 then
        UIManager:show(InfoMessage:new{
            text = _("No Kobo highlights, notes, or bookmarks found to import."),
            timeout = 4,
        })
        return
    end

    local imported_hl, imported_bm, skipped = 0, 0, 0
    for book_path, items in pairs(by_book) do
        local ds = DocSettings:open(book_path)
        local annotations = ds:readSetting("annotations") or {}
        local seen = {}
        for _i, ann in ipairs(annotations) do
            if type(ann) == "table" then
                if ann.text and ann.text ~= "" then seen["t:" .. ann.text] = true end
                if ann.datetime then seen["d:" .. ann.datetime] = true end
            end
        end
        local changed = false
        for _i, item in ipairs(items) do
            local key = (item.text and item.text ~= "") and ("t:" .. item.text) or ("d:" .. item.datetime)
            if seen[key] then
                skipped = skipped + 1
            else
                seen[key] = true
                local is_hl = item.text and item.text ~= ""
                local entry = {
                    datetime = item.datetime,
                    page = 1,
                    chapter = item.content_id and tostring(item.content_id):match("([^/#]+)$") or "",
                    note = (item.note and item.note ~= "") and item.note or nil,
                }
                if is_hl then
                    entry.text = item.text
                    entry.drawer = "lighten"
                    entry.color = "yellow"
                    imported_hl = imported_hl + 1
                else
                    entry.text = entry.note or _("Kobo bookmark")
                    imported_bm = imported_bm + 1
                end
                annotations[#annotations + 1] = entry
                changed = true
            end
        end
        if changed then
            ds:saveSetting("annotations", annotations)
            ds:flush()
        end
        ds:close()
    end

    UIManager:show(InfoMessage:new{
        text = string.format(
            _("Kobo import complete:\n• %d highlights/notes\n• %d bookmarks\n• %d skipped (already present)"),
            imported_hl, imported_bm, skipped
        ),
        timeout = 5,
    })
end

return M
