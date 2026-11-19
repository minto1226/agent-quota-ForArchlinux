--!nonstrict
-- Agent Quota — Popup Panel (1:1 replication of torridfish/agent-quota GNOME popup)

local currentData = noctalia.state.get("quota_data")

local CARD_BG = "#ffffff12"
local CARD_RADIUS = 10
local COLOR_LABEL = "#ffffffd9"
local COLOR_RESET = "#ffffff7a"
local COLOR_DIM = "#ffffff8c"
local COLOR_ERR = "#f26d6d"
local COLOR_INSUFFICIENT = "#8a8a8a"

local function buildGaugeCell(metric, idx)
    local labelColor = if metric.insufficient then COLOR_INSUFFICIENT else COLOR_LABEL
    if metric.isPct then
        local children = {
            ui.image({
                key = string.format("ring-%d", idx),
                path = metric.svgPath,
                width = 44,
                height = 39,
                fit = "contain",
            }),
            ui.label({
                key = string.format("lbl-%d", idx),
                text = metric.label,
                fontSize = 11,
                color = labelColor,
                textAlign = "center",
                maxLines = 1,
            }),
        }
        if metric.showReset then
            table.insert(children, ui.label({
                key = string.format("rst-%d", idx),
                text = metric.resetText,
                fontSize = 10,
                color = COLOR_RESET,
                textAlign = "center",
                maxLines = 1,
            }))
        end
        return ui.column({
            key = string.format("cell-%d", idx),
            flexGrow = 1,
            minWidth = 64,
            align = "center",
            gap = 2,
        }, children)
    else
        local children = {
            ui.label({
                key = string.format("lbl-%d", idx),
                text = metric.label,
                fontSize = 11,
                color = labelColor,
                textAlign = "center",
                maxLines = 2,
            }),
            ui.label({
                key = string.format("val-%d", idx),
                text = metric.value,
                fontSize = 12,
                fontWeight = "bold",
                color = if metric.insufficient then COLOR_INSUFFICIENT else "#ffffffeb",
                textAlign = "center",
                maxLines = 2,
            }),
        }
        if metric.showReset then
            table.insert(children, ui.label({
                key = string.format("rst-%d", idx),
                text = metric.resetText,
                fontSize = 10,
                color = COLOR_RESET,
                textAlign = "center",
                maxLines = 1,
            }))
        end
        return ui.column({
            key = string.format("cell-%d", idx),
            flexGrow = 1,
            minWidth = 64,
            align = "center",
            justify = "center",
            gap = 4,
        }, children)
    end
end

local function buildProviderCard(card, cardIdx)
    local headerChildren = {
        ui.image({
            key = string.format("picon-%d", cardIdx),
            path = card.iconPath,
            width = 16,
            height = 16,
            fit = "contain",
        }),
        ui.label({
            key = string.format("pplan-%d", cardIdx),
            text = card.plan,
            fontSize = 13,
            fontWeight = "semibold",
            color = "#ffffffeb",
            maxLines = 1,
        }),
    }

    if card.user and card.user ~= "" then
        table.insert(headerChildren, ui.spacer({ flexGrow = 1 }))
        table.insert(headerChildren, ui.label({
            key = string.format("puser-%d", cardIdx),
            text = card.user,
            fontSize = 11,
            color = COLOR_DIM,
            maxLines = 1,
        }))
    end

    local cardChildren = {
        ui.row({
            key = string.format("hdr-%d", cardIdx),
            align = "center",
            gap = 6,
        }, headerChildren),
    }

    if card.state ~= "ok" then
        local shortErr = card.error
        if #shortErr > 90 then
            shortErr = string.sub(shortErr, 1, 87) .. "..."
        end
        table.insert(cardChildren, ui.label({
            key = string.format("err-%d", cardIdx),
            text = if shortErr ~= "" then shortErr else ("Status: " .. card.state),
            fontSize = 11,
            color = COLOR_ERR,
            maxLines = 2,
        }))
    else
        local metrics = card.metrics or {}
        if #metrics == 0 then
            table.insert(cardChildren, ui.label({
                key = string.format("empty-%d", cardIdx),
                text = "No metrics reported",
                fontSize = 11,
                color = COLOR_DIM,
            }))
        else
            -- Up to 5 gauges per rowInside a full-width card (like Gemini Pro 5 gauges)
            local maxPerRow = 5
            local rowCells = {}
            for mIdx, metric in ipairs(metrics) do
                table.insert(rowCells, buildGaugeCell(metric, cardIdx * 100 + mIdx))
                if #rowCells == maxPerRow or mIdx == #metrics then
                    table.insert(cardChildren, ui.row({
                        key = string.format("mrow-%d-%d", cardIdx, mIdx),
                        align = "start",
                        justify = "space_between",
                        gap = 8,
                    }, rowCells))
                    rowCells = {}
                end
            end
        end
    end

    return ui.column({
        key = string.format("card-%d-%s", cardIdx, card.key),
        flexGrow = 1,
        fill = CARD_BG,
        radius = CARD_RADIUS,
        padding = 12,
        gap = 10,
        tooltip = if card.state ~= "ok" and card.error ~= "" then card.error else nil,
    }, cardChildren)
end

local function packCardsIntoGrid(cards)
    -- Replicates the screenshot grid layout:
    -- Short cards (<= 3 gauges) pair up 2 per row; wide cards (>= 4 gauges, e.g. Gemini 5 gauges) span full row
    local rows = {}
    local pendingShort = nil
    local pendingIdx = 0

    for idx, card in ipairs(cards) do
        local mCount = if type(card.metrics) == "table" then #card.metrics else 0
        local isShort = (mCount > 0 and mCount <= 3 and card.state == "ok")

        if isShort then
            if pendingShort == nil then
                pendingShort = card
                pendingIdx = idx
            else
                table.insert(rows, ui.row({
                    key = string.format("grid-row-%d", idx),
                    align = "stretch",
                    gap = 10,
                }, {
                    buildProviderCard(pendingShort, pendingIdx),
                    buildProviderCard(card, idx),
                }))
                pendingShort = nil
            end
        else
            if pendingShort ~= nil then
                table.insert(rows, buildProviderCard(pendingShort, pendingIdx))
                pendingShort = nil
            end
            table.insert(rows, buildProviderCard(card, idx))
        end
    end

    if pendingShort ~= nil then
        table.insert(rows, buildProviderCard(pendingShort, pendingIdx))
    end

    return rows
end

function onSettingsClicked()
    panel.close()
    noctalia.openSettings()
end

function onSetupClicked()
    panel.close()
    noctalia.state.set("command", { action = "setup" })
end

function onRefreshClicked()
    noctalia.state.set("command", { action = "refresh", force = true })
end

function onTerminalClicked()
    panel.close()
    noctalia.state.set("command", { action = "terminal" })
end

local function render()
    local data = currentData
    local bodyNodes = {}

    if type(data) ~= "table" or type(data.cards) ~= "table" or #data.cards == 0 then
        table.insert(bodyNodes, ui.column({
            key = "loading-box",
            padding = 20,
            align = "center",
            gap = 8,
        }, {
            ui.label({
                text = if type(data) == "table" and data.isFetching then "Loading quotas…" else "No active providers configured",
                fontSize = 13,
                color = COLOR_DIM,
            }),
        }))
    else
        bodyNodes = packCardsIntoGrid(data.cards)
    end

    -- Footer matching screenshot: thin separator + Settings action on the left + quick setup/refresh/CLI on the right
    table.insert(bodyNodes, ui.separator({
        key = "footer-sep",
        color = "#ffffff1a",
        thickness = 1,
        spacing = 2,
    }))

    table.insert(bodyNodes, ui.row({
        key = "footer-row",
        align = "center",
        justify = "space_between",
        gap = 6,
    }, {
        ui.button({
            key = "btn-settings",
            text = "Settings",
            glyph = "settings",
            variant = "ghost",
            controlSize = "sm",
            contentAlign = "start",
            tooltip = "打开插件外观与阈值设置",
            onClick = "onSettingsClicked",
        }),
        ui.spacer({ flexGrow = 1 }),
        ui.button({
            key = "btn-setup",
            glyph = "adjustments-horizontal",
            variant = "ghost",
            controlSize = "sm",
            tooltip = "运行 agent-quota setup 自由勾选 11 家 AI 服务与配置密钥",
            onClick = "onSetupClicked",
        }),
        ui.button({
            key = "btn-terminal",
            glyph = "terminal-2",
            variant = "ghost",
            controlSize = "sm",
            tooltip = "在终端打开 agent-quota 实时表格",
            onClick = "onTerminalClicked",
        }),
        ui.button({
            key = "btn-refresh",
            glyph = "reload",
            variant = "ghost",
            controlSize = "sm",
            tooltip = if type(data) == "table" and data.isFetching then "正在刷新..." else "立即刷新配额",
            enabled = not (type(data) == "table" and data.isFetching),
            onClick = "onRefreshClicked",
        }),
    }))

    panel.render(ui.column({
        key = "root-col",
        padding = 12,
        gap = 10,
        align = "stretch",
    }, bodyNodes))
end

function onOpen(_context)
    currentData = noctalia.state.get("quota_data")
    render()
    noctalia.state.set("command", { action = "refresh", force = false })
end

noctalia.state.watch("quota_data", function(newData)
    currentData = newData
    render()
end)

render()
