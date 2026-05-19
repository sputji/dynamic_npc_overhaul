ModOptions = ModOptions or {}
if ModOptions.getInstance then
	--print("Custom options engine is already installed!")
	return ModOptions --custom options engine is already installed!
end
local MO = ModOptions
MO._ModOptions = MO
MO.__index = MO

do --Patch 41.77.6+ to be compatible with old mods.
	local m = __classmetatables[zombie.core.Core.class].__index
	if m.getVersion and m.getVersionNumber == nil then
		m.getVersionNumber = m.getVersion
	end
end

local OPTIONS_CHUNKS = {}
MO.OPTIONS_CHUNKS = OPTIONS_CHUNKS

local OptDataMeta; OptDataMeta = {
	set = function(self,value)
		--self.value = value
		self._before = value
		--self.settings.options[self.id] = value
		if self.ui then
			self.ui:toUI()
		end
	end,
	--get = function(self)
	--	return self.value
	--end,
	setData = function(self,list)
		for k,v in pairs(list) do
			self[k] = v
		end
	end,
	resetLua = function(self)
		if self.gameOption then
			self.gameOption:resetLua()
		end
	end,
	getType = function(self)
		local typ = type(self.default) --boolean,string,number
		if typ == "boolean" then
			return "checkbox"
		elseif typ == "string" then
			if self.is_multiline then
				return "text"
			end
			return typ
		elseif typ == 'number' then
			if self[1] then --dropdown list
				return 'enum'
			end
			return "entry" --integer or double
		end
		return typ
	end,
	setRaw = function(self,val) --set value and copy it to options table 
		self.value = val
		self.settings.options[self.id] = val
	end,
}
OptDataMeta.__index = OptDataMeta


local function PrepareChunk(chunk)
	--Search missing keys in other tables
	if chunk.names then
		for k,v in pairs(chunk.names) do
			local data = chunk.options_data[k]
			if not data then
				data = {}
				chunk.options_data[k] = data
			end
			data.name = v
		end
	end
	if chunk.options then
		for k,v in pairs(chunk.options) do
			local data = chunk.options_data[k]
			if not data then
				--if type(v) == 'table' then
				data = {}
				chunk.options_data[k] = data
			end
			data.value = v
			data.default = v
		end
	else
		chunk.options = {}
	end
	--Now "options_data" is the main table with all the keys.
	local options = chunk.options
	for k,v in pairs(chunk.options_data) do
		v.id = k
		v.name = v.name or k
		--v._before = v.value
		v.settings = chunk
		setmetatable(v,OptDataMeta)
		if options[k] == nil then
			if v.value ~= nil then
				options[k] = v.value
			else
				options[k] = v.default
			end
		end
		--Deprecated functions
		if v.onUpdateMainMenu then
			v.OnApplyMainMenu = v.onUpdateMainMenu
		end
		if v.onUpdateIngame then
			v.OnApplyInGame = v.onUpdateIngame
		end
	end
end


function MO:getInstance(options, mod_id, mod_shortname, mod_fullname) --print('getInstance',self,options,mod_id)
	if not options then
		if not self or not self.mod_id then
			return print('ERROR in getInstance: incorrect parameters!')
		end
		options = self
	end
	if type(options) ~= 'table' then
		return print('ERROR in getInstance: bad options!')
	end
	if options.mod_id and options.options_data and getmetatable(options) == MO then
		print('WARNING in getInstance: double initialization!')
		return options
	end
	local chunk
	if mod_id then --all data in params
		if type(mod_id) ~= 'string' or mod_id == '' then
			mod_id = 'Base'
		end
		chunk = {
			options = options,
			mod_id = mod_id,
			index = #OPTIONS_CHUNKS + 1,
			mod_shortname = mod_shortname or mod_id,
			mod_fullname = mod_fullname or mod_shortname or mod_id,
			names = {},
			options_data = {},
		}
	else --all data in a table
		chunk = options
		mod_id = chunk.mod_id or 'Base'
		chunk.mod_id = mod_id
		chunk.mod_shortname = chunk.mod_shortname or mod_id
		chunk.mod_fullname = chunk.mod_fullname or chunk.mod_shortname
		chunk.index = #OPTIONS_CHUNKS + 1
		chunk.options_data = chunk.options_data or {}
	end
	PrepareChunk(chunk)
	table.insert(OPTIONS_CHUNKS, chunk)
	setmetatable(chunk,MO)
	return chunk
end


local function extractValue(val, src)
	if type(src) == 'boolean' then
		if val=='true' then
			return true
		elseif val=='false' then
			return false
		end
		val=val:lower()
		if val=='true' then
			return true
		elseif val=='false' then
			return false
		end
	elseif type(src) == 'number' then
		val = tonumber(val)
		if val then
			return val
		end
	elseif type(src) == 'string' then
		return val
	elseif type(src) == 'table' then
		local num = tonumber(val)
		for i,v in ipairs(src) do
			if type(v) == 'number' then
				if v == num then
					src.value = v
					break
				end
			elseif v == val then
				src.value = v
				break
			end
		end
	end
	return src
end


local ini_data = nil
local function ApplyIniData()
	if not ini_data then
		return
	end
	for _,chunk in pairs(OPTIONS_CHUNKS) do
		if not chunk.is_ini_loaded then
			chunk.is_ini_loaded = true
			local data = ini_data[chunk.mod_id]
			if data then
				local options = chunk.options
				for k,v in pairs(data) do
					if options[k] ~= nil then
						local val = extractValue(v,options[k])
						options[k] = val
						chunk.options_data[k].value = val
					end
				end
			end
		end
	end
end
MO.ApplyIniData = ApplyIniData


local function prepareCustomData(is_reset)
	if is_reset then
		for _,chunk in pairs(OPTIONS_CHUNKS) do
			chunk.is_prepared = nil
		end
	end
	table.sort(OPTIONS_CHUNKS, function(a,b)
		if a.mod_id == "Base" then
			return true
		elseif b.mod_id == "Base" then
			return false
		end
		if a.priority == b.priority then
			return a.mod_fullname < b.mod_fullname
		else
			local a1 = tonumber(a.priority)
			local b1 = tonumber(b.priority)
			if a1 and b1 then
				return a1 > b1
			elseif not a1 ~= not b1 then
				return not b1
			end
		end
		return a.mod_fullname < b.mod_fullname
	end)
	for _,chunk in pairs(OPTIONS_CHUNKS) do
		if not chunk.is_prepared then
			chunk.is_prepared = true
			PrepareChunk(chunk)
		end
	end
	MO.ApplyIniData()
end
MO.prepareCustomData = prepareCustomData


local function loadIniData()
	if ini_data then
		return
	end
	print('ModOptions: Loading ini data...')
	ini_data = {Base={}}
	local reader = getFileReader("mods_options.ini", false)
	if not reader then
		return
	end
	local current_mod = "Base"
	while true do
		local line = reader:readLine()
		if not line then
			reader:close()
			break
		end
		line = line:trim()
		if line ~= "" then
			local k,v = line:match("^([^=%[]+)=([^=]+)$")
			if k then
				k = k:trim()
				ini_data[current_mod][k] = v:trim()
			else
				local mod = line:match("^%[([^%[%]%%]+)%]$")
				if mod then
					current_mod = mod:trim()
					if not ini_data[current_mod] then
						ini_data[current_mod] = {}
					end
				end
			end
		end
	end
end
MO.loadIniData = loadIniData

local function loadFile()
	loadIniData()
	prepareCustomData()
end
MO.loadFile = loadFile

local function saveIniData()
	local saved={Base={}}
	local writer = getFileWriter("mods_options.ini", true, false)
	
	writer:write("[Base]\r\n")
	for i,v in ipairs(OPTIONS_CHUNKS) do
		if v.mod_id == 'Base' then
			writer:write("-----\r\n")
			for k,v in pairs(v.options) do
				local val = v
				if type(v) == 'table' then
					val = v.value
				end
				writer:write(k .. ' = ' .. tostring(val) .. "\r\n")
				saved.Base[k] = true
			end
		end
	end
	
	if ini_data then
		writer:write("\r\n")
		for k,v in pairs(ini_data.Base) do
			if not saved.Base[k] then
				writer:write(k .. ' = ' .. v .. "\r\n")
			end
		end
	end
	
	for i,v in ipairs(OPTIONS_CHUNKS) do
		local id = tostring(v.mod_id)
		if id ~= 'Base' then
			if not saved[id] then
				saved[id] = {}
			end
			writer:write("\r\n["..id.."]\r\n")
			for k,v in pairs(v.options) do
				local val = v
				if type(v) == 'table' then
					val = v.value
				end
				writer:write(k .. ' = ' .. tostring(val) .. "\r\n")
				saved[id][k] = true
			end
		end
	end
	
	if ini_data then
		for id,v in pairs(ini_data) do
			if not saved[id] then
				writer:write("\r\n["..id.."]\r\n")
				for k,v in pairs(v) do
					writer:write(k .. ' = ' .. v .. "\r\n")
				end
			end
		end
	end
	
	writer:close();
end
MO.saveIniData = saveIniData

local save_cnt = 0
function MO:TrySave(input_count)
	if input_count == nil then
		save_cnt = 0
		return
	end
	save_cnt = save_cnt + 1
	if save_cnt == input_count then
		saveIniData()
	end
end

function MO:getData(option_id)
	return self.options_data[option_id]
end

local cache_isHost = nil
function MO:isHost()
	if cache_isHost == nil then
		cache_isHost = not isClient() and not isServer()
	end
	return cache_isHost
end

local key_binging_map
local key_binding_num
local function MakeKeyBindingMap()
	key_binging_map = {}
	key_binding_num = #keyBinding
	local cat_name
	for i,v in ipairs(keyBinding) do
		if not v.key and v.value and luautils.stringStarts(v.value, "[") then
			if cat_name then
				key_binging_map[cat_name] = i
			end
			cat_name = v.value
		end
	end
	if cat_name then
		key_binging_map[cat_name] = key_binding_num + 1
	end
end
local function ShiftMap(idx)
	for i,v in ipairs(key_binging_map) do
		if v >= idx then
			key_binging_map[i] = v + 1
		end
	end
end

local key_bindings = {}
function MO:AddKeyBinding(category, data)
	assert(category and data.key and data.name, "ERROR: bad binding key data")
	if key_binding_num ~= #keyBinding then
		MakeKeyBindingMap()
	end
	local idx = key_binging_map[category]
	if not idx then
		table.insert(keyBinding,{value = category})
		key_binding_num = key_binding_num + 1
		idx = key_binding_num + 1
		key_binging_map[category] = idx
	end
	local bind_data = {
		key=data.key,
		value=data.name,
	}
	table.insert(keyBinding,idx,bind_data)
	ShiftMap(idx)
	table.insert(key_bindings,data)
end

local function CopyKeyBindingData()
	local core = getCore()
	for _,v in pairs(key_bindings) do
		v.key = core:getKey(v.name)
	end
end

function MO:_OnApply()
	saveIniData()
	CopyKeyBindingData()
	local is_ingame = MainScreen.instance.inGame
	for _,v in ipairs(OPTIONS_CHUNKS) do
		if v.OnApply then
			v:OnApply()
		end
		if is_ingame then
			if v.OnApplyInGame then
				v:OnApplyInGame()
			end
		elseif v.OnApplyInMainMenu then
			v:OnApplyInMainMenu()
		end
	end
end

function MO:_OnLoadKeys()
	CopyKeyBindingData()
end

function MO:_AddSandboxOption(path,name)
	if not self.options_data then
		error('ERROR: you should attach this function to the settings!')
	end
	local opt = self.options_data[name]
	if not opt then
		error('ERROR: no such option - '..tostring(name))
	end
	opt.sandbox_path = path
end
function MO:MoveOptionsToSandbox(path,a,b,c,d,e,f,g,h)
	if type(a) == 'table' then
		for _,v in pairs(a) do
			self:_AddSandboxOption(path,v)
		end
		return
	end
	if not a then return end self:_AddSandboxOption(a)
	if not b then return end self:_AddSandboxOption(b)
	if not c then return end self:_AddSandboxOption(c)
	if not d then return end self:_AddSandboxOption(d)
	if not e then return end self:_AddSandboxOption(e)
	if not f then return end self:_AddSandboxOption(f)
	if not g then return end self:_AddSandboxOption(g)
	if not h then return end self:_AddSandboxOption(h)
end

local _search_once = nil
function MO:_SearchAndPrepareSandboxOptions()
	if _search_once then
		return
	end
	_search_once = true
	local struct = MO._sandbox_struct
	local vars = MO._sandbox_vars
	for _,chunk in pairs(OPTIONS_CHUNKS) do
		for _,v in pairs(chunk.options_data) do
			if v.sandbox_path then
				if vars[v.id] ~= nil then
					print('WARNING! Double sandbox name: ',v.id)
					print('Try to use more coplicated names for your options.')
				else
					local page = struct[v.sandbox_path]
					if not page then
						page = {}
						struct[v.sandbox_path] = page
					end
					page[v.id] = v
					vars[v.id] = v
					v._sandbox = v:getType() == "entry" and tostring(v.default) or v.default
				end
			end
		end
	end	
end

do
	local SettingsTable = {
		{ name = "INI", pages = nil},
		{ name = "Sandbox", pages = nil},
	}
	MO.SettingsTable = SettingsTable
	MO._sandbox_vars = {}
	MO._sandbox_struct = {}
	
	local cached = {}
	local cnt_sure, stage, old_ipairs = 0, 1
	local function new_ipairs(t)
		if stage > 2 then
			ipairs = old_ipairs
			table.wipe(cached)
			return ipairs(t)
		elseif cached[t] then
			return old_ipairs(t)
		elseif type(t[1]) == 'table' and t[1].settings then
			SettingsTable[stage].pages = t
			for _,v in old_ipairs(t) do
				cached[v.settings] = true
				v.__name = v.name
			end
			stage = stage + 1
		end
		return old_ipairs(t)
	end

	local old_new = ServerOptions.new
	function ServerOptions:new(...)
			old_ipairs = ipairs
			ipairs = new_ipairs
			return old_new(self, ...)
	end
end

return MO
