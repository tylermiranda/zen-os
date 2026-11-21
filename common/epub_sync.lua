local M = {}

local SERVER_URL = "http://192.168.1.5:8798"

local function getUIManager()
    local ok, ui_mgr = pcall(require, "ui/uimanager")
    if ok and ui_mgr then return ui_mgr end
    return rawget(_G, "UIManager")
end

local function getLogger()
    local ok, l = pcall(require, "logger")
    if ok and l then return l end
    return rawget(_G, "logger")
end

local function showInfo(text, timeout)
    local UIManager = getUIManager()
    if not UIManager then return end
    local ok_im, InfoMessage = pcall(require, "ui/widget/infomessage")
    if ok_im and InfoMessage then
        UIManager:show(InfoMessage:new{
            text = text,
            timeout = timeout or 2,
        })
    end
end

function M.checkAndUploadEpub(file, md5)
    if not file or not file:lower():match("%.epub$") then return end
    if not md5 or md5 == "" then return end

    local logger = getLogger()
    local UIManager = getUIManager()

    -- Check if network is connected
    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_net and NetworkMgr and not NetworkMgr:isConnected() then
        return
    end

    local check_url = SERVER_URL .. "/api/books/" .. md5 .. "/check"
    local upload_url = SERVER_URL .. "/api/books/upload?md5=" .. md5

    local function doUpload()
        pcall(function()
            local http = require("socket.http")
            local ltn12 = require("ltn12")

            http.TIMEOUT = 10
            local check_sink = {}
            local res, code = http.request({
                url = check_url,
                method = "GET",
                sink = ltn12.sink.table(check_sink),
            })

            local exists = (code == 200)

            if not exists then
                if logger and logger.info then
                    logger.info("[ZenOS EPUB Sync] Book missing on server, uploading:", file, md5)
                end
                local f = io.open(file, "rb")
                if f then
                    local size = f:seek("end")
                    f:seek("set", 0)

                    local up_sink = {}
                    http.TIMEOUT = math.max(30, math.floor(size / (50 * 1024)))

                    local up_res, up_code = http.request({
                        url = upload_url,
                        method = "POST",
                        headers = {
                            ["Content-Type"] = "application/epub+zip",
                            ["Content-Length"] = tostring(size),
                            ["X-Book-MD5"] = md5,
                        },
                        source = ltn12.source.file(f),
                        sink = ltn12.sink.table(up_sink),
                    })
                    http.TIMEOUT = 10

                    if up_code == 200 then
                        if logger and logger.info then
                            logger.info("[ZenOS EPUB Sync] Successfully uploaded EPUB:", md5)
                        end
                    end
                end
            end
        end)
    end

    if UIManager and UIManager.scheduleIn then
        UIManager:scheduleIn(2, doUpload)
    else
        doUpload()
    end
end

local function getBookInfo(reader_ui)
    if not reader_ui then return nil end

    local file = reader_ui.document and reader_ui.document.file
    local doc_settings = reader_ui.doc_settings
    local md5 = doc_settings and type(doc_settings.readSetting) == "function"
        and doc_settings:readSetting("partial_md5_checksum")
    if not md5 and file then
        local util = require("util")
        md5 = util.partialMD5(file)
    end
    if not md5 then return nil end

    local cur_page = (reader_ui.getCurrentPage and reader_ui:getCurrentPage())
        or (reader_ui.view and reader_ui.view.state and reader_ui.view.state.page)
        or 1

    local total_pages = (reader_ui.document and reader_ui.document.getPageCount and reader_ui.document:getPageCount())
        or (doc_settings and type(doc_settings.readSetting) == "function" and doc_settings:readSetting("doc_pages"))
        or (reader_ui.document and reader_ui.document.info and reader_ui.document.info.pages)
        or 1

    local live_percent = nil
    if reader_ui.rolling and reader_ui.rolling.getLastPercent then
        local ok_p, val = pcall(reader_ui.rolling.getLastPercent, reader_ui.rolling)
        if ok_p and type(val) == "number" and val == val and val >= 0 and val <= 1 then
            live_percent = val
        end
    elseif reader_ui.paging and reader_ui.paging.getLastPercent then
        local ok_p, val = pcall(reader_ui.paging.getLastPercent, reader_ui.paging)
        if ok_p and type(val) == "number" and val == val and val >= 0 and val <= 1 then
            live_percent = val
        end
    end

    local cur_percent = live_percent
        or (total_pages > 1 and (cur_page / total_pages))
        or (doc_settings and type(doc_settings.readSetting) == "function" and doc_settings:readSetting("percent_finished"))
        or ((total_pages > 0) and (cur_page / total_pages))
        or 0

    if cur_percent > 1.0 and total_pages > 1 then
        cur_percent = cur_page / total_pages
    end
    if cur_percent > 1.0 then cur_percent = 1.0 end
    if cur_percent < 0.0 then cur_percent = 0.0 end

    return {
        file = file,
        md5 = md5,
        cur_page = cur_page,
        total_pages = total_pages,
        cur_percent = cur_percent,
    }
end

function M.pushProgress(reader_ui, interactive, force)
    local info = getBookInfo(reader_ui)
    if not info or not info.md5 then return end

    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_net and NetworkMgr and not NetworkMgr:isConnected() then
        return
    end

    local UIManager = getUIManager()

    local function doPush()
        pcall(function()
            local http = require("socket.http")
            local ltn12 = require("ltn12")
            local json = require("json")

            http.TIMEOUT = 8
            local payload = json.encode({
                document = info.md5,
                progress = tostring(info.cur_page),
                percentage = info.cur_percent,
                device = "Kobo Libra H2O (ZenOS)",
                device_id = "kobo-zenos",
                timestamp = os.time(),
                force = force == true or nil,
            })

            local push_url = SERVER_URL .. (force == true and "/syncs/progress?force=true" or "/syncs/progress")
            local res, code = http.request({
                url = push_url,
                method = "PUT",
                headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = tostring(#payload),
                },
                source = ltn12.source.string(payload),
                sink = ltn12.sink.table({}),
            })

            if interactive then
                if force == true then
                    showInfo(string.format("Saved Page %d (%.1f%%) as furthest ✓", info.cur_page, info.cur_percent * 100), 2)
                else
                    showInfo(string.format("Reading progress in sync ✓ (Page %d / %.1f%%)", info.cur_page, info.cur_percent * 100), 2)
                end
            end
        end)
    end

    if interactive then
        doPush()
    elseif UIManager and UIManager.scheduleIn then
        UIManager:scheduleIn(1, doPush)
    else
        doPush()
    end
end

function M.syncProgress(reader_ui, interactive)
    if not reader_ui then return end

    local logger = getLogger()
    local UIManager = getUIManager()

    local ok_net, NetworkMgr = pcall(require, "ui/network/manager")
    if ok_net and NetworkMgr and not NetworkMgr:isConnected() then
        if interactive then
            showInfo("Wi-Fi not connected. Please turn on Wi-Fi to sync.", 3)
        end
        return
    end

    if interactive then
        showInfo("Syncing with Bookworm...", 1)
    end

    local function doSync()
        local ok_call, err = pcall(function()
            local info = getBookInfo(reader_ui)
            if not info or not info.md5 then
                if logger and logger.warn then
                    logger.warn("[ZenOS EPUB Sync] No book info/md5 found for sync")
                end
                return
            end

            local http = require("socket.http")
            local ltn12 = require("ltn12")
            local json = require("json")

            http.TIMEOUT = 8

            -- 1. Pull furthest read position from server
            local get_sink = {}
            local res, code = http.request({
                url = SERVER_URL .. "/syncs/progress/" .. info.md5,
                method = "GET",
                sink = ltn12.sink.table(get_sink),
            })

            local remote = nil
            if code == 200 then
                local body_str = table.concat(get_sink)
                local ok_j, parsed = pcall(json.decode, body_str)
                if ok_j and parsed and parsed.percentage then
                    remote = parsed
                end
            end

            local remote_percent = remote and tonumber(remote.percentage) or nil
            local cur_percent = info.cur_percent or 0
            local total_pages = info.total_pages or 449
            local cur_page = info.cur_page or 1

            if logger and logger.info then
                logger.info(string.format("[ZenOS EPUB Sync] Pull result: code=%s remote_pct=%s cur_pct=%s cur_page=%d total_pages=%d",
                    tostring(code), tostring(remote_percent), tostring(cur_percent), cur_page, total_pages))
            end

            -- 2. If remote location is ahead (by more than 0.5%), prompt the user (Whispersync)
            if remote_percent and (remote_percent > (cur_percent + 0.005)) then
                local remote_page = math.max(1, math.min(total_pages, math.floor(remote_percent * total_pages + 0.5)))
                if logger and logger.info then
                    logger.info(string.format("[ZenOS EPUB Sync] Prompting jump to page %d (%.1f%%) from %s",
                        remote_page, remote_percent * 100, remote.device or "phone reader"))
                end

                local ButtonDialog = require("ui/widget/buttondialog")
                local dlg
                dlg = ButtonDialog:new{
                    title = string.format(
                        "You are on page %d (%.1f%%).\nFurthest synced on %s is page %d (%.1f%%).",
                        cur_page, cur_percent * 100, remote.device or "phone reader", remote_page, remote_percent * 100
                    ),
                    buttons = {
                        {
                            {
                                text = string.format("Jump to Page %d (%.1f%%)", remote_page, remote_percent * 100),
                                callback = function()
                                    UIManager:close(dlg)
                                    if reader_ui.link and reader_ui.link.addCurrentLocationToStack then
                                        reader_ui.link:addCurrentLocationToStack()
                                    end
                                    local Event = require("ui/event")
                                    reader_ui:handleEvent(Event:new("GotoPage", remote_page))
                                    if interactive then
                                        showInfo(string.format("Jumped to Page %d (%.1f%%)", remote_page, remote_percent * 100), 2)
                                    end
                                end,
                            },
                        },
                        {
                            {
                                text = string.format("Use Page %d as Furthest (Overwrite)", cur_page),
                                callback = function()
                                    UIManager:close(dlg)
                                    M.pushProgress(reader_ui, true, true)
                                end,
                            },
                        },
                        {
                            {
                                text = string.format("Stay on Page %d for Now", cur_page),
                                callback = function()
                                    UIManager:close(dlg)
                                end,
                            },
                        },
                    },
                }
                UIManager:show(dlg)
            elseif remote_percent and (cur_percent > (remote_percent + 0.005)) then
                -- 3. If local position is ahead of server, push local progress to server
                M.pushProgress(reader_ui, interactive)
            else
                -- 4. In sync
                if not remote then
                    M.pushProgress(reader_ui, interactive)
                elseif interactive then
                    showInfo(string.format("Reading progress in sync ✓ (Page %d / %.1f%%)", cur_page, cur_percent * 100), 2)
                end
            end
        end)

        if not ok_call and logger and logger.warn then
            logger.warn("[ZenOS EPUB Sync] Error in doSync:", tostring(err))
        end
    end

    if interactive then
        doSync()
    elseif UIManager and UIManager.scheduleIn then
        -- Deferred 2 seconds so first page paints before dialog
        UIManager:scheduleIn(2, doSync)
    else
        doSync()
    end
end

return M
