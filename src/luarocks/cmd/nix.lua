-- Most likely you want to run this from
-- <nixpkgs>/maintainers/scripts/update-luarocks-packages.sh
-- rockspec format available at
-- https://github.com/luarocks/luarocks/wiki/Rockspec-format
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


nix.help_summary = "Build/compile a rock."
nix.help_arguments = " {<rockspec>|<rock>|<name> [<version>]}"
nix.help = [[
Just set the package name
]]..util.deps_mode_help()


-- attempts to convert spec.description.license
-- to nix lib/licenses.nix
local function convert2nixLicense(spec)
    -- should parse spec.description.license instead !
    -- local command = "nix-instantiate --eval -E 'with import <nixpkgs> { }; stdenv.lib.licenses."..(spec.description.license)..".shortName'"
    -- local r = io.popen(command)
    -- checksum = r:read()
    -- return "stdenv.lib.licenses.mit"

    license = {
      fullName = spec.description.license;
      -- url = http://sales.teamspeakusa.com/licensing.php;
      -- free = false;
    };
end


function get_checksum(rock_file)
    -- TODO download the src.rock unpack it and get the hash around it ?
    local prefetch_url_program = "nix-prefetch-url"

    local command = prefetch_url_program.." "..(rock_file)
    local checksum = nil
    local fetch_method = nil
    local r = io.popen(command)
    checksum = r:read()
    -- local attrSet = {url=(url), sha256=(checksum)}

    return checksum
end

    -- -- to speed up testing
    -- -- url = "https://luarocks.org/luabitop-1.0.2-1.src.rock"
    -- -- filename = "/home/teto/luarocks/src/luabitop-1.0.2-1.src.rock"
    -- -- local url = msg
    -- -- util.printout("downloading from url ", url)
    -- -- util.printout("got file ", rock_filename)


    -- -- to overwrite folders
    -- flags["force"] = 1
    -- -- can get url from rockspec.url maybe ?



-- TODO fetch sources/pack it
local function convert_rockspec2nix(name)
    spec, err, ret = fetch.load_rockspec(name)
end


-- local function rock2src(spec)
-- end

local function rockspec2src(spec)

-- https://github.com/luarocks/luarocks/wiki/Rockspec-format
   -- the good thing is zat nix-prefetch-zip caches downloads in the store
   -- todo check constraints to choose the correct version of lua
   -- local src = get_src(spec, url)
   local checksum = get_checksum(rock_file or rock_url)
   -- local checksum = "0x000"
  src = [[ (fetchurl {
    url    = ]]..rock_url..[[;
    sha256 = ]]..util.LQ(checksum)..[[;
  }) ]]
  return src
end

-- TODO take into account external_dependencies !!
-- @param spec table
-- @param rock_url
-- @param rock_file if nil, will be fetched from url
-- fetch.fetch_sources
-- fetch.fetch_and_unpack_rock(rock_file, dest)
-- @param name lua package name e.g.: 'lpeg', 'mpack' etc
local function convert_spec2nix(spec, rock_url, rock_file)
    assert ( spec )
    assert ( type(rock_url) == "string" )


    -- deps.parse_dep(dep) is called fetch.load_local_rockspec so
    -- so we havebuildLuaPackage defined in
    local dependencies = ""
    local external_deps = ""
    local lua_constraints = ""
    for id, dep in ipairs(spec.dependencies)
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
					constraint_str = " lua.majorVersion != "..util.LQ(tostring(c.version))
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

  -- TODO need to map lua dependencies to nix ones,
  -- try heuristics with nix-locate or manual table ?
  --
  -- what to do with those
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
    -- srcs = [ (spec.source.url
   -- see https://stackoverflow.com/questions/1405583/concatenation-of-strings-in-lua for the best method to concat strings
   -- nixpkgs accept empty/inplace license see
   -- we could try to map the luarocks licence to nixpkgs license
   -- see convert2nixLicense or/and hope for this https://github.com/luarocks/luarocks/issues/762
   -- we have to quote the urls because some finish with the bookmark '#' which fails with nix
   -- ]]..external_deps..[[
   -- maybe we should have
   -- get rid of the rec ?

   sources = 
  src = fetchurl {
    url    = ]]..rock_url..[[;
    sha256 = ]]..util.LQ(checksum)..[[;
  };

    local header = convert_pkg_name_to_nix(spec.name)..[[ = buildLuaPackage rec {
  pname = ]]..util.LQ(spec.name)..[[;
  version = ]]..util.LQ(spec.version)..[[;

  ]]..sources..[[
  ]]..lua_constraints..[[


  propagatedBuildInputs = []]..dependencies..[[
  ];

  buildType=]]..util.LQ(spec.build.type)..[[;

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
--
-- @return (spec, url, rock_file)
function load_rock_from_name (name, version)
    local search = require("luarocks.search")

    local query = queries.new(name, version, nil, "src" )
    local url, search_err = search.find_suitable_rock(query)
    if not url then
        util.printerr("can't find suitable rock "..name)
        -- util.printerr(search_err)
        return false, search_err
    end

	-- we might want to fetch it with nix-prefetch-url instead because it will
	-- get cached
    local rock_file, tmp_dirname, errcode = fetch.fetch_url_at_temp_dir(url, "luarocks-rock-"..name)
    if not rock_file then
        return nil, "Could not fetch rock file: " .. tmp_dirname, errcode
    end

    local dir_name, err, errcode = fetch.fetch_and_unpack_rock(rock_file, dest)
    if not dir_name then
        return nil, err, errcode
    end
    local rockspec_file = path.rockspec_name_from_rock(rock_file)
    rockspec_file = dir_name.."/"..rockspec_file
    -- util.printerr("loading ",  rockspec_file)
    spec, err = fetch.load_local_rockspec(rockspec_file, nil)
    if not spec then
        return nil, err
    end
    return spec, url, rock_file
end

function convert_pkg_name_to_nix(name)

	-- replaces dot in names with underscores
	-- % works as an escape character
	local res, _ = name:gsub("%.", "_")
	return res
end

--- Driver function for "convert2nix" command.
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
        -- nil = dest
        -- should return path to the rockspec
        -- TODO I would need to find its url !
        -- print('this might be a src.rock')
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
        -- print("Loaded locally version ", rockspec_version)
		-- -- test mode
		-- local derivation, err = convert_spec2nix(spec, "")
		-- if derivation then
		-- 	print(derivation)
		-- end
		-- return true
    else
        rockspec_name = name
        rockspec_version = version
    end

    -- print("Loading ", rockpsec_name)
    spec, res1, rock_file = load_rock_from_name (rockspec_name, rockspec_version)

    if not spec then
        return false, res1
    end
	local rock_url = res1

	-- not needed in principle
	-- print("rock version= ", spec.version, " to compare with", rockspec_version)
	-- if rockspec_version and (rockspec_version ~= spec.version) then
	-- 	return false, "could not find a src.rock for version "..version..
	-- 		" ( "..rockspec_version.." is available though )"
	-- end

    local derivation, err = convert_spec2nix(spec, rock_url)
	if derivation then
		print(derivation)
	end
    return derivation, err
end

   -- print("hello world name=", name)
   -- todo should expect a spec + rock file ?
   -- local res, err = convert_rock2nix(name, version)
   -- return false, res, err

   -- if flags["pack-binary-rock"] then
   --    return pack.pack_binary_rock(name, version, do_build, name, version, deps.get_deps_mode(flags))
   -- else


return nix
