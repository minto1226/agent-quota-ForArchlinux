--!nonstrict
-- Agent Quota — background service polling agent-quota --json and generating 240° SVG gauges

local GAUGE_START_ANGLE = (5 * math.pi) / 6
local GAUGE_END_ANGLE = (13 * math.pi) / 6
local PERCENT_EPSILON = 1e-9

local COLOR_OK = "#8ff0a4"
local COLOR_WARN = "#f8e45c"
local COLOR_CRIT = "#ff7b72"
local COLOR_MUTED = "#6f8f78"
local COLOR_INSUFFICIENT = "#8a8a8a"
local COLOR_TRACK = "rgba(255, 255, 255, 0.16)"
local COLOR_TEXT = "rgba(255, 255, 255, 0.92)"

local isFetching = false
local lastFetchEpoch = 0
local cachedPayload = nil
local gaugesDir = noctalia.expandPath("~/.config/noctalia/plugins/agent-quota/gauges")
local iconsDir = noctalia.expandPath("~/.config/noctalia/plugins/agent-quota/icons")

noctalia.mkdirAll(gaugesDir)

local function getIntConfig(key, fallback)
    local val = tonumber(noctalia.getConfig(key))
    if val == nil then return fallback end
    return math.floor(val)
end

local function getBoolConfig(key, fallback)
    local val = noctalia.getConfig(key)
    if type(val) == "boolean" then return val end
    return fallback
end

local function getStringConfig(key, fallback)
    local val = noctalia.getConfig(key)
    if type(val) == "string" and val ~= "" then return val end
    return fallback
end

local function flooredPercent(pct)
    local num = tonumber(pct) or 0
    local clamped = math.max(0, math.min(100, num))
    return math.floor(clamped + PERCENT_EPSILON)
end

local function thresholdState(pct)
    local warn = getIntConfig("warning_threshold", 30)
    local crit = getIntConfig("critical_threshold", 10)
    if crit >= warn then
        crit = math.max(0, warn - 1)
    end
    if pct <= crit then return "critical" end
    if pct <= warn then return "warning" end
    return "ok"
end

local function meterFillHex(state, isRemaining, muted, insufficient, failed)
    if failed or insufficient then return COLOR_INSUFFICIENT end
    if muted then return COLOR_MUTED end
    if isRemaining == false then return COLOR_CRIT end
    if state == "critical" then return COLOR_CRIT end
    if state == "warning" then return COLOR_WARN end
    return COLOR_OK
end

local function arcPath(cx, cy, r, a1, a2)
    local x1 = cx + r * math.cos(a1)
    local y1 = cy + r * math.sin(a1)
    local x2 = cx + r * math.cos(a2)
    local y2 = cy + r * math.sin(a2)
    local large = if (a2 - a1) > math.pi then 1 else 0
    return string.format("M %.2f %.2f A %.2f %.2f 0 %d 1 %.2f %.2f", x1, y1, r, r, large, x2, y2)
end

local function gaugeArcAngles(pct, strokeWidth, radius)
    local clamped = math.max(0, math.min(100, tonumber(pct) or 0))
    if clamped <= 0 then
        return nil
    end
    if clamped >= 99.95 then
        return { startAngle = GAUGE_START_ANGLE, endAngle = GAUGE_END_ANGLE }
    end
    local safeRadius = math.max(1, radius)
    local arcSpan = GAUGE_END_ANGLE - GAUGE_START_ANGLE
    local maxSweep = math.max(0.2, arcSpan - (strokeWidth / safeRadius) - 0.18)
    local sweep = math.max(0.08, (clamped / 100.0) * maxSweep)
    return {
        startAngle = GAUGE_START_ANGLE,
        endAngle = GAUGE_START_ANGLE + sweep,
    }
end

local function renderGaugeSvg(pct, isRemaining, muted, insufficient, failed)
    local mode = getStringConfig("gauge_percent_mode", "number")
    local displayPct = if failed then 100 else flooredPercent(pct)
    local rawPct = if failed or pct == nil then displayPct else math.max(0, math.min(100, tonumber(pct) or 0))
    local state = thresholdState(rawPct)
    local strokeColor = meterFillHex(state, isRemaining, muted, insufficient, failed)

    -- 1:1 with torridfish popupGaugeShape(radius=21, offset=35)
    local w = 44
    local h = 39
    local cx = 22.0
    local cy = 22.0
    local r = 18.0
    local stroke = 4.0

    local trackD = arcPath(cx, cy, r, GAUGE_START_ANGLE, GAUGE_END_ANGLE)
    local arc = gaugeArcAngles(displayPct, stroke, r)
    local activePathXml = ""
    if arc then
        local activeD = arcPath(cx, cy, r, arc.startAngle, arc.endAngle)
        activePathXml = string.format(
            '  <path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="butt"/>\n',
            activeD, strokeColor, stroke
        )
    end

    local textXml = ""
    if not failed and mode ~= "hidden" then
        local textVal = if mode == "percent" then string.format("%d%%", displayPct) else tostring(displayPct)
        local textColor = if insufficient then COLOR_INSUFFICIENT else COLOR_TEXT
        local fontSize = if mode == "percent" and displayPct == 100 then 10 else 12
        textXml = string.format(
            '  <text x="%.1f" y="29.5" text-anchor="middle" dominant-baseline="central" fill="%s" font-family="Noto Sans, Cantarell, sans-serif" font-weight="700" font-size="%d">%s</text>\n',
            cx, textColor, fontSize, textVal
        )
    end

    local fileKey = string.format("g_%d_%s_%s_%s", displayPct, strokeColor:gsub("#", ""), mode, tostring(failed or false))
    local filePath = string.format("%s/%s.svg", gaugesDir, fileKey)
    local svg = string.format(
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">\n'
        .. '  <path d="%s" fill="none" stroke="%s" stroke-width="%.1f" stroke-linecap="butt"/>\n'
        .. '%s%s</svg>\n',
        w, h, w, h, trackD, COLOR_TRACK, stroke, activePathXml, textXml
    )
    noctalia.writeFile(filePath, svg)
    return filePath
end

local function generateBarIcons()
    local states = {
        ok = COLOR_OK,
        warning = COLOR_WARN,
        critical = COLOR_CRIT,
        error = COLOR_CRIT,
        loading = "#d8dee9",
    }
    local d = "M8 1.5a6.5 6.5 0 0 0-6.5 6.5c0 1.42.46 2.73 1.24 3.8l1.2-.87A5 5 0 1 1 13.06 11l1.2.87A6.5 6.5 0 0 0 8 1.5Zm0 2a4.5 4.5 0 0 0-4.5 4.5c0 .85.24 1.65.65 2.33l1.27-.92A3 3 0 1 1 11 8c0-.44-.1-.86-.27-1.24l-2.1 1.52a1 1 0 1 1-.88-1.23l1.02-2.4A4.5 4.5 0 0 0 8 3.5Z"
    for name, hex in pairs(states) do
        local svg = string.format(
            '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 16 16">\n  <path fill="%s" d="%s"/>\n</svg>\n',
            hex, d
        )
        noctalia.writeFile(string.format("%s/bar-%s.svg", gaugesDir, name), svg)
    end
end

local function formatPlanHeader(status)
    local showOrg = getBoolConfig("show_org_name", false)
    local plan = status.plan or status.name or ""
    if plan == "" then
        plan = status.name or status.key or "Provider"
    end
    if not showOrg and (status.key == "claude" or status.key == "codex") then
        plan = plan:gsub("%s*%b()%s*$", "")
    end
    return plan
end

local function shouldShowReset(metric)
    local reset = tostring(metric.reset or "")
    if reset == "" or reset == "—" then
        if flooredPercent(metric.pct) >= 100 and getBoolConfig("show_reset_when_full", true) then
            return true, "-"
        end
        return false, ""
    end
    if reset:lower():find("^no reset") then
        return true, "-"
    end
    if flooredPercent(metric.pct) >= 100 and not getBoolConfig("show_reset_when_full", true) then
        return false, ""
    end
    return true, reset
end

local function processAndPublish(payload)
    if type(payload) ~= "table" or type(payload.statuses) ~= "table" then
        return
    end

    local overallState = "ok"
    local hasError = false
    local sumPct = 0
    local countPct = 0
    local cards = {}
    local tooltipRows = {}

    for _, status in ipairs(payload.statuses) do
        local key = tostring(status.key or "")
        local state = tostring(status.state or "ok")
        local planTitle = formatPlanHeader(status)
        local userLabel = if getBoolConfig("show_user_info", false) then tostring(status.user or "") else ""
        if userLabel == "Unknown" then userLabel = "" end

        local iconPath = string.format("%s/provider-%s-symbolic.svg", iconsDir, key)
        if not noctalia.fileExists(iconPath) then
            iconPath = string.format("%s/gauge-symbolic.svg", iconsDir)
        end

        local metricsOut = {}
        local summaryParts = {}

        if state ~= "ok" then
            hasError = true
        else
            for _, m in ipairs(status.metrics or {}) do
                local isPct = (m.pct ~= nil)
                local svgPath = ""
                if isPct then
                    local pctNum = tonumber(m.pct) or 0
                    if not m.muted and not m.insufficient then
                        sumPct += pctNum
                        countPct += 1
                    end
                    svgPath = renderGaugeSvg(pctNum, m.is_remaining ~= false, m.muted == true, m.insufficient == true, false)
                    table.insert(summaryParts, string.format("%s %d%%", tostring(m.label or ""), flooredPercent(pctNum)))
                else
                    table.insert(summaryParts, string.format("%s %s", tostring(m.label or ""), tostring(m.value or "")))
                end

                local showRst, rstText = shouldShowReset(m)
                table.insert(metricsOut, {
                    label = tostring(m.label or ""),
                    value = tostring(m.value or ""),
                    isPct = isPct,
                    pct = if isPct then flooredPercent(m.pct) else nil,
                    svgPath = svgPath,
                    showReset = showRst,
                    resetText = rstText,
                    insufficient = (m.insufficient == true),
                })
            end
        end

        if #summaryParts > 0 then
            table.insert(tooltipRows, {
                key = string.format("%s (%s)", tostring(status.name or key), planTitle),
                value = table.concat(summaryParts, " · "),
            })
        elseif state ~= "ok" then
            table.insert(tooltipRows, {
                key = tostring(status.name or key),
                value = "Error: " .. tostring(status.error or state),
            })
        end

        table.insert(cards, {
            key = key,
            name = tostring(status.name or key),
            plan = planTitle,
            rawPlan = tostring(status.plan or ""),
            user = userLabel,
            workspaceId = tostring(status.workspace_id or ""),
            state = state,
            error = tostring(status.error or ""),
            iconPath = iconPath,
            metrics = metricsOut,
        })
    end

    -- 1:1 with extension.js lines 355-364: icon color follows the average of all active percentage gauges
    local avgPct = if countPct > 0 then math.floor((sumPct / countPct) + 0.5) else 100
    overallState = if countPct > 0 then thresholdState(avgPct) else "ok"

    local barIconPath = string.format("%s/bar-%s.svg", gaugesDir, overallState)
    noctalia.state.set("quota_data", {
        updatedAt = tostring(payload.updated_at or ""),
        overallState = overallState,
        hasError = hasError,
        lowestPct = avgPct,
        barIconPath = barIconPath,
        cards = cards,
        tooltipRows = tooltipRows,
        isFetching = isFetching,
    })
end

local function fetchQuotas(forceClearCache)
    if isFetching then return end
    isFetching = true

    if cachedPayload then
        processAndPublish(cachedPayload)
    else
        noctalia.state.set("quota_data", {
            overallState = "loading",
            hasError = false,
            lowestPct = 100,
            barIconPath = string.format("%s/bar-loading.svg", gaugesDir),
            cards = {},
            tooltipRows = { { key = "Agent Quota", value = "正在加载配额数据..." } },
            isFetching = true,
        })
    end

    local bin = noctalia.expandPath("~/.local/bin/agent-quota")
    local cmd = if forceClearCache
        then string.format("rm -f ~/.cache/agent-quota/*.json 2>/dev/null; %s --json", bin)
        else string.format("%s --json", bin)

    noctalia.runAsync(cmd, function(res)
        isFetching = false
        lastFetchEpoch = os.time()
        if res.stdout and res.stdout ~= "" then
            local decoded, err = noctalia.json.decode(res.stdout)
            if type(decoded) == "table" and type(decoded.statuses) == "table" then
                cachedPayload = decoded
                processAndPublish(decoded)
                return
            else
                noctalia.log("agent-quota json decode error: " .. tostring(err))
            end
        end
        if cachedPayload then
            processAndPublish(cachedPayload)
        end
    end, 45000)
end

local function launchSetup()
    noctalia.runInTerminal("~/.local/bin/agent-quota setup")
end

noctalia.state.watch("command", function(cmd)
    if type(cmd) ~= "table" then return end
    if cmd.action == "refresh" then
        fetchQuotas(cmd.force == true)
    elseif cmd.action == "settings" then
        noctalia.openSettings()
    elseif cmd.action == "setup" then
        launchSetup()
    elseif cmd.action == "terminal" then
        noctalia.runInTerminal("~/.local/bin/agent-quota --watch 30")
    end
end)

function onConfigChanged()
    if cachedPayload then
        processAndPublish(cachedPayload)
    end
end

function update()
    local interval = getIntConfig("refresh_seconds", 60)
    if not isFetching and (os.time() - lastFetchEpoch) >= interval then
        fetchQuotas(false)
    end
end

generateBarIcons()
noctalia.setUpdateInterval(5000)
fetchQuotas(false)
