--[[
	ItemSearch
		An item text search engine of some sort
		
	Grammar:
		<search> 			:=	<intersect search>
		<intersect search> 	:=	<union search> & <union search> ; <union search>
		<union search>		:=	<negatable search>  | <negatable search> ; <negatable search>
		<negatable search> 	:=	!<primitive search> ; <primitive search>
		<primitive search>	:=	<tooltip search> ; <quality search> ; <type search> ; <text search>
		<tooltip search>	:=  bop ; boa ; bou ; boe ; quest
		<quality search>	:=	q<op><text> ; q<op><digit>
		<ilvl search>		:=	ilvl<op><number>
		<type search>		:=	t:<text>
		<text search>		:=	<text>
		<item set search>	:=	s:<setname> (setname can be * for all sets)
		<op>				:=  : | = | == | != | ~= | < | > | <= | >=
--]]

local Lib = LibStub:NewLibrary('LibItemSearch-1.1', 1)
if not Lib then
  return
else
  Lib.searchTypes = Lib.searchTypes or {}
end


--[[ Locals ]]--

local tonumber, select, split = tonumber, select, strsplit
local function useful(a) -- check if the search has a decent size
  return a and #a >= 1
end

local function compare(op, a, b)
	if op == '<=' then
		return a <= b
	end

	if op == '<' then
		return a < b
	end

	if op == '>' then
		return a > b
	end

	if op == '>=' then
		return a >= b
	end

	return a == b
end

local function match(search, ...)
  for i = 1, select('#', ...) do
    local text = select(i, ...)
    if text and text:lower():find(search) then
      return true
    end
  end
  return false
end


--[[ User API ]]--

function Lib:Matches(link, search)
	if link then
		return not useful(search) or self:FindUnionSearch(link, split('\124', search:lower()))
	end
end

function Lib:InSet(link, search)
	if IsEquippableItem(link) then
		local id = tonumber(link:match('item:(%-?%d+)'))
		return self:BelongsToSet(id, search or '')
	end
end


--[[ Top-Layer Processing ]]--

-- union search: <search>&<search>
function Lib:FindUnionSearch(item, ...)
	for i = 1, select('#', ...) do
		local search = select(i, ...)
		if useful(search) and self:FindIntersectSearch(item, split('\038', search)) then
      		return true
		end
	end
end


-- intersect search: <search>|<search>
function Lib:FindIntersectSearch(item, ...)
	for i = 1, select('#', ...) do
		local search = select(i, ...)
		if useful(search) and not self:FindNegatableSearch(item, search) then
        	return
		end
	end

	return true
end


-- negated search: !<search>
function Lib:FindNegatableSearch(item, search)
  local negatedSearch = search:match('^[!~][%s]*(.+)$')
  if negatedSearch then
    return not self:FindTypedSearch(item, negatedSearch)
  end
  return self:FindTypedSearch(item, search, true)
end


--[[
     Search Types:
      easly defined search types

      A typed search object should look like the following:
        {
          string id
            unique identifier for the search type,

          string searchCapture = function canSearch(self, search)
            returns a capture if the given search matches this typed search

          bool isMatch = function findItem(self, itemLink, searchCapture)
            returns true if <itemLink> is in the search defined by <searchCapture>
          }
--]]

function Lib:RegisterTypedSearch(object)
	self.searchTypes[object.id] = object
end

function Lib:GetTypedSearches()
	return pairs(self.searchTypes)
end

function Lib:GetTypedSearch(id)
	return self.searchTypes[id]
end

function Lib:FindTypedSearch(item, search, default)
  if not useful(search) then
    return default
  end

  local tag, rest = search:match('^[%s]*(%w+):(.*)$')
  if tag then
    if useful(rest) then
      search = rest
    else
      return default
    end
  end

  local operator, search = search:match('^[%s]*([%>%<%=]*)[%s]*(.*)$')
  if useful(search) then
    operator = useful(operator) and operator
  else
    return default
  end

  if tag then
    tag = '^' .. tag
    for id, searchType in self:GetTypedSearches() do
      if searchType.tags then
        for _, value in pairs(searchType.tags) do
          if value:find(tag) then
            return self:UseTypedSearch(searchType, item, operator, search)
          end
        end
      end
    end
  else
    for id, searchType in self:GetTypedSearches() do
      if not searchType.onlyTags and self:UseTypedSearch(searchType, item, operator, search) then
        return true
      end
    end
    return false
  end

  return default
end

function Lib:UseTypedSearch(searchType, item, operator, search)
  local capture1, capture2, capture3 = searchType:canSearch(operator, search)
  if capture1 then
    if searchType:findItem(item, operator, capture1, capture2, capture3) then
      return true
    end
  end
end


--[[ Item name ]]--

Lib:RegisterTypedSearch{
  id = 'itemName',
  tags = {'n', 'name'},

	canSearch = function(self, operator, search)
		return not operator and search
	end,

	findItem = function(self, item, _, search)
		local name = item:match('%[(.-)%]')
		return match(search, name)
	end
}


--[[ Item type, subtype and equiploc ]]--

Lib:RegisterTypedSearch{
	id = 'itemType',
	tags = {'t', 'type', 'slot'},

	canSearch = function(self, operator, search)
		return not operator and search
	end,

	findItem = function(self, item, _, search)
		local type, subType, _, equipSlot = select(6, GetItemInfo(item))
		return match(search, type, subType, _G[equipSlot])
	end
}


--[[ Item quality ]]--

local qualities = {}
for i = 0, #ITEM_QUALITY_COLORS do
  qualities[i] = _G['ITEM_QUALITY' .. i .. '_DESC']:lower()
end

Lib:RegisterTypedSearch{
	id = 'itemQuality',
	tags = {'q', 'quality'},

	canSearch = function(self, _, search)
		for i, name in pairs(qualities) do
		  if name:find(search) then
			return i
		  end
		end
	end,

	findItem = function(self, link, operator, num)
		local quality = select(3, GetItemInfo(link))
		return compare(operator, quality, num)
	end,
}


--[[ Item level ]]--

Lib:RegisterTypedSearch{
	id = 'itemLevel',
	tags = {'l', 'level', 'lvl'},

	canSearch = function(self, _, search)
		return tonumber(search)
	end,

	findItem = function(self, link, operator, num)
		local lvl = select(4, GetItemInfo(link))
		if lvl then
			return compare(operator, lvl, num)
		end
	end,
}


--[[ Tooltip searches ]]--

local tooltipCache = setmetatable({}, {__index = function(t, k) local v = {} t[k] = v return v end})
local tooltipScanner = _G['LibItemSearchTooltipScanner'] or CreateFrame('GameTooltip', 'LibItemSearchTooltipScanner', UIParent, 'GameTooltipTemplate')

local function link_FindSearchInTooltip(itemLink, search)
	local itemID = itemLink:match('item:(%d+)')
	if not itemID then
		return
	end
	
	local cachedResult = tooltipCache[search][itemID]
	if cachedResult ~= nil then
		return cachedResult
	end

	tooltipScanner:SetOwner(UIParent, 'ANCHOR_NONE')
	tooltipScanner:SetHyperlink(itemLink)

	local result = false
	if tooltipScanner:NumLines() > 1 and _G[tooltipScanner:GetName() .. 'TextLeft2']:GetText() == search then
		result = true
	elseif tooltipScanner:NumLines() > 2 and _G[tooltipScanner:GetName() .. 'TextLeft3']:GetText() == search then
		result = true
	end

	tooltipCache[search][itemID] = result
	return result
end


Lib:RegisterTypedSearch{
	id = 'bindType',

	canSearch = function(self, _, search)
		return self.keywords[search]
	end,

	findItem = function(self, itemLink, _, search)
		return search and link_FindSearchInTooltip(itemLink, search)
	end,

	keywords = {
    	['soulbound'] = ITEM_BIND_ON_PICKUP,
    	['bound'] = ITEM_BIND_ON_PICKUP,
		['boe'] = ITEM_BIND_ON_EQUIP,
		['bop'] = ITEM_BIND_ON_PICKUP,
		['bou'] = ITEM_BIND_ON_USE,
		['quest'] = ITEM_BIND_QUEST,
		['boa'] = ITEM_BIND_TO_BNETACCOUNT
	}
}

Lib:RegisterTypedSearch{
	id = 'tooltip',
	tags = {'tt', 'tip', 'tooltip'},
	onlyTags = true,

	canSearch = function(self, _, search)
		return search
	end,

	findItem = function(self, link, _, search)
		tooltipScanner:SetOwner(UIParent, 'ANCHOR_NONE')
		tooltipScanner:SetHyperlink(link)

		for i = 1, tooltipScanner:NumLines() do
			local text =  _G[tooltipScanner:GetName() .. 'TextLeft' .. i]:GetText():lower()
			
			if text:find(search) then
				return true
			end
		end

		return false
	end,
}


--[[ Equipment sets ]]--

if IsAddOnLoaded('ItemRack') then
	local sameID = ItemRack.SameID

	function Lib:BelongsToSet(id, search)
		for name, set in pairs(ItemRackUser.Sets) do
			if name:sub(1,1) ~= '' and name:lower():match(search) then
				for _, item in pairs(set.equip) do
					if sameID(id, item) then
						return true
					end
				end
			end
		end
	end

elseif IsAddOnLoaded('Wardrobe') then
	function Lib:BelongsToSet(id, search)
		for _, outfit in ipairs(Wardrobe.CurrentConfig.Outfit) do
			local name = outfit.OutfitName:lower()
			if name:match(search) then
				for _, item in pairs(outfit.Item) do
					if item.IsSlotUsed == 1 and item.ItemID == id then
						return true
					end
				end
			end
		end
	end

else
	function Lib:BelongsToSet(id, search)
		for i = 1, GetNumEquipmentSets() do
			local name = GetEquipmentSetInfo(i)
			if name:lower():match(search) then
				local items = GetEquipmentSetItemIDs(name)
				for _, item in pairs(items) do
					if id == item then
						return true
					end
				end
			end
		end
	end
end

Lib:RegisterTypedSearch{
	id = 'equipmentSet',
	tags = {'s', 'set'},

	canSearch = function(self, operator, search)
		return not operator and search
	end,

	findItem = function(self, link, _, search)
		return Lib:InSet(link, search)
	end,
}