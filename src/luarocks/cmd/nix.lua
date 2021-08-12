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

local path = require("luarocks.path")
local util = require("luarocks.util")
local fetch = require("luarocks.fetch")
local cfg = require("luarocks.core.cfg")
local queries = require("luarocks.queries")
local dir = require("luarocks.dir")
local fs = require("luarocks.fs")
local search = require("luarocks.search")
local write_rockspec = require("luarocks.cmd.write_rockspec")


-- new flags must be added to util.lua
-- ..util.deps_mode_help()
-- nix.help_arguments = "[--maintainers] {<rockspec>|<rock>|<name> [<version>]}"
function nix.add_to_parser(parser)
   local cmd = parser:command("nix", [[
Generates a nix derivation from a luarocks package.
If the argument is a .rockspec or a .rock, this generates a nix derivation matching the rockspec,
otherwise the program searches luarocks.org with the argument as the package name.

--maintainers set package meta.maintainers
]], util.see_also())
   :summary("Converts a rock/rockspec to a nix package")

   cmd:argument("name", "Rockspec for the rock to build.")
      :args("?")
   cmd:argument("version", "Rock(spec) version.")
      :args("?")

   cmd:option("--maintainers", "comma separated list of nix maintainers")
end

-- look at how it's done in fs.lua
local function debug(msg)
   if cfg.verbose then
      print("nix:"..msg)
   end
end

-- attempts to convert spec.description.license
-- to spdx id (see <nixpkgs>/lib/licenses.nix)
local function convert2nixLicense(license)
   assert (license ~= nil)
   return util.LQ(license)
end


function get_basic_checksum(url)
    -- TODO download the src.rock unpack it and get the hash around it ?
    local prefetch_url_program = "nix-prefetch-url"
    -- add --unpack flag to be able to use the resulet with fetchFromGithub and co ?

    local command = prefetch_url_program.." "..(url)
    local checksum = nil
    local r = io.popen(command)
    -- "*a"
    checksum = r:read()

    return checksum
end


-- Generate nix code using fetchurl
-- Detects if the server is in the list of possible mirrors
-- in which case it uses the special nixpkgs uris mirror://luarocks
local function gen_src_from_basic_url(url)
   assert(type(url) == "string")
   local checksum = get_basic_checksum(url)
   local final_url = url

   local dirname = dir.dir_name(url)
   for _, repo in ipairs(cfg.rocks_servers) do
      if repo == dirname then
         local basename = dir.base_name(url)
         final_url = "mirror://luarocks/"..basename
         break
      end
   end

   local src = [[fetchurl {
    url    = "]]..final_url..[[";
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
      util.printerr("Call to "..cmd.." failed")
   end
   src = [[fetchgit ( removeAttrs (builtins.fromJSON '']].. generatedSrc .. [[ '') ["date" "path"]) ]]

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

   util.printerr("Unsupported protocol"..protocol)
   assert(false) -- unsupported protocol
   return src
end


-- @param dependencies array of dependencies
-- @return dependency string and associated constraints
local function load_dependencies(deps_array)
   local dependencies = ""
   local cons = {}

   for _, dep in ipairs(deps_array)
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

    if manual_overrides["maintainers"] then
       maintainers_str = "    maintainers = with maintainers; [ "..manual_overrides["maintainers"].." ];\n"
    end

    if spec.detailed then
       long_desc_str = "    longDescription = ''"..spec.detailed.."'';"
    end

    dependencies, lua_constraints = load_dependencies(spec.dependencies)
    -- TODO to map lua dependencies to nix ones,
    -- try heuristics with nix-locate or manual table ?
    -- local external_deps = ""
    -- if spec.external_dependencies then
    --    external_deps = "# override to account for external deps"
    -- end

    if #lua_constraints > 0 then
       lua_constraints_str =  "  disabled = "..table.concat(lua_constraints,' || ')..";\n"
    end

    -- if only a rockspec than translate the way to fetch the sources
    local sources = ""
    if rock_url then
       sources = "src = "..gen_src_from_basic_url(rock_url)..";"
    elseif rockspec_url then

       -- we have to embed the valid rockspec since most repos dont contain
       -- valid rockspecs in the repo for a specific revision (the rockspec is
       -- manually updated before being uploaded to luarocks.org)
       sources = [[knownRockspec = (]]..url2src(rockspec_url)..[[).outPath;

  src = ]].. url2src(spec.source.url)..[[;
]]
    else
       return nil, "Either rockspec_url or rock_url must be set"
    end

    local propagated_build_inputs_str = ""
    if #dependencies > 0 then
       propagated_build_inputs_str = "  propagatedBuildInputs = [ "..dependencies.."];\n"
    end

    checkInputs, checkInputsConstraints = load_dependencies(spec.test_dependencies)

    if spec.test and spec.test.type then
       local test_type = spec.test.type
       if test_type == "busted" then
         checkInputs = checkInputs.."busted "
       end
    end


    -- introduced in rockspec format 3
    local checkInputsStr = ""
    if #checkInputs > 0 then
       checkInputsStr = "  checkInputs = [ "..checkInputs.."];\n"
       checkInputsStr = checkInputsStr.."  doCheck = true;\n"
    end
    local license_str = ""
    if spec.description.license then
       license_str = [[    license.fullName = ]]..convert2nixLicense(spec.description.license)..";\n"
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

  meta = with lib; {
    homepage = ]]..util.LQ(spec.description.homepage or spec.source.url)..[[;
    description = ]]..util.LQ(spec.description.summary or "No summary")..[[;
]]..long_desc_str..[[
]]..maintainers_str..[[
]]..license_str..[[
  };
};
]]

    return header
end

--
-- @return (spec, url, )
function run_query (name, version)

    -- "src" to fetch only sources
    -- see arch_to_table for, any delimiter will do
    local query = queries.new(name, nil, version, false, "src|rockspec")
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
   local url = write_rockspec.detect_url(name)

   if type(name) ~= "string" then
       return nil, "Expects package name as first argument. "..util.see_help("nix")
   end
   local rock_url
   local rockspec_name, rockspec_version
    -- assert(type(version) == "string" or not version)

   if name:match(".*%.rock$")  then
      spec, msg = fetch.fetch_and_unpack_rock(name, nil)
      if not spec then
          return false, msg
      end

   elseif url then
      print("is it an url ?", url)
      -- local pattern = "plenary.nvim-scm-1.rockspec"
      -- local src_dir = url
      local src_dir = "/home/teto/plenary.nvim"
      local res = fs.find(src_dir)
      print("Printing results")

      -- -- return base_name:match("(.*)%.[^.]*.rock") .. ".rockspec"
      -- rockspec_file = nil
      for _, file in ipairs(res) do
         -- if file:match("(.*)-([^-]+-%d+)%.(rockspec)") then
         -- local pattern = "(.*)-([^-]+-%d+)%.(rockspec)"
         -- print(file)
         local pattern = "(.*).(rockspec)"
         if file:match(pattern) then
            rockspec_file = file
            print("rockspec", rockspec_file)
         end
      end
   -- -- local rockspec_file = dir_name..".rockspec"

   util.printout("rockspec=", rockspec_file)
   elseif name:match(".*%.rockspec") then
      -- local fetch_git = require("luarocks.fetch.git")
      -- TODO it could accept the full url https://github.com/nvim-lua/plenary.nvim/blob/master/plenary.nvim-scm-1.rockspec
      -- dir.split_url
      -- THis should work:
      -- local rockspec = fetch.load_rockspec("http://localhost:8080/file/a_rock-1.0-1.rockspec")
      -- ok, proto = pcall(require, "luarocks.fetch."..protocol:gsub("[+-]", "_"))
      -- if not ok then
      --    return nil, "Unknown protocol "..protocol
      -- end
      -- os.execute()
      spec, err = fetch.load_rockspec(name, nil)
      if not spec then
          return false, err
      end
    else
      -- assume it's just a name
      rockspec_name = name
      rockspec_version = version
      url, res1 = run_query (rockspec_name, rockspec_version)
      if not url then
         return false, res1
      end

      local rockspec_file = nil
      local fetched_file = res1
      if url:match(".*%.rock$")  then

         rock_url = url

         -- here we are not sure it's actually a rock
         local dir_name, err, errcode = fetch.fetch_and_unpack_rock(fetched_file)
         if not dir_name then
            util.printerr("can't fetch and unpack "..name)
            return nil, err, errcode
         end
         rockspec_file = path.rockspec_name_from_rock(fetched_file)
         rockspec_file = dir_name.."/"..rockspec_file
      else
         -- it's a rockspec
         rockspec_file = fetched_file
         -- rockspec_url = url
      end

      spec, err = fetch.load_local_rockspec(rockspec_file, nil)
      if not spec then
         return nil, err
      end
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
