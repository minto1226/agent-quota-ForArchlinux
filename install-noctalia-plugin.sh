#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_src="${repo_dir}/noctalia-plugin"
plugin_dest_base="${XDG_CONFIG_HOME:-${HOME}/.config}/noctalia/plugins"
plugin_dest="${plugin_dest_base}/agent-quota"

uv_command="$(command -v uv || true)"
if [ -z "${uv_command}" ] && [ -x "${HOME}/.local/bin/uv" ]; then
    uv_command="${HOME}/.local/bin/uv"
fi
if [ -z "${uv_command}" ]; then
    echo "uv is required to install Agent Quota." >&2
    exit 1
fi

echo "==> Installing agent-quota CLI backend via uv..."
"${uv_command}" tool install --force --refresh-package agent-quota "${repo_dir}"

echo "==> Deploying Noctalia plugin to ${plugin_dest}..."
mkdir -p "${plugin_dest}/icons" "${plugin_dest}/translations" "${plugin_dest}/gauges"
cp "${plugin_src}/plugin.toml" "${plugin_src}/service.luau" "${plugin_src}/widget.luau" "${plugin_src}/panel.luau" "${plugin_dest}/"
cp -R "${plugin_src}/icons/." "${plugin_dest}/icons/"
cp -R "${plugin_src}/translations/." "${plugin_dest}/translations/"

if command -v noctalia >/dev/null 2>&1; then
    echo "==> Linting Noctalia plugin..."
    noctalia plugins lint "${plugin_dest}"

    if noctalia msg status >/dev/null 2>&1; then
        echo "==> Registering local plugin source and enabling torridfish/agent-quota..."
        noctalia msg plugins source add my-local path "${plugin_dest_base}" >/dev/null 2>&1 || true
        noctalia msg plugins enable torridfish/agent-quota >/dev/null 2>&1 || true
        echo "==> Noctalia plugin enabled!"
        echo "To add the widget to your bar, include \"torridfish/agent-quota:widget\" in your bar widget list (e.g. bar.default.end)."
    else
        echo "==> Noctalia is not currently running; plugin files are installed at ${plugin_dest}."
    fi
else
    echo "==> Plugin files installed at ${plugin_dest}."
fi
