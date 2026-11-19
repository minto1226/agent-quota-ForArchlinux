--!nonstrict
-- Agent Quota — Noctalia bar widget

local defaultIcon = noctalia.expandPath("~/.config/noctalia/plugins/agent-quota/icons/gauge-symbolic.svg")
local currentData = noctalia.state.get("quota_data")

local function render(data)
    currentData = data
    barWidget.setVisible(true)

    local iconPath = defaultIcon
    local hasError = false
    if type(data) == "table" then
        if type(data.barIconPath) == "string" and data.barIconPath ~= "" and noctalia.fileExists(data.barIconPath) then
            iconPath = data.barIconPath
        end
        hasError = (data.hasError == true)
        if type(data.tooltipRows) == "table" and #data.tooltipRows > 0 then
            barWidget.setTooltip(data.tooltipRows)
        else
            barWidget.setTooltip("Agent Quota\n左键展开面板 · 右键立即刷新")
        end
    else
        barWidget.setTooltip("Agent Quota\n左键展开面板 · 右键立即刷新")
    end

    local children = {
        ui.image({
            key = "gauge-icon",
            path = iconPath,
            width = 18,
            height = 18,
            fit = "contain",
        }),
    }

    if hasError then
        table.insert(children, ui.label({
            key = "err-badge",
            text = "!",
            fontSize = 10,
            fontWeight = "bold",
            color = "#ff7b72",
        }))
    end

    local container = if barWidget.isVertical() then ui.column else ui.row
    barWidget.render(container({ gap = 2, align = "center" }, children))
end

function onClick()
    noctalia.togglePanel("torridfish/agent-quota:panel")
end

function onRightClick()
    noctalia.state.set("command", { action = "refresh", force = true })
    noctalia.osd.show("reload", "Refreshing Agent Quota...")
end

function onMiddleClick()
    noctalia.state.set("command", { action = "terminal" })
end

render(currentData)
noctalia.state.watch("quota_data", render)
