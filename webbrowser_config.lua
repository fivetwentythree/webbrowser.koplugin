-- Working defaults for installations without an optional configuration file.
local Config = {}

function Config.defaults()
    -- Return fresh tables: UI settings must not mutate the reset defaults.
    return {
        engine = "duckduckgo",
        engines = {
            duckduckgo = {
                name = "duckduckgo",
                display_name = "DuckDuckGo",
                base_url = "https://duckduckgo.com",
                search_path = "/html/",
                language = "en",
                country = "us",
                max_results = 10,
            },
        },
        render_type = "cre",
        keep_old_website_files = true,
        download_images = false,
        use_stylesheets = false,
        search_highlighted_text = false,
        search_history_limit = 10,
        website_history_limit = 50,
        duplicate_entry_on_website_history = true,
    }
end

local function merge(target, overrides)
    for key, value in pairs(overrides) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            merge(target[key], value)
        else
            target[key] = value
        end
    end
end

function Config.load(reload)
    if reload then
        package.loaded["webbrowser_configuration"] = nil
    end

    local config = Config.defaults()
    local ok, overrides = pcall(require, "webbrowser_configuration")
    if not ok then
        -- A missing file is normal. Report errors in an existing file to the
        -- caller, but keep the browser usable with the built-in defaults.
        local message = tostring(overrides)
        if message:match("^module 'webbrowser_configuration' not found:") then
            return config, false
        end
        return config, false, message
    end
    if type(overrides) ~= "table" then
        return config, false, "webbrowser_configuration.lua must return a table"
    end
    if overrides.engines ~= nil then
        if type(overrides.engines) ~= "table" then
            return config, false, "Configuration engines must be a table"
        end
        for key, profile in pairs(overrides.engines) do
            if type(key) ~= "string" or type(profile) ~= "table" then
                return config, false, "Each configured engine must be a named table"
            end
        end
    end

    -- Custom files may override just one option or provide full engine profiles.
    merge(config, overrides)
    return config, true
end

return Config
