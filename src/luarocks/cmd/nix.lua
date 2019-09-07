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

local pack = require("luarocks.pack")
local path = require("luarocks.path")
local util = require("luarocks.util")
local fetch = require("luarocks.fetch")
local search = require("luarocks.search")
local deps = require("luarocks.deps")
local cfg = require("luarocks.core.cfg")
local queries = require("luarocks.queries")
local dir = require("luarocks.dir")


-- new flags must be added to util.lua
-- ..util.deps_mode_help()
-- nix.help_arguments = "[--maintainers] {<rockspec>|<rock>|<name> [<version>]}"
function nix.add_to_parser(parser)
   local cmd = parser:command("nix", [[
Generates a nix package from luarocks package.

Just set the package name.

--maintainers set package meta.maintainers
]], util.see_also())
   :summary("Converts a rock/rockspec to a nix package")

   cmd:argument("name", "Rockspec for the rock to build.")
      :args("?")
   cmd:argument("version", "Rock(spec) version.")
      :args("?")

   cmd:flag("--maintainers", "comma separated list of nix maintainers")
end

-- look at how it's done in fs.lua
local function debug(msg)
   if cfg.verbose then
      print("nix:"..msg)
   end
end

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


-- Generate nix code using fetchurl
-- Detects if the server is in the list of possible mirrors
-- in which case it uses the special nixpkgs uris mirror://luarocks
local function gen_src_from_basic_url(url)
   assert(type(url) == "string")
   local checksum = get_basic_checksum(url)
   local final_url = url

   local dirname = dir.dir_name(url)
   local standard_repo = false
   for _, repo in ipairs(cfg.rocks_servers) do
      debug("checking against repo"..repo)
      if repo == dirname then
         local basename = dir.base_name(url)
         final_url = "mirror://luarocks/"..basename
         break
      end
   end

   local src = [[fetchurl {
    url    = ]]..final_url..[[;
    sha256 = ]]..util.LQ(checksum)..[[;
  }]]
   return src

end

-- Generate nix code to fetch from a git repository
local function gen_src_from_git_url(url)

   -- deal with  git://github.com/antirez/lua-cmsgpack.git for instance
   cmd = "nix-prefetch-git --fetch-submodules --quiet "..url

   debug(cmd)
   local generatedSrc= util.popen_read(cmd, "*a")
   if generatedSrc and generatedSrc == "" then
      utils.printerr("Call to "..cmd.." failed")
   end
   src = [[fetchgit ( removeAttrs (builtins.fromJSON '']].. generatedSrc .. [[ '') ["date"]) ]]

   return src
end

-- converts url to nix "src"
-- while waiting for a program capable to generate the nix code for us
local function url2src(url)

   local src = ""

   -- logic inspired from rockspecs.from_persisted_table
   local protocol, pathname = dir.split_url(url)
   debug("Generating src for protocol:"..protocol.." to "..pathname)
   if dir.is_basic_protocol(protocol) then
      return gen_src_from_basic_url(url)
   end

   if protocol == "git" then
      return gen_src_from_git_url(url)
   end

   if protocol == "file" then
      return pathname
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
   -- local lua_constraints = ""
   local dependencies = ""
   local cons = {}
   -- local lua_constraints = cons

   for id, dep in ipairs(deps_array)
   do
      local entry = convert_pkg_name_to_nix(dep.name)
      if entry == "lua" and dep.constraints then
         for _, c in ipairs(dep.constraints)
         do
            local constraint_str = nil
            if c.op == ">=" then
               constraint_str = "luaOlder "..util.LQ(tostring(c.version))
            elseif c.op == "==" then
               constraint_str = "lua.luaversion != "..util.LQ(tostring(c.version))
            elseif c.op == ">" then
               constraint_str = "luaOlder "..util.LQ(tostring(c.version))
            elseif c.op == "<" then
               constraint_str = "luaAtLeast "..util.LQ(tostring(c.version))
            end
            if constraint_str then
               cons[#cons+1] = "("..constraint_str..")"
            end

         end
      end
      dependencies = dependencies..entry.." "
   end
   return dependencies, cons
end


-- Converts luarocks to nix platform names
local function translate_platforms(spec)
   if spec.supported_platforms then
      return "    platforms = [];"
   end
end

-- TODO take into account external_dependencies
-- @param spec table
-- @param rock_url
-- @param rock_file if nil, will be fetched from url
-- @param manual_overrides a table of custom nix settings like "maintainers"
local function convert_spec2nix(spec, rockspec_url, rock_url, manual_overrides)
    assert ( spec )
    assert ( type(rock_url) == "string" or not rock_url )


    local dependencies = ""
    local lua_constraints = {}
    local lua_constraints_str = ""
    local maintainers_str = ""
    local long_desc_str = ""
    local platforms_str = ""

    if manual_overrides["maintainers"] then
       maintainers_str = "    maintainers = with maintainers; [ "..manual_overrides["maintainers"].." ];\n"
    end

    if spec.detailed then
       long_desc_str = "    longDescription = ''"..spec.detailed.."'';"
    end

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


    if #lua_constraints > 0 then
       lua_constraints_str =  "  disabled = "..table.concat(lua_constraints,' || ')..";\n"
    end

    -- TODO write a generate sources here
    -- if only a rockspec than translate the way to fetch the sources
    local sources = ""
    if rock_url then
       sources = "src = "..gen_src_from_basic_url(rock_url)..";"
    elseif rockspec_url then

       -- TODO might nbe a pb here
       sources = [[knownRockspec = (]]..url2src(rockspec_url)..[[).outPath;

  src = ]].. convert_specsource2nix(spec) ..[[;
]]
    else
       return nil, "Either rockspec_url or rock_url must be set"
    end

    local propagated_build_inputs_str = ""
    if #dependencies > 0 then
       propagated_build_inputs_str = "  propagatedBuildInputs = [ "..dependencies.."];\n"
    end

     checkInputs, checkInputsConstraints = load_dependencies(spec.test_dependencies)

     -- introduced in rockspec format 3
     local checkInputsStr = ""
     if #checkInputs > 0 then
        checkInputsStr = "  checkInputs = [ "..checkInputs.."];\n"
     end

   -- should be able to do without 'rec'
   -- we have to quote the urls because some finish with the bookmark '#' which fails with nix
    local header = [[
buildLuarocksPackage {
  pname = ]]..util.LQ(spec.name)..[[;
  version = ]]..util.LQ(spec.version)..[[;

  ]]..sources..[[

]]..lua_constraints_str..[[
]]..propagated_build_inputs_str..[[
]]..checkInputsStr..[[

  meta = with stdenv.lib; {
    homepage = ]]..util.LQ(spec.description.homepage or spec.source.url)..[[;
    description = ]]..util.LQ(spec.description.summary or "No summary")..[[;
]]..long_desc_str..[[
]]..maintainers_str..[[
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
    local operator = ">"
    local query = queries.new(name, version, false, "src|rockspec")
    local url, search_err = search.find_suitable_rock(query)
    if not url then
        util.printerr("can't find suitable rock "..name)
        return nil, search_err
    end
    debug('found url '..url)

    -- local rockspec_file = "unset path"
    local fetched_file, tmp_dirname, errcode = fetch.fetch_url_at_temp_dir(url, "luarocks-"..name)
    if not fetched_file then
       return nil, "Could not fetch file: " .. tmp_dirname, errcode
    end

    return url, fetched_file
end

-- Converts lua package name to nix package name
-- replaces dot with underscores
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
-- @param maintainers
-- @return boolean or (nil, string, exitcode): True if build was successful; nil and an
-- error message otherwise. exitcode is optionally returned.
function nix.command(args)
    local name = args.name
    local version = args.version
    local maintainers = args.maintainers

    if type(name) ~= "string" then
        return nil, "Expects package name as first argument. "..util.see_help("nix")
    end
    local spec, rock_url, rock_file
    local rockspec_name, rockspec_version
    -- assert(type(version) == "string" or not version)

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

    spec, err = fetch.load_local_rockspec(rockspec_file, nil)
    if not spec then
        return nil, err
    end

    nix_overrides = {
       maintainers = maintainers
    }
    local derivation, err = convert_spec2nix(spec, rockspec_url, rock_url, nix_overrides)
    if derivation then
      print(derivation)
    end
    return derivation, err
end

return nix
