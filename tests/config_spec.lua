-- Run from the repository root: luajit tests/config_spec.lua
package.path = "./?.lua;" .. package.path
local Config = require("webbrowser_config")
local count = 0

local function test(name, loader, check)
    package.loaded.webbrowser_configuration = nil
    package.preload.webbrowser_configuration = loader
    local ok, err = pcall(check)
    package.loaded.webbrowser_configuration = nil
    package.preload.webbrowser_configuration = nil
    assert(ok, name .. ": " .. tostring(err))
    count = count + 1
end

test("fresh installation needs no configuration", nil, function()
    local config, custom, err = Config.load()
    assert(not custom and not err)
    assert(config.engine == "duckduckgo" and config.render_type == "cre")
    assert(config.engines.duckduckgo.base_url == "https://duckduckgo.com")
    assert(config.engines.duckduckgo.api_key == nil)
    assert(config.download_images == false and config.use_stylesheets == false)
end)

test("partial overrides keep the remaining defaults", function()
    return { engines = { duckduckgo = { country = "au" } }, download_images = true }
end, function()
    local config, custom = Config.load()
    assert(custom and config.download_images)
    assert(config.render_type == "cre" and config.use_stylesheets == false)
    assert(config.engines.duckduckgo.country == "au")
    assert(config.engines.duckduckgo.search_path == "/html/")
end)

test("existing API profiles and explicit false settings survive", function()
    return {
        engine = "brave_personal", render_type = "markdown",
        keep_old_website_files = false,
        engines = { brave_personal = {
            name = "brave_api", api_key = "test-key", language = "fr",
        } },
    }
end, function()
    local config, custom = Config.load()
    assert(custom and config.engine == "brave_personal")
    assert(config.render_type == "markdown" and not config.keep_old_website_files)
    assert(config.engines.brave_personal.api_key == "test-key")
    assert(config.engines.brave_personal.language == "fr")
    assert(config.engines.duckduckgo)
end)

test("runtime edits do not mutate defaults or the custom file's tables", function()
    return { engines = { duckduckgo = { country = "au" } } }
end, function()
    local first = Config.load()
    first.engines.duckduckgo.country = "nz"
    local second = Config.load()
    assert(second.engines.duckduckgo.country == "au")
    assert(Config.defaults().engines.duckduckgo.country == "us")
end)

test("a broken custom file falls back and reports the error", function()
    error("invalid custom configuration")
end, function()
    local config, custom, err = Config.load()
    assert(not custom and err:find("invalid custom configuration", 1, true))
    assert(config.engine == "duckduckgo" and config.render_type == "cre")
end)

test("an invalid return value falls back", function() return "wrong type" end, function()
    local config, custom, err = Config.load()
    assert(not custom and err:find("must return a table", 1, true))
    assert(config.engines.duckduckgo)
end)

test("invalid engine settings fall back before reaching the UI", function()
    return { engines = false }
end, function()
    local config, custom, err = Config.load()
    assert(not custom and err and config.engines.duckduckgo)
end)

test("invalid engine profiles fall back before reaching the UI", function()
    return { engines = { duckduckgo = "wrong type" } }
end, function()
    local config, custom, err = Config.load()
    assert(not custom and err and config.engines.duckduckgo.name == "duckduckgo")
end)

test("a missing dependency in custom configuration is reported", function()
    error("module 'custom_dependency' not found:", 0)
end, function()
    local _, custom, err = Config.load()
    assert(not custom and err:find("custom_dependency", 1, true))
end)

test("reset reloads the optional file and removes stale overrides", function()
    return { download_images = true, engines = { duckduckgo = { country = "au" } } }
end, function()
    assert(Config.load().download_images)
    package.preload.webbrowser_configuration = function() return { render_type = "mupdf" } end
    local config = Config.load(true)
    assert(config.render_type == "mupdf" and config.download_images == false)
    assert(config.engines.duckduckgo.country == "us")
end)

test("copying the sample retains free startup defaults", nil, function()
    local sample = dofile("webbrowser_configuration.sample.lua")
    assert(sample.engine == "duckduckgo" and sample.render_type == "cre")
    assert(not sample.download_images and not sample.use_stylesheets)
end)

print(string.format("PASS: %d configuration checks", count))
