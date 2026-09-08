local T = MiniTest.new_set()

local modules = {
  "lsp_nulls_spec",
  "sql_tools_service_adapter_spec",
  "tools_downloader_spec",
  "workspace_spec",
  "activity_stream_spec",
  "ui_options_spec",
  "timeouts_spec",
  "connection_profiles_spec",
  "public_api_spec",
  "activity_ui_spec",
  "query_result_renderer_spec",
  "result_filetype_spec",
  "result_column_navigation_spec",
  "result_session_spec",
  "result_sticky_header_spec",
  "query_selection_spec",
  "query_backend_spec",
  "query_summary_spec",
  "object_script_spec",
}

for _, module in ipairs(modules) do
  T[module] = require("tests.unit." .. module)
end

return T
