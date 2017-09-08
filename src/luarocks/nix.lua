local nix = {}
package.loaded["luarocks.nix"] = nix

local pack = require("luarocks.pack")
local path = require("luarocks.path")
local util = require("luarocks.util")
local repos = require("luarocks.repos")
local fetch = require("luarocks.fetch")
local fs = require("luarocks.fs")
local dir = require("luarocks.dir")
local deps = require("luarocks.deps")
local manif = require("luarocks.manif")
local remove = require("luarocks.remove")
local cfg = require("luarocks.cfg")

util.add_run_function(nix)
nix.help_summary = "Build/compile a rock."
nix.help_arguments = "[--pack-binary-rock] [--keep] {<rockspec>|<rock>|<name> [<version>]}"
nix.help = [[
toto test
]]..util.deps_mode_help()

function nix.convert2nix(name)
   local rockspec, err, errcode = fetch.load_rockspec(rockspec_file)
end



--- Driver function for "build" command.
-- @param name string: A local or remote rockspec or rock file.
-- If a package name is given, forwards the request to "search" and,
-- if returned a result, installs the matching rock.
-- @param version string: When passing a package name, a version number may
-- also be given.
-- @return boolean or (nil, string, exitcode): True if build was successful; nil and an
-- error message otherwise. exitcode is optionally returned.
function nix.command(flags, name, version)
   if type(name) ~= "string" then
      return nil, "Argument missing. "..util.see_help("build")
   end
   assert(type(version) == "string" or not version)
   print("hello world")

   -- if flags["pack-binary-rock"] then
   --    return pack.pack_binary_rock(name, version, do_build, name, version, deps.get_deps_mode(flags))
   -- else
   --    local ok, err = fs.check_command_permissions(flags)
   --    if not ok then return nil, err, cfg.errorcodes.PERMISSIONDENIED end
   --    ok, err = do_build(name, version, deps.get_deps_mode(flags), flags["only-deps"])
   --    if not ok then return nil, err end
   --    name, version = ok, err

   --    if (not flags["only-deps"]) and (not flags["keep"]) and not cfg.keep_other_versions then
   --       local ok, err = remove.remove_other_versions(name, version, flags["force"], flags["force-fast"])
   --       if not ok then util.printerr(err) end
   --    end

   --    manif.check_dependencies(nil, deps.get_deps_mode(flags))
   --    return name, version
   -- end
end


return nix
