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
local vers = require("luarocks.core.vers")


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
local function debug(...)
   if cfg.verbose then
      print("nix:", ...)
   end
end

-- attempts to convert spec.description.license
-- to spdx id (see <nixpkgs>/lib/licenses.nix)
local function convert2nixLicense(license)
   assert (license ~= nil)
   return util.LQ(license)
end


local function get_basic_checksum(url)
   -- TODO download the src.rock unpack it and get the hash around it ?
   local prefetch_url_program = "nix-prefetch-url"
   -- add --unpack flag to be able to use the resulet with fetchFromGithub and co ?

   local command = prefetch_url_program.." "..(url)
   local r = io.popen(command)
   -- "*a"
   local checksum = r:read()

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
local function gen_src_from_git_url(url, ref)
   -- TODO we could check a specific branch with --rev

   -- deal with  git://github.com/antirez/lua-cmsgpack.git for instance
   local cmd = "nix-prefetch-git --fetch-submodules --quiet "..url
   if ref then
      cmd = cmd.." --rev "..ref
   end

   debug(cmd)
   local generatedSrc= util.popen_read(cmd, "*a")
   if generatedSrc and generatedSrc == "" then
      util.printerr("Call to "..cmd.." failed")
   end

   return generatedSrc
end

-- converts url to nix "src"
-- while waiting for a program capable to generate the nix code for us
-- @param source dict: the rockspec spec.source, contains tag etc
local function url2src(url, ref)
   assert (url)

   local src = ""

   -- logic inspired from rockspecs.from_persisted_table
   local protocol, pathname = dir.split_url(url)
   debug("Generating src for protocol:"..protocol.." to "..pathname)
   if dir.is_basic_protocol(protocol) then
      return gen_src_from_basic_url(url)
   end

   if protocol == "git" or protocol == "git+https" then
      local normalized_url = "https://"..pathname
      -- print("normalized", normalized_url)
      local nix_json = gen_src_from_git_url(normalized_url, ref)
      src = [[fetchgit ( removeAttrs (builtins.fromJSON '']].. nix_json .. [[ '') ["date" "path"]) ]]

      return src

   end

   if protocol == "file" then
      return pathname
   end

   util.printerr("Unsupported protocol "..protocol)
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
      local entry = nix.convert_pkg_name_to_nix(dep.name)
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
-- @param rockspec_url Rockspecs are not easy to find in project repos, so we need to reference the luarocks one
-- @param rockspec_relpath path towards the rockspec from within the repository (should this be a directory ?)
-- @param rock_file if nil, will be fetched from url
-- @param manual_overrides a table of custom nix settings like "maintainers"
local function convert_spec2nix(spec, rockspec_relpath, rockspec_url, manual_overrides)
   assert ( spec )
   -- assert ( type(rock_url) == "string" or not rock_url )

   local lua_constraints_str = ""
   local maintainers_str = ""
   local long_desc_str = ""

   if manual_overrides["maintainers"] then
      maintainers_str = "    maintainers = with lib.maintainers; [ "..manual_overrides["maintainers"].." ];\n"
   end

   if spec.detailed then
      long_desc_str = "    longDescription = ''"..spec.detailed.."'';"
   end

   local dependencies, lua_constraints = load_dependencies(spec.dependencies)
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
   local sources
   local rockspec_str = ""

   if rockspec_url then
     -- sources = "src = "..gen_src_from_basic_url(rock_url)..";"
      rockspec_str = [[  knownRockspec = (]]..url2src(rockspec_url)..[[).outPath;]]
   end

   -- we have to embed the valid rockspec since most repos dont contain
   -- valid rockspecs in the repo for a specific revision (the rockspec is
   -- manually updated before being uploaded to luarocks.org)
   sources = "src = ".. url2src(spec.source.url, spec.source.tag)..[[;
]]
   -- else
   --    return nil, "Either rockspec_url or rock_url must be set"
   -- end

   local propagated_build_inputs_str = ""
   if #dependencies > 0 then
      propagated_build_inputs_str = "  propagatedBuildInputs = [ "..dependencies.."];\n"
   end

   local checkInputs, _ = load_dependencies(spec.test_dependencies)

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
      -- for now set it to false else it creates infinite loops in the nix code because
      -- of the way checkInputs are handled
      checkInputsStr = checkInputsStr.."  doCheck = false;\n"
   end
   local license_str = ""
   if spec.description.license then
      license_str = [[    license.fullName = ]]..convert2nixLicense(spec.description.license)..";\n"
   end


   if rockspec_relpath ~= nil and rockspec_relpath ~= "." and rockspec_relpath ~= "" then
      -- rockspecDir = ]]..rockspec_relpath..[[;
      rockspec_str = [[  rockspecDir = "]]..rockspec_relpath..[[";
]]
   end


   -- should be able to do without 'rec'
   -- we have to quote the urls because some finish with the bookmark '#' which fails with nix
   local header = [[
buildLuarocksPackage {
  pname = ]]..util.LQ(spec.name)..[[;
  version = ]]..util.LQ(spec.version)..[[;
]]..rockspec_str..[[

  ]]..sources..[[

]]..lua_constraints_str..[[
]]..propagated_build_inputs_str..[[
]]..checkInputsStr..[[

  meta = {
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

-- @return (spec, url, )
local function run_query (name, version)

   -- "src" to fetch only sources
   -- see arch_to_table for, any delimiter will do
   local arch = "rockspec" -- look only for rockspecs, use "src|rockspec" to search both
   local query = queries.new(name, nil, version, false, arch)
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
function nix.convert_pkg_name_to_nix(name)

   -- % works as an escape character
   local res, _ = name:gsub("%.", "-")
   return res
end



function nix.spec2nix_from_repo()
end

--- Driver function for "nix" command.
-- we need to have both the rock and the rockspec
-- @param name string: A local or remote rockspec or rock file.
-- If a package name is given, forwards the request to "search" and,
-- if returned a result, installs the matching rock.
-- @param version string: When passing a package name, a version number may
-- also be given.
-- @param maintainers string: the maintainer names, e.g. "teto vyc"
-- @return boolean or (nil, string, exitcode): True if build was successful; nil and an
-- error message otherwise. exitcode is optionally returned.
function nix.command(args)
   local name = args.name
   local version = args.version
   local maintainers = args.maintainers
   local spec, msg
   local rockspec_relpath = nil

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

   elseif name:match("://") then
      local url = write_rockspec.detect_url(name)

      debug("is it an url ?", url)
      local rockspec_filename = nil
      local generated_src = gen_src_from_git_url(url)
      local storePath = generated_src:match("path\": \"([^\n]+)\",")
      local src_dir = storePath
      local res = fs.find(src_dir)
      local current_candidate = nil
      debug("Printing results")

      -- -- return base_name:match("(.*)%.[^.]*.rock") .. ".rockspec"
      for _, file in ipairs(res) do
         -- if file:match("(.*)-([^-]+-%d+)%.(rockspec)") then
         -- local pattern = "(.*)-([^-]+-%d+)%.(rockspec)"
         debug("analyzing file ", file)
         local pkg_name , pkg_version, _ = path.parse_name(file)
         -- local basename = dir.base_name(file)

         -- local pattern = "(.*)-(.*).(rockspec)"
         -- local pkg_name, pkg_version = basename:match(pattern)
         if pkg_name then
            -- print("pkg_version ", pkg_version)
            -- print("pkg_name ", pkg_name)
            -- print("comparing version", version, " with pkg_version ", pkg_version)
            local newer

            if version then
               debug("pkg_version matches requested version ?", version)
               if pkg_version == version then
                  newer = true
                  debug("MATCH !! ", version)
                  current_candidate = pkg_version
               end
            elseif current_candidate then
               newer = vers.compare_versions(pkg_version, current_candidate)
            else
               newer = true
               current_candidate = pkg_version
            end

            if newer then
               rockspec_filename = storePath.. "/" .. file
               rockspec_relpath = dir.dir_name(file)
               debug("rockspec file", file)
               debug("rockspec_relpath [".. rockspec_relpath .."]")
               debug("rockspec_filename", rockspec_filename)
               -- todo check for version against the candidates
            end
         -- special case for lgi repo
         elseif file == "rockspec.in" then
            current_candidate = true
            rockspec_filename = storePath.. "/" .. file

         end
      end

      if not current_candidate then
         local err = "can't find a valid candidate "
         util.printerr(err)
         -- return nil, err
         return
      end
      -- local fetch_git = require("luarocks.fetch.git")
      debug("loading rockspec ", rockspec_filename)
      local err
      spec, err = fetch.load_local_rockspec(rockspec_filename, nil)
      if not spec then
         return nil, err
      end

      -- TODO if version matches scm, overwrite the source.url
      -- override the rockspec src
      -- spec.source.url = name

   else
      -- assume it's just a name
      rockspec_name = name
      rockspec_version = version
      local url, res1 = run_query (rockspec_name, rockspec_version)
      if not url then
         return false, res1
      end

      local rockspec_file
      local fetched_file = res1
      -- if url:match(".*%.rock$")  then

         rock_url = url
      --    -- here we are not sure it's actually a rock
      --    local dir_name, err, errcode = fetch.fetch_and_unpack_rock(fetched_file)
      --    if not dir_name then
      --       util.printerr("can't fetch and unpack "..name)
      --       return nil, err, errcode
      --    end
      --    rockspec_file = path.rockspec_name_from_rock(fetched_file)
      --    rockspec_file = dir_name.."/"..rockspec_file
      -- else
         -- it's a rockspec
         rockspec_file = fetched_file
         -- rockspec_url = url
      -- end

      spec, err = fetch.load_local_rockspec(rockspec_file, nil)
      if not spec then
         return nil, err
      end
   end

   local nix_overrides = {
      maintainers = maintainers
   }
   -- print("spec", spec)
   local derivation, err = convert_spec2nix(spec, rockspec_relpath, rock_url, nix_overrides)
   if derivation then
     print(derivation)
   end
   return derivation, err
end

return nix
