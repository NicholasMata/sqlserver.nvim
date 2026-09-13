local T = MiniTest.new_set()

local modules = {
  "setup_spec",
  "lsp_nulls_spec",
  "sql_tools_service_client_spec",
  "backend_proxy_spec",
  "sql_tools_service_installer_spec",
  "workspace_spec",
  "operations_spec",
  "activity_stream_spec",
  "config_ui_spec",
  "timeouts_spec",
  "connection_profiles_spec",
  "public_api_spec",
  "query_lifecycle_spec",
  "connection_lifecycle_spec",
  "object_lifecycle_spec",
  "object_picker_spec",
  "activity_ui_spec",
  "generated_buffer_spec",
  "query_result_renderer_spec",
  "result_filetype_spec",
  "result_column_navigation_spec",
  "result_selection_spec",
  "result_html_spec",
  "clipboard_spec",
  "result_export_view_spec",
  "result_session_spec",
  "result_winbar_spec",
  "result_sticky_header_spec",
  "query_selection_spec",
  "sql_tools_service_query_spec",
  "sql_tools_service_scripting_spec",
  "query_summary_spec",
  "object_script_spec",
  "integration_shards_spec",
}

for _, module in ipairs(modules) do
  T[module] = require("tests.unit." .. module)
end

return T
