local nix = require("luarocks.cmd.nix")
local fetch = require("luarocks.fetch")
local cfg = require("luarocks.core.cfg")
local search = require("luarocks.search")

describe("luarocks nix source failures #unit", function()
   local spec
   local responses
   local execute
   local load_rockspec
   local print_result
   local servers
   local arch

   before_each(function()
      spec = {
         name = "fixture",
         version = "1.0-1",
         source = { url = "https://example.com/source.tar.gz" },
         description = {},
         dependencies = { queries = {} },
         build_dependencies = { queries = {} },
         test_dependencies = { queries = {} },
      }
      responses = {}
      execute = stub(os, "execute", function(cmd)
         local response = table.remove(responses, 1)
         assert.is_table(response)
         local output = assert(io.open(cmd:match(" > (.+)$"), "wb"))
         output:write(response.stdout or "")
         output:close()
         local stderr_path = cmd:match(" 2>(%S+)")
         if stderr_path then
            local stderr = assert(io.open(stderr_path, "wb"))
            stderr:write(response.stderr or "")
            stderr:close()
         end
         local status = response.status or 0
         if _VERSION == "Lua 5.1" then
            return status
         end
         return status == 0, "exit", status
      end)
      load_rockspec = stub(fetch, "load_rockspec", function()
         return spec
      end)
      print_result = stub(_G, "print")
      arch = cfg.arch
      cfg.arch = cfg.arch or "test"
      servers = cfg.rocks_servers
      cfg.rocks_servers = {}
   end)

   after_each(function()
      execute:revert()
      load_rockspec:revert()
      print_result:revert()
      cfg.rocks_servers = servers
      cfg.arch = arch
   end)

   local function fails()
      local result, err = nix.command({ name = "fixture-1.0-1.rockspec" })
      assert.is_nil(result)
      assert.is_string(err)
      assert.stub(print_result).was_not_called()
   end

   it("rejects a failed prefetch even with a checksum and path", function()
      responses = {{
         status = 1, stdout = "hash",
         stderr = "path is '/source'\n",
      }}
      fails()
   end)

   it("rejects a missing checksum", function()
      responses = {{ stderr = "path is '/source'\n" }}
      fails()
   end)

   it("rejects a missing prefetched path", function()
      responses = {{ stdout = "hash" }}
      fails()
   end)

   it("rejects a failed file command even with output", function()
      responses = {
         { stdout = "hash", stderr = "path is '/source'\n" },
         { status = 1, stdout = "/source: gzip compressed data" },
      }
      fails()
   end)

   it("rejects a failed unpack", function()
      responses = {
         { stdout = "hash", stderr = "path is '/source'\n" },
         { stdout = "/source: Zip archive data" },
         { status = 1, stdout = "partial" },
      }
      fails()
   end)

   it("propagates errors while fetching a known rockspec", function()
      local find = stub(search, "find_suitable_rock", function()
         return "https://example.com/fixture-1.0-1.rockspec"
      end)
      local download = stub(fetch, "fetch_url_at_temp_dir", function()
         return "fixture-1.0-1.rockspec"
      end)
      local load_local = stub(fetch, "load_local_rockspec", function()
         return spec
      end)
      responses = {{ status = 1 }}
      local result, err = nix.command({ name = "fixture" })
      find:revert()
      download:revert()
      load_local:revert()
      assert.is_nil(result)
      assert.is_string(err)
      assert.stub(print_result).was_not_called()
   end)

   for _, response in ipairs({
      { status = 1, stdout = "fetchFromGitHub { hash = \"partial\"; }" },
      { stdout = "" },
      { stdout = "   " },
      { stdout = "fetchFromGitHub {" },
   }) do
      it("rejects failed or incomplete nurl output: "..response.stdout, function()
         spec.source.url = "git+https://example.com/source"
         responses = { response }
         fails()
      end)
   end

   for _, git in ipairs({ false, true }) do
      it("preserves successful "..(git and "git" or "archive").." conversion", function()
         if git then
            spec.source.url = "git+https://example.com/source"
            responses = {{ stdout = "fetchFromGitHub { hash = \"hash\"; }" }}
         else
            responses = {
               { stdout = "hash", stderr = "path is '/source'\n" },
               { stdout = "/source: gzip compressed data" },
            }
         end
         local result, err = nix.command({ name = "fixture-1.0-1.rockspec" })
         assert.is_nil(err)
         assert.matches("buildLuarocksPackage {", result, 1, true)
         assert.stub(print_result).was_called(1)
      end)
   end
end)
