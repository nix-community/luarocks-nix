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

local nixpkgs_folder = "pkgs/development/lua-modules"
local filename = "luarocks-packages.nix"

util.add_run_function(nix)
nix.help_summary = "Build/compile a rock."
nix.help_arguments = "[--pack-binary-rock] [--keep] {<rockspec>|<rock>|<name> [<version>]}"
nix.help = [[
toto test
]]..util.deps_mode_help()

local function do_build(name, version, deps_mode, build_only_deps)
	-- only support rockspec for now
   if name:match("%.rockspec$") then
      return build.build_rockspec(name, true, false, deps_mode, build_only_deps)
   -- elseif name:match("%.src%.rock$") then
   --    return build.build_rock(name, false, deps_mode, build_only_deps)
   -- elseif name:match("%.all%.rock$") then
   --    local install = require("luarocks.install")
   --    local install_fun = build_only_deps and install.install_binary_rock_deps or install.install_binary_rock
   --    return install_fun(name, deps_mode)
   -- elseif name:match("%.rock$") then
   --    return build.build_rock(name, true, deps_mode, build_only_deps)
   -- elseif not name:match(dir.separator) then
   --    local search = require("luarocks.search")
   --    return search.act_on_src_or_rockspec(do_build, name:lower(), version, nil, deps_mode, build_only_deps)
   end
   return nil, "Don't know what to do with "..name
end

-- return header
function nix.header()
	local header = "/* "..filename.." is an auto-generated file -- DO NOT EDIT! */"
	return header
end

function nix.convert2nix(name)
	-- for now we accept only rockspec_filename
   if not name:match("%.rockspec$") then
	return nil, "Don't know what to do with "..name
   end
   rockspec_filename = name
      -- return build.build_rockspec(name, true, false, deps_mode, build_only_deps)
   local spec, err, errcode = fetch.load_rockspec(rockspec_filename)
   if not spec then
	   return nil, err
	end
   print("loaded name=", spec.name)
   local drv_name = spec.name..".nix"
   print("Writing derivation to ", drv_name)
   local fd = io.open(drv_name, "w+")

   -- deps.parse_dep(dep) is called fetch.load_local_rockspec so 
   -- so we havebuildLuaPackage defined in
   local dependencies = ""
   for id, dep in ipairs(spec.dependencies)
   do
		-- deps.constraints is a table {op, version}
		dependencies = dependencies.." "..dep.name
	   print("name; ", id, "dep:", dep.name)
   end

	-- todo check constraints to choose the correct version of lua
   local attrs = {
	name= spec.name,
    version= spec.version,
	-- we should run sthg to get sha
   src= "{  url="..(spec.source.url).."; sha256=".. "0x00".."}",
   meta= "{ homepage="..spec.description.homepage.."; }",
   -- nativeInputs etc will depend on the type of package (binary or ...)
   propagatedBuildInputs = "[".. dependencies .."]"
   }
   -- todo parse license too
   -- see https://stackoverflow.com/questions/1405583/concatenation-of-strings-in-lua for the best method to concat strings

    -- TODO
	-- dependencies

    -- meta = {
    --   homepage = "http://bitop.luajit.org";
    --   maintainers = with maintainers; [ flosse ];
    -- };
    -- buildFlags = stdenv.lib.optionalString stdenv.isDarwin "macosx";
   function table2str(s)
    local t = { }
    for k,v in pairs(s) do
        t[#t+1] = k.."="..tostring(v)..";"
    end
    return table.concat(t,"\n")
	end
	local str = table2str(attrs)

	-- spec.install => install phase

    -- installPhase = ''
    --   mkdir -p $out/lib/lua/${lua.luaversion}
    --   install -p bit.so $out/lib/lua/${lua.luaversion}
    -- '';


   ret, err = fd:write(str)
   if not ret then
	   print("Error happened: "..err)
	end
   -- ret, err = fd:write()
   fd:close()

   return true
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
   print("hello world name=", name)
   local res, err = nix.convert2nix(name)
   return res

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
