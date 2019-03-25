-- Most likely you want to run this from
-- <nixpkgs>/maintainers/scripts/update-luarocks-packages
-- rockspec format available at
-- https://github.com/luarocks/luarocks/wiki/Rockspec-format
-- luarocks 3 introduced many things:
-- https://github.com/luarocks/luarocks/blob/master/CHANGELOG.md#new-build-system
-- this should be converted to an addon
-- https://github.com/luarocks/luarocks/wiki/Addon-author's-guide
-- needs at least one json library, for instance luaPackages.cjson
local nix = {}
package.loaded["luarocks.nix"] = nix

local pack = require("luarocks.pack")
local path = require("luarocks.path")
local util = require("luarocks.util")
local fetch = require("luarocks.fetch")
local search = require("luarocks.search")
local deps = require("luarocks.deps")
local cfg = require("luarocks.core.cfg")
local queries = require("luarocks.queries")
local dir = require("luarocks.dir")


nix.help_summary = "Build/compile a rock."
nix.help_arguments = " {<rockspec>|<rock>|<name> [<version>]}"
nix.help = [[

Generates a nix package from luarocks package.

Just set the package name
]]..util.deps_mode_help()


-- attempts to convert spec.description.license
-- to nix lib/licenses.nix
local function convert2nixLicense(spec)

    license = {
      fullName = spec.description.license;
    };
end


function get_basic_checksum(url)
    -- TODO download the src.rock unpack it and get the hash around it ?
    local prefetch_url_program = "nix-prefetch-url"
    -- add --unpack flag to be able to use the resulet with fetchFromGithub and co ?

    local command = prefetch_url_program.." "..(url)
    local checksum = nil
    local fetch_method = nil
    local r = io.popen(command)
    -- "*a"
    checksum = r:read()

    return checksum
end

-- TODO fetch sources/pack it
local function convert_rockspec2nix(name)
    spec, err, ret = fetch.load_rockspec(name)
end


local function gen_src_from_basic_url(url)
   assert(type(url) == "string")
   local checksum = get_basic_checksum(url)
   local src = [[fetchurl {
    url    = ]]..url..[[;
    sha256 = ]]..util.LQ(checksum)..[[;
  }]]
   return src

end

local function gen_src_from_git_url(url)

   -- deal with  git://github.com/antirez/lua-cmsgpack.git for instance
   cmd = "nix-prefetch-git --fetch-submodules --quiet "..url

   local r = io.popen(cmd)
   local generated_attr = r:read("*a")
   src = [[fetchgit ( removeAttrs (builtins.fromJSON '']].. generated_attr .. [[ '') ["date"]) ]]

   return src
end

-- converts url to nix "src"
-- while waiting for a program capable to generate the nix code for us
local function url2src(url)
   -- assert(type(url) == "string")

   local src = ""

   -- logic inspired from rockspecs.from_persisted_table
   local protocol, pathname = dir.split_url(url)
   if dir.is_basic_protocol(protocol) then
      return gen_src_from_basic_url(url)
   end

   if protocol == "git" then
      return gen_src_from_git_url(url)
   end

   assert(false) -- unsupported protocol
   return src
end


local function convert_specsource2nix(spec)
   assert(type(spec.source.url) == "string")
   return url2src(spec.source.url)
end


-- @param dependencies array of dependencies
-- @return dependency string and associated constraints
local function load_dependencies(deps_array)
   local lua_constraints = ""
   local dependencies = ""
   for id, dep in ipairs(deps_array)
   do
      local entry = convert_pkg_name_to_nix(dep.name)
      if entry == "lua" and dep.constraints then
         local cons = {}
         for _, c in ipairs(dep.constraints)
         do
            local constraint_str = nil
            if c.op == ">=" then
               constraint_str = " luaOlder "..util.LQ(tostring(c.version))
            elseif c.op == "==" then
               constraint_str = " lua.luaversion != "..util.LQ(tostring(c.version))
            elseif c.op == ">" then
               constraint_str = " luaOlder "..util.LQ(tostring(c.version))
            elseif c.op == "<" then
               constraint_str = " luaAtLeast "..util.LQ(tostring(c.version))
            end
            if constraint_str then
               cons[#cons+1] = "("..constraint_str..")"
            end

         end

         if #cons > 0 then
            lua_constraints =  "disabled = "..table.concat(cons,' || ')..";"
         end
      end
      dependencies = dependencies..entry.." "
   end
   return dependencies, lua_constraints
end

-- TODO take into account external_dependencies
-- @param spec table
-- @param rock_url
-- @param rock_file if nil, will be fetched from url
local function convert_spec2nix(spec, rockspec_url, rock_url)
    assert ( spec )
    assert ( type(rock_url) == "string" or not rock_url )


    local dependencies = ""
    local lua_constraints = ""
    -- for id, dep in ipairs(spec.dependencies)
    -- do
		-- local entry = convert_pkg_name_to_nix(dep.name)
		-- if entry == "lua" and dep.constraints then
			-- local cons = {}
			-- for _, c in ipairs(dep.constraints)
			-- do
				-- local constraint_str = nil
				-- if c.op == ">=" then
					-- constraint_str = " luaOlder "..util.LQ(tostring(c.version))
				-- elseif c.op == "==" then
					-- constraint_str = " lua.luaversion != "..util.LQ(tostring(c.version))
				-- elseif c.op == ">" then
					-- constraint_str = " luaOlder "..util.LQ(tostring(c.version))
				-- elseif c.op == "<" then
					-- constraint_str = " luaAtLeast "..util.LQ(tostring(c.version))
				-- end
				-- if constraint_str then
					-- cons[#cons+1] = "("..constraint_str..")"
				-- end

			-- end

    --      if #cons > 0 then
    --         lua_constraints =  "disabled = "..table.concat(cons,' || ')..";"
    --      end
		-- end
    --     dependencies = dependencies..entry.." "
    -- end

    dependencies, lua_constraints = load_dependencies(spec.dependencies)
    -- TODO to map lua dependencies to nix ones,
    -- try heuristics with nix-locate or manual table ?
    local external_deps = ""
    if spec.external_dependencies then
       --   for name, ext_files in util.sortedpairs(spec.external_dependencies)
       -- do
       --     local name = name:lower()
       -- external_deps = external_deps..(name)..".dev "
       -- end
       external_deps = "# override to account for external deps"
    end


    -- TODO write a generate sources here
    -- if only a rockspec than translate the way to fetch the sources
    local sources = ""
    if rock_url then
       sources = "src = "..gen_src_from_basic_url(rock_url)..";"
    elseif rockspec_url then

       -- TODO might nbe a pb here
       sources = [[
  knownRockspec = (]]..url2src(rockspec_url)..[[).outPath;

  src = ]].. convert_specsource2nix(spec) ..[[;
]]
    else
       return nil, "Either rockspec_url or rock_url must be set"
    end

    local propagatedBuildInputs = ""
    if #dependencies > 0 then
       propagatedBuildInputs = "propagatedBuildInputs = [ "..dependencies.."];"
    end


    --local checkInputs = ""
    -- local checkInputsConstraints = ""
    -- checkInputs, checkInputsConstraints = build_dependencies(spec.test_dependencies)
    --
    -- introduced in rockspec format 3
    -- if #dependencies > 0 then
    --    propagatedBuildInputs = "checkInputs = ["..dependencies.." ];"
    -- end

  -- should be able to do without 'rec'
   -- we have to quote the urls because some finish with the bookmark '#' which fails with nix
    local header = [[
buildLuarocksPackage {
  pname = ]]..util.LQ(spec.name)..[[;
  version = ]]..util.LQ(spec.version)..[[;

  ]]..sources..[[

  ]]..lua_constraints..[[

  ]]..propagatedBuildInputs..[[

  buildType = ]]..util.LQ(spec.build.type)..[[;

  meta = {
    homepage = ]]..util.LQ(spec.description.homepage or spec.source.url)..[[;
    description=]]..util.LQ(spec.description.summary)..[[;
    license = {
      fullName = ]]..util.LQ(spec.description.license)..[[;
    };
  };
};
]]

    return header
end

--
-- @return (spec, url, )
function run_query (name, version)
    local search = require("luarocks.search")

    -- "src" to fetch only sources
    -- see arch_to_table for, any delimiter will do
    local query = queries.new(name, version, false, "src rockspec" )
    local url, search_err = search.find_suitable_rock(query)
    if not url then
        util.printerr("can't find suitable rock "..name)
        -- util.printerr(search_err)
        return nil, search_err
    end
   util.printerr('found url '..url)

   -- local rockspec_file = "unset path"
   local fetched_file, tmp_dirname, errcode = fetch.fetch_url_at_temp_dir(url, "luarocks-"..name)
   if not fetched_file then
      return nil, "Could not fetch file: " .. tmp_dirname, errcode
   end

    return url, fetched_file
end

-- Converts lua package name to nix package name
-- replaces dot in names with underscores
function convert_pkg_name_to_nix(name)

	-- % works as an escape character
	local res, _ = name:gsub("%.", "_")
	return res
end

--- Driver function for "nix" command.
-- we need to have both the rock and the rockspec
-- @param name string: A local or remote rockspec or rock file.
-- If a package name is given, forwards the request to "search" and,
-- if returned a result, installs the matching rock.
-- @param version string: When passing a package name, a version number may
-- also be given.
-- @return boolean or (nil, string, exitcode): True if build was successful; nil and an
-- error message otherwise. exitcode is optionally returned.
function nix.command(flags, name, version)
    if type(name) ~= "string" then
        return nil, "Expects package name as first argument. "..util.see_help("nix")
    end
    local spec, rock_url, rock_file
    local rockspec_name, rockspec_version
    -- assert(type(version) == "string" or not version)

    -- if name:match("%.rockspec$")
    --  -- table or (nil, string, [string])
    --  local res, err = convert_rockspec2nix(name, version)
    -- else if
    if name:match(".*%.rock$")  then
        local rock_file = name
        local spec, msg = fetch.fetch_and_unpack_rock(rock_file, nil)
        if not spec then
            return false, msg
        end
        rockspec_name = spec.name
        rockspec_version = spec.version

    elseif name:match(".*%.rockspec") then
        local spec, err = fetch.load_rockspec(name, nil)
        if not spec then
            return false, err
        end
        rockspec_name = spec.name
        rockspec_version = spec.version
    else
        rockspec_name = name
        rockspec_version = version
    end

    url, res1 = run_query (rockspec_name, rockspec_version)


    if not url then
        return false, res1
    end

   -- if a rock is available
   -- res1 being the url
	local rock_url = nil
	local rockspec_url = nil
   local rockspec_file = nil
	local fetched_file = res1
    if url:match(".*%.rock$")  then

      rock_url = url

      -- here we are not sure it's actually a rock
      local dir_name, err, errcode = fetch.fetch_and_unpack_rock(fetched_file, dest)
      if not dir_name then
         util.printerr("can't fetch and unpack "..name)
         return nil, err, errcode
      end
      rockspec_file = path.rockspec_name_from_rock(fetched_file)
      rockspec_file = dir_name.."/"..rockspec_file
   else
      -- it's a rockspec
      rockspec_file = fetched_file
      rockspec_url = url
   end


    -- util.printerr("loading ",  rockspec_file)
    spec, err = fetch.load_local_rockspec(rockspec_file, nil)
    if not spec then
        return nil, err
    end


    local derivation, err = convert_spec2nix(spec, rockspec_url, rock_url)
	if derivation then
		print(derivation)
	end
    return derivation, err
end

return nix
