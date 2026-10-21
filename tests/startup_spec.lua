-- Run from the repository root: luajit tests/startup_spec.lua
-- Native KOReader services are stubbed; the actual plugin/settings methods run.
package.path = "./?.lua;" .. package.path
local shown, saved, warnings, renderer_options, request
local custom_mtime = 10
local count = 0

local function mock(name, value)
    package.loaded[name] = value
end

local Widget = {}
function Widget:extend(fields)
    return setmetatable(fields or {}, { __index = self })
end
function Widget:new(fields)
    return self:extend(fields)
end
function Widget:getInputText() return self.input end
function Widget:onCloseKeyboard() end
function Widget:onShowKeyboard() end
function Widget:getFields() return self.test_fields or {} end
function Widget:hasEntries() return false end
function Widget:getAll() return {} end

for _, name in ipairs({
    "ui/widget/infomessage", "ui/widget/inputdialog", "ui/widget/menu",
    "ui/widget/buttondialog", "ui/widget/button", "ui/geometry",
    "ui/widget/container/scrollablecontainer", "ui/widget/verticalgroup",
    "ui/widget/horizontalspan", "ui/widget/checkbutton", "ui/widget/multiinputdialog",
    "ui/widget/container/widgetcontainer", "ui/widget/confirmbox",
    "webbrowser_bookmarks", "webbrowser_history", "webbrowser_website_history",
    "webbrowser_markdown_viewer",
}) do mock(name, Widget) end

mock("gettext", function(text) return text end)
mock("dispatcher", { registerAction = function() end })
mock("ffi/blitbuffer", { COLOR_WHITE = 0 })
mock("device", { screen = {} })
mock("util", {})
mock("apps/filemanager/filemanager", {})
mock("apps/filemanager/filemanagerutil", {})
mock("libs/libkoreader-lfs", { attributes = function() return { modification = custom_mtime } end })
mock("logger", { warn = function(...) warnings[#warnings + 1] = {...} end })
mock("socket", {})
mock("socketutil", {})
mock("ltn12", {})
mock("random", {})
mock("webbrowser_http", {})
mock("document/documentregistry", {})
mock("webbrowser_utils", {
    is_loopback_url = function() return false end,
    strip_fragment = function(url) return url:match("^[^#]+") end,
})
mock("datastorage", {
    getSettingsDir = function() return "/test/settings" end,
    getDataDir = function() return "/test" end,
})
mock("luasettings", { open = function()
    return {
        readSetting = function(_, key) return saved[key] end,
        saveSetting = function(_, key, value) saved[key] = value end,
        delSetting = function(_, key) saved[key] = nil end,
        flush = function() end,
    }
end })
mock("ui/uimanager", {
    show = function(_, widget) shown[#shown + 1] = widget end,
    close = function(_, widget) widget.closed = true end,
})
mock("ui/network/manager", { runWhenOnline = function(_, callback) callback() end })
mock("webbrowser_renderer", { new = function(_, options)
    renderer_options = options
    return { fetchAndStore = function(_, url)
        request = url
        return true, "/test/cache/article.html"
    end }
end })
for _, name in ipairs({ "duckduckgo", "brave_api", "google_api", "tavily_api", "exa_api", "kiwix" }) do
    mock("webbrowser_" .. name, { search = function(query, config)
        request = { query = query, config = config, engine = name }
        return { { title = "Test", url = "https://example.com" } }
    end })
end

local function browser(loader)
    package.preload.webbrowser_configuration = loader
    package.loaded.webbrowser_configuration = nil
    shown, warnings, renderer_options, request = {}, {}, nil, nil
    local Browser = dofile("main.lua")
    local instance = Browser:new { ui = {
        menu = { registerToMainMenu = function() end },
        link = { addToExternalLinkDialog = function() end },
    } }
    instance:init()
    return instance
end

local function test(name, check)
    saved = {}
    local ok, err = pcall(check)
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
end

test("fresh install opens the search dialog", function()
    local b = browser()
    b:showSearchDialog()
    assert(b.search_dialog and b.search_dialog.title == "DuckDuckGo Search")
    assert(#shown == 1 and #warnings == 0)
    assert(b:isCreRender() and not b:shouldDownloadImages() and not b:shouldUseStylesheets())
    assert(b.mu_pdf_link_handler_registered)
end)

test("search works with built-in provider settings", function()
    local b = browser()
    b.showResultsMenu = function(_, query, results) assert(query == "books" and #results == 1) end
    b:performSearch("books")
    assert(request.engine == "duckduckgo" and request.config.search_path == "/html/")
    assert(request.config.api_key == nil)
end)

test("direct URL navigation uses CRE without an API", function()
    local b = browser()
    b.recordWebsiteVisit = function() end
    b.openCreDocument = function(_, path) assert(path == "/test/cache/article.html") end
    b:openDirectUrl("example.com")
    assert(request == "https://example.com")
    assert(renderer_options.download_images == false and renderer_options.use_stylesheets == false)
end)

test("settings and language controls work without a config file", function()
    local b = browser()
    b:showEngineSettings()
    assert(shown[#shown].title == "Search Engine: DuckDuckGo")
    b:showEngineSelector()
    assert(#b.engine_selector_dialog.buttons == 1)
    b:showLanguageSettings()
    local dialog = shown[#shown]
    dialog.test_fields = { "en", "au" }
    dialog.buttons[1][2].callback()
    assert(saved.duckduckgo_country == "au" and saved.engine == "duckduckgo")
end)

test("language choices survive a restart without a config file", function()
    local b = browser()
    local config = b:getSearchEngineConfig()
    config.language, config.country = "fr", "ca"
    b:saveSettings("duckduckgo")
    local restarted = browser()
    local restored = restarted:getSearchEngineConfig()
    assert(restored.language == "fr" and restored.country == "ca")
end)

test("reset works without a config file", function()
    local b = browser()
    b:getSearchEngineConfig().country = "au"
    b:saveSettings("duckduckgo")
    b:resetToConfigDefaults()
    assert(shown[#shown].ok_callback)
    shown[#shown].ok_callback()
    assert(b:getSearchEngineConfig().country == "us")
    assert(saved.duckduckgo_country == nil and b.search_dialog)
end)

test("existing custom profiles remain selected", function()
    local b = browser(function() return {
        engine = "brave_personal", render_type = "mupdf",
        engines = { brave_personal = { name = "brave_api", api_key = "test-key" } },
    } end)
    local engine, config, name = b:getSearchEngineModule()
    assert(engine and name == "brave_api" and config.api_key == "test-key")
    assert(b:isMuPDFRender())
    b:showSearchDialog()
    assert(b.search_dialog)
end)

test("removing custom configuration returns to free defaults", function()
    local b = browser(function() return {
        engine = "brave_api", engines = { brave_api = { name = "brave_api", api_key = "test-key" } },
    } end)
    b:saveSettings()
    local restarted = browser()
    assert(restarted:getSelectedProfileKey() == "duckduckgo" and restarted:isCreRender())
end)

test("a saved missing provider does not override working defaults", function()
    saved.engine = "brave_api"
    local b = browser()
    assert(b:getSelectedProfileKey() == "duckduckgo")
end)

test("reset reloads custom overrides and drops removed options", function()
    local b = browser(function() return { download_images = true } end)
    assert(b:shouldDownloadImages())
    package.preload.webbrowser_configuration = function() return { engines = { duckduckgo = { country = "au" } } } end
    b:resetToConfigDefaults()
    shown[#shown].ok_callback()
    assert(not b:shouldDownloadImages() and b:getSearchEngineConfig().country == "au")
end)

test("custom file edits take precedence over previously saved UI choices", function()
    local loader = function() return { engines = { duckduckgo = { country = "au" } } } end
    local b = browser(loader)
    b:getSearchEngineConfig().country = "nz"
    b:saveSettings("duckduckgo")
    assert(browser(loader):getSearchEngineConfig().country == "nz")
    custom_mtime = 20
    local updated = browser(loader)
    custom_mtime = 10
    assert(updated:getSearchEngineConfig().country == "au")
end)

test("a broken optional file logs an error and still opens", function()
    local b = browser(function() error("test syntax error") end)
    b:showSearchDialog()
    assert(#warnings == 1 and b.search_dialog.title == "DuckDuckGo Search")
end)

package.preload.webbrowser_configuration = nil
package.loaded.webbrowser_configuration = nil
print(string.format("PASS: %d startup/settings checks", count))
