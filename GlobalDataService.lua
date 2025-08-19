--// Services
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local _Required = false

local GlobalDataService = {}
GlobalDataService.__index = GlobalDataService

local stocks = {}

local _onStockChangedCallbacks = {}
local _onStockForceChangeCallbacks = {}
local _onForcedStockExpiredCallbacks = {}

--// Constants
local _KEY_DATASTORE_NAME = "GlobalStockKeyStore"
local _KEY_DATASTORE_KEY = "GlobalStockKey_v1"
local _FORCED_STOCK_KEY = "ForcedNextStock"
local restockAnchorStore = DataStoreService:GetDataStore("GlobalRestockAnchor")
local _KEY_LENGTH = 16
local _MAX_UPDATE_ATTEMPTS = 5

local _SEED_ZERO_FALLBACK = 0xCAFEBABE
local _SEED_INITIAL_ZERO = 0xDEADBEEF
local _SEED_FALLBACK_OFFSET_1 = 99999
local _SEED_FALLBACK_OFFSET_2 = 88888
local _SEED_COUNT_OFFSET = 10000

--// Performance and monitoring constants
local _MIN_POLLING_INTERVAL = 0.5
local _MAX_POLLING_INTERVAL = 30
local _HEALTH_CHECK_INTERVAL = 60
local _MAX_CALLBACK_ERRORS = 10
local _MAX_EVENT_HISTORY = 100

local DAY_NAME_TO_ID = {
	sunday = 1,
	monday = 2,
	tuesday = 3,
	wednesday = 4,
	thursday = 5,
	friday = 6,
	saturday = 7
}

--// Debug config
local _debug = false
local _forcedLogLimit = 5
local _forcedLogCount = 0

--// Private
local _Version = "1.2.0"
local VERSION_URL = "https://raw.githubusercontent.com/V1nyI/roblox-GlobalDataService/refs/heads/main/Version.txt"

--// Global key cache
local _cachedGlobalKey = nil
local _fetchingGlobalKey = false
local _globalKeyLastFetch = 0
local _globalKeyFetchTimeout = 10

--// Performance monitoring
local _performanceMetrics = {
	stockUpdates = 0,
	callbackErrors = 0,
	lastHealthCheck = 0,
	activeStocks = 0
}

--// Event history for debugging
local _eventHistory = {}
local _eventHistoryIndex = 1

--// Logging Utility
local function _log(level, msg, force)
	if not _debug and not force then return end
	if force then
		if _forcedLogCount >= _forcedLogLimit then return end
		_forcedLogCount += 1
	end

	level = tostring(level):lower()
	if level == "warn" then
		warn("[GlobalDataService] "..tostring(msg))
	elseif level == "error" then
		error("[GlobalDataService] "..tostring(msg))
	else
		print("[GlobalDataService] "..tostring(msg))
	end
end

--// Event history logging
local function _logEvent(eventType, stockName, details)
	if #_eventHistory >= _MAX_EVENT_HISTORY then
		_eventHistory[_eventHistoryIndex] = nil
	else
		table.insert(_eventHistory, {
			timestamp = os.time(),
			type = eventType,
			stockName = stockName,
			details = details
		})
	end
end

local function CheckForUpdates(currentVersion)
	local success, response = pcall(function()
		return HttpService:GetAsync(VERSION_URL)
	end)

	if success then
		local remoteVersion = response:match("%S+")
		if remoteVersion and remoteVersion ~= currentVersion then
			warn("[GlobalDataService] A newer version is available: "..remoteVersion.." (current: "..currentVersion..")")
		else
			print("[GlobalDataService] You are using the latest version: "..currentVersion)
		end
	else
		warn("[GlobalDataService] Failed to check for updates.")
	end
end

if _Required == false then
	_Required = true
	CheckForUpdates(_Version)
end

local function _rol32(x, n)
	n = n % 32
	local left = bit32.lshift(x, n)
	local right = bit32.rshift(x, 32 - n)
	
	return bit32.band(bit32.bor(left, right), 0xFFFFFFFF)
end

local function _makeXorShift32(seed)
	local s = bit32.band(tonumber(seed) or 0, 0xFFFFFFFF)
	if s == 0 then s = _SEED_INITIAL_ZERO end
	
	return function()
		s = bit32.xor(s, bit32.lshift(s, 13))
		s = bit32.xor(s, bit32.rshift(s, 17))
		s = bit32.xor(s, bit32.lshift(s, 5))
		s = bit32.band(s, 0xFFFFFFFF)
		return s / 0x100000000
	end
end

local function _generateRandomKey()
	local rng = Random.new()
	local key = {}
	for i = 1, _KEY_LENGTH do
		key[i] = rng:NextInteger(0, 0x7FFFFFFF)
	end
	
	return key
end

local function _getOrCreateGlobalKeyFromDataStore()
	if _cachedGlobalKey then
		return _cachedGlobalKey
	end
	
	if _fetchingGlobalKey then
		-- Wait for existing fetch to complete
		local startTime = os.time()
		while _fetchingGlobalKey and (os.time() - startTime) < _globalKeyFetchTimeout do
			task.wait(0.1)
		end
		if _cachedGlobalKey then
			return _cachedGlobalKey
		end
	end
	
	_fetchingGlobalKey = true
	_globalKeyLastFetch = os.time()
	
	local store = DataStoreService:GetDataStore(_KEY_DATASTORE_NAME)
	for attempt = 1, _MAX_UPDATE_ATTEMPTS do
		local success, result = pcall(function()
			return store:UpdateAsync(_KEY_DATASTORE_KEY, function(oldValue)
				if oldValue and type(oldValue) == "table" and oldValue.numbers then
					return oldValue
				end
				return {
					numbers = _generateRandomKey(),
					created = os.time()
				}
			end)
		end)
		
		if success and type(result) == "table" and result.numbers then
			_log("info", "Global key obtained on attempt "..attempt, false)
			_cachedGlobalKey = result.numbers
			_fetchingGlobalKey = false
			return _cachedGlobalKey
		end
		task.wait(math.min(attempt, 5))
	end
	
	_log("warn", "Failed to obtain/create global key after retries", true)
	_fetchingGlobalKey = false
	return nil
end

local function _ensureGlobalKeyAsync()
	if _cachedGlobalKey then
		return _cachedGlobalKey
	end
	
	local key = _getOrCreateGlobalKeyFromDataStore()
	if key then
		return key
	end
	
	-- Only spawn retry if we're not already fetching
	if not _fetchingGlobalKey then
		task.spawn(function()
			task.wait(5)
			_getOrCreateGlobalKeyFromDataStore()
		end)
	end
	
	return nil
end

local function _forceRotateGlobalKey()
	local store = DataStoreService:GetDataStore(_KEY_DATASTORE_NAME) -- Fixed: was using wrong store name
	
	local success, result = pcall(function()
		return store:UpdateAsync(_KEY_DATASTORE_KEY, function()
			return {
				numbers = _generateRandomKey(),
				created = os.time()
			}
		end)
	end)
	
	if success and type(result) == "table" and result.numbers then
		_log("info", "Global key rotated successfully", false)
		_cachedGlobalKey = result.numbers
		return result.numbers
	end
	
	_log("warn", "Failed to rotate global key: "..tostring(result), true)
	return nil
end

local function getGlobalAnchor()
	local success, value = pcall(function()
		return restockAnchorStore:GetAsync("Anchor")
	end)
	
	if success and value then
		return value
	end
	
	local now = os.time()
	pcall(function()
		restockAnchorStore:SetAsync("Anchor", now)
	end)
	
	return now
end

local function _keyAndTimeToSeed(keyNumbers, restockTime)
	local seed = bit32.band(tonumber(restockTime) or os.time(), 0xFFFFFFFF)
	
	for i = 1, #keyNumbers do
		local num = keyNumbers[i] or 0
		local rotated = _rol32(bit32.band(num, 0xFFFFFFFF), i)
		seed = bit32.xor(seed, rotated)
		seed = bit32.band(seed + (num % 0x100000000), 0xFFFFFFFF)
	end
	
	if seed == 0 then seed = _SEED_ZERO_FALLBACK end
	return seed
end

--// Deterministic boundary helpers

local function computeDeterministicBoundary(anchor, stockName, interval)
	local hash = 0
	for i = 1, #stockName do
		hash = (hash + string.byte(stockName, i)) % interval
	end
	
	local now = os.time()
	return now - ((now - (anchor + hash)) % interval)
end

local function _getDeterministicRestockTime(stockData, currentTime)
	currentTime = currentTime or os.time()
	local interval = stockData.RESTOCK_INTERVAL or 100
	local globalKey = stockData.globalKey
	local stockName = stockData._stockName or "UnknownStock"
	
	return computeDeterministicBoundary(globalKey, stockName, interval)
end

--// MemoryStore access helpers for forced stock

local function _getMemoryStoreMap()
	return MemoryStoreService:GetSortedMap(_FORCED_STOCK_KEY)
end

local function _getForcedStockFromMemoryStore()
	local memStore = _getMemoryStoreMap()
	
	local success, data = pcall(function()
		return memStore:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	
	if success and data then
		local forcedStocks = {}
		
		for _, entry in ipairs(data) do
			if type(entry.value) == "table" and entry.key then
				forcedStocks[entry.key] = entry.value
			end
		end
		
		return forcedStocks
	end
	
	return nil
end

local function _saveForcedStockToMemoryStore(stockName, stockList, restocks)
	local memStore = _getMemoryStoreMap()
	
	local expiration = tonumber(restocks) or 1
	expiration = expiration * (stocks[stockName] and stocks[stockName].RESTOCK_INTERVAL or 600)
	
	pcall(function()
		memStore:SetAsync(stockName, stockList, expiration)
	end)
end

local function _clearForcedStockInMemoryStore(stockName)
	local memStore = _getMemoryStoreMap()
	
	pcall(function()
		memStore:RemoveAsync(stockName)
	end)
end

local function _getForcedStock(stockName)
	local map = _getMemoryStoreMap()
	
	local success, forcedStock = pcall(function()
		return map:GetAsync(stockName)
	end)
	
	if success and type(forcedStock) == "table" then
		return forcedStock
	end
	
	return nil
end

local function _callCallbacks(callbacks, stockName, oldStock, newStock, timer)
	local errorCount = 0
	for i = #callbacks, 1, -1 do
		local callback = callbacks[i]
		if callback and type(callback) == "function" then
			local ok, err = pcall(callback, stockName, oldStock, newStock, timer)
			
			if not ok then
				errorCount += 1
				_log("warn", "Stock callback error for '"..tostring(stockName).."': "..tostring(err), true)
				
				-- Remove problematic callbacks after too many errors
				if errorCount >= _MAX_CALLBACK_ERRORS then
					_log("warn", "Too many callback errors, removing callback", true)
					table.remove(callbacks, i)
				end
			end
		else
			-- Remove invalid callbacks
			table.remove(callbacks, i)
		end
	end
end

--// Predict stock based on seed and stock data
local function _predictStock(stockData, restockTime)
	assert(stockData.globalKey and type(stockData.globalKey) == "table", "Global key not set")
	
	local seed = _keyAndTimeToSeed(stockData.globalKey, restockTime)
	local rand = _makeXorShift32(seed)
	
	local candidates = {}
	
	for _, itemData in ipairs(stockData.stockItems) do
		if type(itemData) == "table" then
			local itemName = itemData.name
			if type(itemName) == "string" then
				local chance = math.clamp(tonumber(itemData.chance) or 100, 0, 100)
				local minAmount = math.max(1, tonumber(itemData.minAmount) or 1)
				local maxAmount = math.max(minAmount, tonumber(itemData.maxAmount) or minAmount)
				
				if rand() <= (chance / 100) then
					local amountRand = _makeXorShift32(seed + (#candidates + 1))
					local amount = minAmount
					if maxAmount > minAmount then
						amount = minAmount + math.floor(amountRand() * (maxAmount - minAmount + 1))
						amount = math.min(amount, maxAmount)
					end
					table.insert(candidates, {name = itemName, amount = amount})
				end
			end
		end
	end
	
	if #candidates == 0 and #stockData.stockItems > 0 then
		local fallbackRand = _makeXorShift32(seed + _SEED_FALLBACK_OFFSET_1)
		local idx = 1 + math.floor(fallbackRand() * #stockData.stockItems)
		idx = math.clamp(idx, 1, #stockData.stockItems)
		
		local fallbackItem = stockData.stockItems[idx]
		local minAmount = math.max(1, tonumber(fallbackItem.minAmount) or 1)
		local maxAmount = math.max(minAmount, tonumber(fallbackItem.maxAmount) or minAmount)
		
		local amount = minAmount
		if maxAmount > minAmount then
			local amountRand = _makeXorShift32(seed + _SEED_FALLBACK_OFFSET_2)
			amount = minAmount + math.floor(amountRand() * (maxAmount - minAmount + 1))
			amount = math.min(amount, maxAmount)
		end
		
		return {{name = fallbackItem.name or "Unknown", amount = amount}}
	end
	
	local minCount = math.max(1, math.min(stockData.minItems, #candidates))
	local maxCount = math.max(minCount, math.min(stockData.maxItems, #candidates))
	local countToReturn = minCount
	
	if maxCount > minCount then
		local randCount = _makeXorShift32(seed + _SEED_COUNT_OFFSET)
		countToReturn = minCount + math.floor(randCount() * (maxCount - minCount + 1))
		countToReturn = math.min(countToReturn, maxCount)
	end
	
	for i = #candidates, 2, -1 do
		local j = 1 + math.floor(rand() * i)
		candidates[i], candidates[j] = candidates[j], candidates[i]
	end
	
	local predictedStock = {}
	
	for i = 1, countToReturn do
		table.insert(predictedStock, candidates[i])
	end
	
	return predictedStock
end

local function _getCurrentRestockTime(stockData, currentTime)
	currentTime = currentTime or os.time()
	local interval = stockData.RESTOCK_INTERVAL or 100
	return currentTime - (currentTime % interval)
end

local function _isDayAllowed(stockData, now)
	if not stockData.allowedDays then return true end
	local currentDayId = tonumber(os.date("!%w", now)) + 1
	return stockData.allowedDays[currentDayId] == true
end

local function normalizeDayInput(day)
	if type(day) == "number" then
		assert(day >= 1 and day <= 7, "Day number must be 1-7")
		return day
	elseif type(day) == "string" then
		local lower = string.lower(day)
		assert(DAY_NAME_TO_ID[lower], "Invalid day name: "..tostring(day))
		return DAY_NAME_TO_ID[lower]
	else
		error("Day must be string or number")
	end
end

local function convertToTime(date)
	assert(type(date) == "table" and date.year and date.month and date.day, "Date must have at least {year, month, day}")
	
	local hour = date.hour or 0
	local min = date.min or date.minute or 0
	local sec = date.sec or date.second or 0
	local timezone = date.timezoneOffset or date.tzOffset or 0
	
	local timezoneSeconds = timezone * 3600
	
	local timestamp = os.time({
		year = date.year,
		month = date.month,
		day = date.day,
		hour = hour,
		min = min,
		sec = sec
	})
	
	return timestamp - timezoneSeconds
end

local function _isWithinDateRange(stockData, now)
	if not stockData.dateStart or not stockData.dateEnd then return true end
	return now >= stockData.dateStart and now <= stockData.dateEnd
end

local function stocksDifferent(a, b)
	if not a or not b then return true end
	if #a ~= #b then return true end
	for i = 1, #a do
		local ai, bi = a[i], b[i]
		if not bi or ai.name ~= bi.name or ai.amount ~= bi.amount then
			return true
		end
	end
	return false
end

--// Calculate next polling interval based on restock timing
local function _calculateNextPollingInterval(stockData, currentTime)
	if not stockData or not stockData.RESTOCK_INTERVAL then
		return _MIN_POLLING_INTERVAL
	end
	
	local nextRestock = _getCurrentRestockTime(stockData, currentTime) + stockData.RESTOCK_INTERVAL
	local timeUntilRestock = nextRestock - currentTime
	
	-- Poll more frequently as restock approaches
	if timeUntilRestock <= 10 then
		return _MIN_POLLING_INTERVAL
	elseif timeUntilRestock <= 60 then
		return math.max(_MIN_POLLING_INTERVAL, timeUntilRestock / 20)
	else
		return math.min(_MAX_POLLING_INTERVAL, timeUntilRestock / 10)
	end
end

local function _stockThread(stockName)
	local stockData = stocks[stockName]
	if not stockData then return end
	
	_performanceMetrics.activeStocks += 1
	
	while stockData._running do
		local now = os.time()
		local inDate = _isWithinDateRange(stockData, now)
		local inDays = _isDayAllowed(stockData, now)
		local inWindow = inDate and inDays
		
		if not inWindow then
			if stockData._currentStock and #stockData._currentStock > 0 then
				local oldStock = stockData._currentStock
				stockData._currentStock = {}
				_callCallbacks(_onStockChangedCallbacks, stockName, oldStock, {}, 0)
				_logEvent("stock_cleared", stockName, {reason = "out_of_window"})
				_log("info", "Stock '"..stockName.."' cleared (out of allowed window).", false)
			end
		else
			local forcedStock = _getForcedStock(stockName)
			if forcedStock then
				if stocksDifferent(stockData._currentStock, forcedStock) then
					local oldStock = stockData._currentStock
					stockData._currentStock = forcedStock
					_callCallbacks(_onStockForceChangeCallbacks, stockName, oldStock, forcedStock, 0)
					_logEvent("forced_stock_applied", stockName, {forcedStock = forcedStock})
					_performanceMetrics.stockUpdates += 1
				end
			else
				local newStock = GlobalDataService.GetCurrentStock(stockName) or {}
				if stocksDifferent(stockData._currentStock, newStock) then
					local oldStock = stockData._currentStock
					stockData._currentStock = newStock
					_callCallbacks(_onStockChangedCallbacks, stockName, oldStock, newStock, os.time())
					_logEvent("stock_updated", stockName, {oldStock = oldStock, newStock = newStock})
					_performanceMetrics.stockUpdates += 1
				end
			end
		end
		
		-- Smart polling based on restock timing
		local pollInterval = _calculateNextPollingInterval(stockData, now)
		task.wait(pollInterval)
	end
	
	_performanceMetrics.activeStocks -= 1
end

--// Health check and monitoring
local function _performHealthCheck()
	local now = os.time()
	if now - _performanceMetrics.lastHealthCheck < _HEALTH_CHECK_INTERVAL then
		return
	end
	
	_performanceMetrics.lastHealthCheck = now
	
	-- Check global key health
	if not _cachedGlobalKey and (now - _globalKeyLastFetch) > _globalKeyFetchTimeout then
		_log("warn", "Global key fetch timeout, attempting recovery", true)
		_ensureGlobalKeyAsync()
	end
	
	-- Log performance metrics
	if _debug then
		_log("info", string.format("Health Check - Active Stocks: %d, Updates: %d, Callback Errors: %d", 
			_performanceMetrics.activeStocks, 
			_performanceMetrics.stockUpdates, 
			_performanceMetrics.callbackErrors), false)
	end
end

--// Validation functions
local function _validateStockItems(stockItems)
	if type(stockItems) ~= "table" then
		return false, "stockItems must be a table"
	end
	
	for i, item in ipairs(stockItems) do
		if type(item) ~= "table" then
			return false, "Item " .. i .. " must be a table"
		end
		
		if type(item.name) ~= "string" then
			return false, "Item " .. i .. " must have a string name"
		end
		
		if item.chance and (type(item.chance) ~= "number" or item.chance < 0 or item.chance > 100) then
			return false, "Item " .. i .. " chance must be 0-100"
		end
		
		if item.minAmount and (type(item.minAmount) ~= "number" or item.minAmount < 1) then
			return false, "Item " .. i .. " minAmount must be >= 1"
		end
		
		if item.maxAmount and (type(item.maxAmount) ~= "number" or item.maxAmount < 1) then
			return false, "Item " .. i .. " maxAmount must be >= 1"
		end
		
		if item.minAmount and item.maxAmount and item.maxAmount < item.minAmount then
			return false, "Item " .. i .. " maxAmount must be >= minAmount"
		end
	end
	
	return true
end

--// Public API

--[[
	Creates and registers a new global stock configuration
	
	@param stockName string Unique name of the stock
	@param stockItems table List of items with chance, minAmount, maxAmount
	@param minItems number Minimum items to pick
	@param maxItems number Maximum items to pick
	@param restockInterval number Interval in seconds for stock refresh
	@param stockType string Optional stock type
	@param Info table Optional info for date/day restrictions
	@return table stockData or nil, string error
]]
function GlobalDataService.CreateStock(stockName, stockItems, minItems, maxItems, restockInterval, stockType, Info)
	-- Input validation
	if type(stockName) ~= "string" or stockName == "" then
		return nil, "stockName must be a non-empty string"
	end
	
	if type(stockItems) ~= "table" or #stockItems == 0 then
		return nil, "stockItems must be a non-empty table"
	end
	
	-- Validate stock items
	local isValid, errorMsg = _validateStockItems(stockItems)
	if not isValid then
		return nil, errorMsg
	end
	
	minItems = tonumber(minItems) or 1
	maxItems = tonumber(maxItems) or minItems
	restockInterval = tonumber(restockInterval) or 50
	stockType = stockType or "Normal"
	
	if minItems < 1 then
		return nil, "minItems must be >= 1"
	end
	
	if maxItems < minItems then
		return nil, "maxItems must be >= minItems"
	end
	
	if restockInterval < 1 then
		return nil, "restockInterval must be >= 1"
	end
	
	if stocks[stockName] then
		_log("warn", "Stock '"..stockName.."' already exists. Overwriting.", true)
	end
	
	local globalKey = _ensureGlobalKeyAsync()
	if not globalKey then
		task.spawn(function()
			task.wait(5)
			_ensureGlobalKeyAsync()
		end)
	end
	
	local stockData = {
		stockItems = stockItems,
		minItems = minItems,
		maxItems = maxItems,
		RESTOCK_INTERVAL = restockInterval,
		globalKey = globalKey,
		_currentStock = {},
		_running = true,
		_type = string.lower(stockType),
		_stockName = stockName,
		_created = os.time()
	}
	
	if stockType:lower() == "datelimited" or stockType:lower() == "dayofweeklimited" then
		-- DateLimited setup (Info.start / Info.end with {year,month,day})
		if Info and Info.start and Info["end"] then
			stockData.dateStart = convertToTime(Info.start)
			stockData.dateEnd   = convertToTime(Info["end"])
		end
		
		-- DayOfWeekLimited setup (Info.days = {"Monday", "Friday"})
		if Info and Info.days then
			stockData.allowedDays = {}
			for _, d in ipairs(Info.days) do
				local dayId = normalizeDayInput(d)
				stockData.allowedDays[dayId] = true
			end
		end
	end
	
	stocks[stockName] = stockData
	task.spawn(function()
		_stockThread(stockName)
	end)
	
	_logEvent("stock_created", stockName, {config = stockData})
	return stockData
end

--[[
	Gets the current stock list for a stock name
	
	@param stockName string
	@return table
]]
function GlobalDataService.GetCurrentStock(stockName)
	local stockData = stocks[stockName]
	if not stockData then return {} end
	
	local anchor = getGlobalAnchor()
	local restockTime = computeDeterministicBoundary(anchor, stockName, stockData.RESTOCK_INTERVAL)
	
	local predictedStock = _predictStock(stockData, restockTime)
	return predictedStock
end

--[[
	Gets the deterministic restock boundary and offset for a stock
	
	@param stockName string
	@return currentBoundary, offset
]]
function GlobalDataService.GetDeterministicBoundary(stockName)
	local stockData = stocks[stockName]
	if not stockData then
		return nil
	end
	local globalKey = stockData.globalKey or _ensureGlobalKeyAsync()
	if not globalKey then
		return nil
	end
	local interval = stockData.RESTOCK_INTERVAL or 100
	return computeDeterministicBoundary(globalKey, stockName, interval)
end

--[[
	Forces the next stock to be a specific list for a given number of restocks
	
	@param stockName string
	@param stockList table The stock items list to force
	@param restocks number Number of restocks before forced stock expires
	@return boolean success
]]
function GlobalDataService.ForceNextStock(stockName, stockList, restocks)
	assert(type(stockName) == "string", "stockName must be string")
	assert(type(stockList) == "table", "stockList must be table")
	
	restocks = tonumber(restocks) or 1
	
	local stockData = stocks[stockName]
	if not stockData then
		_log("warn", "ForceNextStock failed: Stock '"..stockName.."' does not exist", true)
		return false
	end
	
	-- Validate forced stock list
	local isValid, errorMsg = _validateStockItems(stockList)
	if not isValid then
		_log("warn", "ForceNextStock failed: " .. errorMsg, true)
		return false
	end
	
	_saveForcedStockToMemoryStore(stockName, stockList, restocks)
	
	local oldStock = stockData._currentStock
	stockData._currentStock = stockList
	_callCallbacks(_onStockForceChangeCallbacks, stockName, oldStock, stockList, 0)
	
	_logEvent("forced_stock_set", stockName, {forcedStock = stockList, restocks = restocks})
	_log("info", "Forced stock set for '"..stockName.."' with expiration in "..tostring(restocks).." restocks", false)
	return true
end

--[[
	Clears forced stock override for a stock name
	
	@param stockName string
	@return boolean success
]]
function GlobalDataService.ClearForcedStock(stockName)
	assert(type(stockName) == "string", "stockName must be string")
	
	local stockData = stocks[stockName]
	if not stockData then
		return false
	end
	
	_clearForcedStockInMemoryStore(stockName)
	_logEvent("forced_stock_cleared", stockName, {})
	_log("info", "Forced stock cleared for '"..stockName.."'", false)
	return true
end

--[[
	Subscribe to stock changed events (normal stock changes)
	
	@param callback function(stockName, oldStock, newStock, restockTime)
	@return function unsubscribe function
]]
function GlobalDataService.OnStockChanged(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onStockChangedCallbacks + 1
	_onStockChangedCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onStockChangedCallbacks[callbackId] == callback then
			_onStockChangedCallbacks[callbackId] = nil
		end
	end
end

--[[
	Subscribe to forced stock changed events
	
	@param callback function(stockName, oldStock, newStock, timer)
	@return function unsubscribe function
]]
function GlobalDataService.OnStockForceChanged(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onStockForceChangeCallbacks + 1
	_onStockForceChangeCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onStockForceChangeCallbacks[callbackId] == callback then
			_onStockForceChangeCallbacks[callbackId] = nil
		end
	end
end

--[[
	Subscribe to forced stock expiration events
	
	@param callback function(stockName)
	@return function unsubscribe function
]]
function GlobalDataService.OnForcedStockExpired(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onForcedStockExpiredCallbacks + 1
	_onForcedStockExpiredCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onForcedStockExpiredCallbacks[callbackId] == callback then
			_onForcedStockExpiredCallbacks[callbackId] = nil
		end
	end
end

--[[
	Rotates the global key manually
	
	@return boolean success, newKey or error string
]]
function GlobalDataService.ForceRotateGlobalKey()
	local newKey = _forceRotateGlobalKey()
	
	if newKey then
		_cachedGlobalKey = newKey
		for name, stockData in pairs(stocks) do
			stockData.globalKey = newKey
		end
		_logEvent("global_key_rotated", "system", {newKey = newKey})
		return true, newKey
	end
	
	return false, "Failed to rotate global key"
end

--[[
	Stops a stock update loop cleanly
	
	@param stockName string
	@return boolean success
]]
function GlobalDataService.StopStock(stockName)
	local stockData = stocks[stockName]
	if stockData then
		stockData._running = false
		_logEvent("stock_stopped", stockName, {})
		return true
	end
	return false
end

--[[
	Stops all stocks and cleans up resources
	
	@return boolean success
]]
function GlobalDataService.StopAllStocks()
	for stockName, stockData in pairs(stocks) do
		stockData._running = false
	end
	
	-- Clear all callbacks
	_onStockChangedCallbacks = {}
	_onStockForceChangeCallbacks = {}
	_onForcedStockExpiredCallbacks = {}
	
	_logEvent("all_stocks_stopped", "system", {})
	_log("info", "All stocks stopped and callbacks cleared", true)
	return true
end

--[[
	Enables or disables debug logging globally
	
	@param enabled boolean
	@return boolean success, string message
]]
function GlobalDataService.SetDebug(enabled)
	if not RunService:IsStudio() then
		warn("Debug can only be set in Studio")
		return false, "Debug can only be set in Studio"
	end
	_debug = enabled and true or false
	if _debug then
		_log("info", "Debug logging enabled", true)
	end
	return true, "Debug logging " .. (_debug and "enabled" or "disabled")
end

--[[
	Gets performance metrics and health information
	
	@return table metrics
]]
function GlobalDataService.GetPerformanceMetrics()
	return {
		activeStocks = _performanceMetrics.activeStocks,
		totalStocks = #stocks,
		stockUpdates = _performanceMetrics.stockUpdates,
		callbackErrors = _performanceMetrics.callbackErrors,
		lastHealthCheck = _performanceMetrics.lastHealthCheck,
		globalKeyStatus = _cachedGlobalKey and "healthy" or "unhealthy",
		version = _Version
	}
end

--[[
	Gets recent event history for debugging
	
	@param limit number Maximum number of events to return
	@return table events
]]
function GlobalDataService.GetEventHistory(limit)
	limit = tonumber(limit) or _MAX_EVENT_HISTORY
	limit = math.min(limit, #_eventHistory)
	
	local events = {}
	for i = #_eventHistory - limit + 1, #_eventHistory do
		if _eventHistory[i] then
			table.insert(events, _eventHistory[i])
		end
	end
	
	return events
end

--[[
	Bulk operations for managing multiple stocks
	
	@param operations table List of operations to perform
	@return table results
]]
function GlobalDataService.BulkOperation(operations)
	if type(operations) ~= "table" then
		return nil, "Operations must be a table"
	end
	
	local results = {}
	
	for i, operation in ipairs(operations) do
		local success, result, errorMsg
		
		if operation.action == "create" then
			success, result = GlobalDataService.CreateStock(
				operation.stockName,
				operation.stockItems,
				operation.minItems,
				operation.maxItems,
				operation.restockInterval,
				operation.stockType,
				operation.info
			)
			if not success then
				errorMsg = result
			end
		elseif operation.action == "stop" then
			success = GlobalDataService.StopStock(operation.stockName)
			result = success
		elseif operation.action == "force" then
			success = GlobalDataService.ForceNextStock(
				operation.stockName,
				operation.stockList,
				operation.restocks
			)
			result = success
		else
			success = false
			errorMsg = "Unknown operation: " .. tostring(operation.action)
		end
		
		results[i] = {
			action = operation.action,
			stockName = operation.stockName,
			success = success,
			result = result,
			error = errorMsg
		}
	end
	
	return results
end

--[[
	Validates a stock configuration without creating it
	
	@param stockItems table
	@param minItems number
	@param maxItems number
	@param restockInterval number
	@return boolean isValid, string errorMessage
]]
function GlobalDataService.ValidateStockConfig(stockItems, minItems, maxItems, restockInterval)
	if type(stockItems) ~= "table" or #stockItems == 0 then
		return false, "stockItems must be a non-empty table"
	end
	
	local isValid, errorMsg = _validateStockItems(stockItems)
	if not isValid then
		return false, errorMsg
	end
	
	minItems = tonumber(minItems) or 1
	maxItems = tonumber(maxItems) or minItems
	restockInterval = tonumber(restockInterval) or 50
	
	if minItems < 1 then
		return false, "minItems must be >= 1"
	end
	
	if maxItems < minItems then
		return false, "maxItems must be >= minItems"
	end
	
	if restockInterval < 1 then
		return false, "restockInterval must be >= 1"
	end
	
	return true
end

--[[
	Gets information about a specific stock
	
	@param stockName string
	@return table stockInfo or nil
]]
function GlobalDataService.GetStockInfo(stockName)
	local stockData = stocks[stockName]
	if not stockData then
		return nil
	end
	
	return {
		name = stockName,
		type = stockData._type,
		restockInterval = stockData.RESTOCK_INTERVAL,
		minItems = stockData.minItems,
		maxItems = stockData.maxItems,
		currentStock = stockData._currentStock,
		created = stockData._created,
		running = stockData._running,
		allowedDays = stockData.allowedDays,
		dateStart = stockData.dateStart,
		dateEnd = stockData.dateEnd
	}
end

--[[
	Gets a list of all registered stock names
	
	@return table stockNames
]]
function GlobalDataService.GetAllStockNames()
	local names = {}
	for stockName, _ in pairs(stocks) do
		table.insert(names, stockName)
	end
	return names
end

--// Start health check loop
task.spawn(function()
	while true do
		_performHealthCheck()
		task.wait(_HEALTH_CHECK_INTERVAL)
	end
end)

return GlobalDataService