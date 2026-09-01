local downloader = require("sqlserver.tools_downloader")

return {
  test_name = "SQL Tools Service releases should be explicit and validated",
  run_test_async = function()
    local release = downloader.get_release("1.2.3", "Linux", "x64")
    assert(release.version == "1.2.3")
    assert(release.filename == "Microsoft.SqlTools.ServiceLayer-linux-x64-net8.0.tar.gz")
    assert(release.url == "https://github.com/microsoft/sqltoolsservice/releases/download/1.2.3/" .. release.filename)

    local ok, err = pcall(downloader.get_release, "bad/version", "Linux", "x64")
    assert(not ok and tostring(err):find("tools_version", 1, true))

    ok, err = pcall(downloader.get_release, "1.2.3", "Plan9", "x64")
    assert(not ok and tostring(err):find("operating system Plan9", 1, true))

    ok, err = pcall(downloader.get_release, "1.2.3", "Linux", "x86")
    assert(not ok and tostring(err):find("architecture x86 on Linux", 1, true))

    if jit.os == "Windows" then
      return
    end

    local test_dir = vim.fn.tempname()
    local source_dir = vim.fs.joinpath(test_dir, "archive")
    local target_dir = vim.fs.joinpath(test_dir, "sqltools")
    local archive = vim.fs.joinpath(test_dir, "invalid.tar.gz")
    vim.fn.mkdir(source_dir, "p")
    vim.fn.mkdir(target_dir, "p")
    vim.fn.writefile({ "working" }, vim.fs.joinpath(target_dir, "existing-install"))
    vim.fn.writefile({ "not the service" }, vim.fs.joinpath(source_dir, "unexpected-file"))

    local packed = vim.system({ "tar", "-czf", archive, "-C", source_dir, "." }, { text = true }):wait()
    assert(packed.code == 0, packed.stderr)

    local installed, install_error = downloader.download_tools_async({ url = "file://" .. archive }, test_dir)
    assert(not installed)
    assert(install_error:find("expected executable", 1, true))
    assert(vim.fn.filereadable(vim.fs.joinpath(target_dir, "existing-install")) == 1)
    assert(#vim.fn.glob(vim.fs.joinpath(test_dir, "sqltools.installing-*"), false, true) == 0)

    vim.fn.delete(test_dir, "rf")
  end,
}
