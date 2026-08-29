-- Qt's QML language server. Quickshell installs its qmltypes into the default
-- QML import path (/usr/lib/qt6/qml), so `import Quickshell` resolves without
-- any extra -I flags.
local cmd = { "qmlls6", "-E", "--no-cmake-calls" }

-- Hover docs for QtQuick types, only present when qt6-doc is installed.
if vim.uv.fs_stat("/usr/share/doc/qt6/qtquick") then
  vim.list_extend(cmd, { "-d", "/usr/share/doc/qt6" })
end

return {
  cmd = cmd,
  filetypes = { "qml" },
  root_markers = { ".qmlls.ini", "shell.qml", "qmldir", ".git" },
}
