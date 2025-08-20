--// Services
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")

local _Required = false

local GlobalDataService = {}
GlobalDataService.__index = GlobalDataService

local datas = {}

local _onDataChangedCallbacks = {}
local _onDataForceChangeCallbacks = {}
local _onForcedDataExpiredCallbacks = {}

--// Constants
local _KEY_DATASTORE_NAME = "GlobalDataKeyStore"
local _KEY_DATASTORE_KEY = "GlobalDataKey_v1"
local _FORCED_DATA_KEY = "ForcedNextData"
local _BACKUP_DATASTORE_NAME = "GlobalDataBackupStore"
local _CONFIG_DATASTORE_NAME = "GlobalDataConfigStore"
local restockAnchorStore = DataStoreService:GetDataStore("GlobalRestockAnchor")
local backupStore = DataStoreService:GetDataStore(_BACKUP_DATASTORE_NAME)
local configStore = DataStoreService:GetDataStore(_CONFIG_DATASTORE_NAME)
local _KEY_LENGTH = 16
local _MAX_UPDATE_ATTEMPTS = 5
local _MAX_BACKUP_ATTEMPTS = 3
local _BACKUP_RETENTION_DAYS = 30

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

--// Performance optimization constants
local _CACHE_ENABLED = true
local _CACHE_TTL = 300 -- 5 minutes
local _PRELOAD_ENABLED = false
local _OPTIMIZATION_STRATEGIES = {
	AGGRESSIVE = "aggressive",
	BALANCED = "balanced",
	CONSERVATIVE = "conservative"
}

local DAY_NAME_TO_ID = {
	sunday = 1,
	monday = 2,
	tuesday = 3,
	wednesday = 4,
	thursday = 5,
	friday = 6,
	saturday = 7
}

--// Advanced scheduling constants
local _TIMEZONE_OFFSETS = {
	UTC = 0,
	EST = -5,
	PST = -8,
	GMT = 0,
	JST = 9
}

local _SEASONS = {
	spring = {start = {month = 3, day = 20}, ["end"] = {month = 6, day = 20}},
	summer = {start = {month = 6, day = 21}, ["end"] = {month = 9, day = 22}},
	autumn = {start = {month = 9, day = 23}, ["end"] = {month = 12, day = 20}},
	winter = {start = {month = 12, day = 21}, ["end"] = {month = 3, day = 19}}
}

local _HOLIDAYS = {
	christmas = {month = 12, day = 25},
	newyear = {month = 1, day = 1},
	halloween = {month = 10, day = 31},
	easter = {month = 4, day = 1} -- Simplified, actual Easter calculation is complex
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
	dataUpdates = 0,
	callbackErrors = 0,
	lastHealthCheck = 0,
	activeDatas = 0
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
local function _logEvent(eventType, dataName, details)
	if #_eventHistory >= _MAX_EVENT_HISTORY then
		_eventHistory[_eventHistoryIndex] = nil
	else
		table.insert(_eventHistory, {
			timestamp = os.time(),
			type = eventType,
			dataName = dataName,
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

local function computeDeterministicBoundary(anchor, dataName, interval)
	local hash = 0
	for i = 1, #dataName do
		hash = (hash + string.byte(dataName, i)) % interval
	end
	
	local now = os.time()
	return now - ((now - (anchor + hash)) % interval)
end

local function _getDeterministicRestockTime(dataItem, currentTime)
	currentTime = currentTime or os.time()
	local interval = dataItem.RESTOCK_INTERVAL or 100
	local globalKey = dataItem.globalKey
	local dataName = dataItem._dataName or "UnknownData"
	
	return computeDeterministicBoundary(globalKey, dataName, interval)
end

--// MemoryStore access helpers for forced data

local function _getMemoryStoreMap()
	return MemoryStoreService:GetSortedMap(_FORCED_DATA_KEY)
end

local function _getForcedDataFromMemoryStore()
	local memStore = _getMemoryStoreMap()
	
	local success, data = pcall(function()
		return memStore:GetRangeAsync(Enum.SortDirection.Ascending, 100)
	end)
	
	if success and data then
		local forcedDatas = {}
		
		for _, entry in ipairs(data) do
			if type(entry.value) == "table" and entry.key then
				forcedDatas[entry.key] = entry.value
			end
		end
		
		return forcedDatas
	end
	
	return nil
end

local function _saveForcedDataToMemoryStore(dataName, dataList, restocks)
	local memStore = _getMemoryStoreMap()
	
	local expiration = tonumber(restocks) or 1
	expiration = expiration * (datas[dataName] and datas[dataName].RESTOCK_INTERVAL or 600)
	
	pcall(function()
		memStore:SetAsync(dataName, dataList, expiration)
	end)
end

local function _clearForcedDataInMemoryStore(dataName)
	local memStore = _getMemoryStoreMap()
	
	pcall(function()
		memStore:RemoveAsync(dataName)
	end)
end

local function _getForcedData(dataName)
	local map = _getMemoryStoreMap()
	
	local success, forcedData = pcall(function()
		return map:GetAsync(dataName)
	end)
	
	if success and type(forcedData) == "table" then
		return forcedData
	end
	
	return nil
end

local function _callCallbacks(callbacks, dataName, oldData, newData, timer)
	local errorCount = 0
	for i = #callbacks, 1, -1 do
		local callback = callbacks[i]
		if callback and type(callback) == "function" then
			local ok, err = pcall(callback, dataName, oldData, newData, timer)
			
			if not ok then
				errorCount += 1
				_log("warn", "Data callback error for '"..tostring(dataName).."': "..tostring(err), true)
				
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

--// Predict data based on seed and data data
local function _predictData(dataItem, restockTime)
	assert(dataItem.globalKey and type(dataItem.globalKey) == "table", "Global key not set")
	
	local seed = _keyAndTimeToSeed(dataItem.globalKey, restockTime)
	local rand = _makeXorShift32(seed)
	
	local candidates = {}
	
	for _, itemData in ipairs(dataItem.dataItems) do
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
	
	if #candidates == 0 and #dataItem.dataItems > 0 then
		local fallbackRand = _makeXorShift32(seed + _SEED_FALLBACK_OFFSET_1)
		local idx = 1 + math.floor(fallbackRand() * #dataItem.dataItems)
		idx = math.clamp(idx, 1, #dataItem.dataItems)
		
		local fallbackItem = dataItem.dataItems[idx]
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
	
	local minCount = math.max(1, math.min(dataItem.minItems, #candidates))
	local maxCount = math.max(minCount, math.min(dataItem.maxItems, #candidates))
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
	
	local predictedData = {}
	
	for i = 1, countToReturn do
		table.insert(predictedData, candidates[i])
	end
	
	return predictedData
end

local function _getCurrentRestockTime(dataItem, currentTime)
	currentTime = currentTime or os.time()
	local interval = dataItem.RESTOCK_INTERVAL or 100
	return currentTime - (currentTime % interval)
end

local function _isDayAllowed(dataItem, now)
	if not dataItem.allowedDays then return true end
	local currentDayId = tonumber(os.date("!%w", now)) + 1
	return dataItem.allowedDays[currentDayId] == true
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

local function _isWithinDateRange(dataItem, now)
	if not dataItem.dateStart or not dataItem.dateEnd then return true end
	return now >= dataItem.dateStart and now <= dataItem.dateEnd
end

local function datasDifferent(a, b)
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
local function _calculateNextPollingInterval(dataItem, currentTime)
	if not dataItem or not dataItem.RESTOCK_INTERVAL then
		return _MIN_POLLING_INTERVAL
	end
	
	local nextRestock = _getCurrentRestockTime(dataItem, currentTime) + dataItem.RESTOCK_INTERVAL
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

local function _dataThread(dataName)
	local dataItem = datas[dataName]
	if not dataItem then return end
	
	_performanceMetrics.activeDatas += 1
	
	while dataItem._running do
		local now = os.time()
		local inDate = _isWithinDateRange(dataItem, now)
		local inDays = _isDayAllowed(dataItem, now)
		local inAdvancedTime = _isWithinAdvancedTimeRestrictions(dataItem, now)
		local inWindow = inDate and inDays and inAdvancedTime
		
		if not inWindow then
			if dataItem._currentData and #dataItem._currentData > 0 then
				local oldData = dataItem._currentData
				dataItem._currentData = {}
				_callCallbacks(_onDataChangedCallbacks, dataName, oldData, {}, 0)
				_logEvent("data_cleared", dataName, {reason = "out_of_window"})
				_log("info", "Data '"..dataName.."' cleared (out of allowed window).", false)
			end
		else
			local forcedData = _getForcedData(dataName)
			if forcedData then
				if datasDifferent(dataItem._currentData, forcedData) then
					local oldData = dataItem._currentData
					dataItem._currentData = forcedData
					_callCallbacks(_onDataForceChangeCallbacks, dataName, oldData, forcedData, 0)
					_logEvent("forced_data_applied", dataName, {forcedData = forcedData})
					_performanceMetrics.dataUpdates += 1
				end
			else
				local newData = GlobalDataService.GetCurrentData(dataName) or {}
				if datasDifferent(dataItem._currentData, newData) then
					local oldData = dataItem._currentData
					dataItem._currentData = newData
					_callCallbacks(_onDataChangedCallbacks, dataName, oldData, newData, os.time())
					_logEvent("data_updated", dataName, {oldData = oldData, newData = newData})
					_performanceMetrics.dataUpdates += 1
				end
			end
		end
		
		-- Smart polling based on restock timing with optimization
		local pollInterval = _optimizePollingInterval(dataItem, now)
		task.wait(pollInterval)
	end
	
	_performanceMetrics.activeDatas -= 1
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
		_log("info", string.format("Health Check - Active Datas: %d, Updates: %d, Callback Errors: %d", 
			_performanceMetrics.activeDatas, 
			_performanceMetrics.dataUpdates, 
			_performanceMetrics.callbackErrors), false)
	end
end

--// Validation functions
local function _validateDataItems(dataItems)
	if type(dataItems) ~= "table" then
		return false, "dataItems must be a table"
	end
	
	for i, item in ipairs(dataItems) do
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

--// Utility helper functions
local function _getTableKeys(t)
	local keys = {}
	for k, _ in pairs(t) do
		table.insert(keys, k)
	end
	return keys
end

--// Advanced Scheduling and Time Management Functions

local function _isWithinTimeWindow(dataItem, now)
	if not dataItem.timeWindow then return true end
	
	local hour = tonumber(os.date("!%H", now))
	local startHour = dataItem.timeWindow.startHour or 0
	local endHour = dataItem.timeWindow.endHour or 23
	
	if startHour <= endHour then
		return hour >= startHour and hour <= endHour
	else
		-- Handles cases like 22:00 to 06:00 (overnight)
		return hour >= startHour or hour <= endHour
	end
end

local function _isWithinSeason(dataItem, now)
	if not dataItem.seasons then return true end
	
	local month = tonumber(os.date("!%m", now))
	local day = tonumber(os.date("!%d", now))
	
	for seasonName, _ in pairs(dataItem.seasons) do
		local season = _SEASONS[seasonName]
		if season then
			local startDate = season.start
			local endDate = season["end"]
			
			-- Check if current date falls within season
			if startDate.month < endDate.month then
				-- Same year season (e.g., spring)
				if (month > startDate.month or (month == startDate.month and day >= startDate.day)) and
				   (month < endDate.month or (month == endDate.month and day <= endDate.day)) then
					return true
				end
			else
				-- Cross-year season (e.g., winter)
				if (month > startDate.month or (month == startDate.month and day >= startDate.day)) or
				   (month < endDate.month or (month == endDate.month and day <= endDate.day)) then
					return true
				end
			end
		end
	end
	
	return false
end

local function _isHoliday(dataItem, now)
	if not dataItem.holidays then return false end
	
	local month = tonumber(os.date("!%m", now))
	local day = tonumber(os.date("!%d", now))
	
	for holidayName, _ in pairs(dataItem.holidays) do
		local holiday = _HOLIDAYS[holidayName]
		if holiday and holiday.month == month and holiday.day == day then
			return true
		end
	end
	
	return false
end

local function _isWithinCustomSchedule(dataItem, now)
	if not dataItem.customSchedule then return true end
	
	local weekday = tonumber(os.date("!%w", now))
	local hour = tonumber(os.date("!%H", now))
	local minute = tonumber(os.date("!%M", now))
	local currentTime = hour * 60 + minute
	
	local daySchedule = dataItem.customSchedule[weekday]
	if not daySchedule then return false end
	
	for _, timeSlot in ipairs(daySchedule) do
		local startTime = timeSlot.start * 60 -- Convert to minutes
		local endTime = timeSlot["end"] * 60
		
		if currentTime >= startTime and currentTime <= endTime then
			return true
		end
	end
	
	return false
end

local function _convertTimezone(time, timezone)
	if not timezone or timezone == "UTC" then return time end
	
	local offset = _TIMEZONE_OFFSETS[timezone]
	if not offset then return time end
	
	return time + (offset * 3600)
end

local function _isWithinAdvancedTimeRestrictions(dataItem, now)
	-- Check all time-based restrictions
	local inTimeWindow = _isWithinTimeWindow(dataItem, now)
	local inSeason = _isWithinSeason(dataItem, now)
	local isHoliday = _isHoliday(dataItem, now)
	local inCustomSchedule = _isWithinCustomSchedule(dataItem, now)
	
	-- Apply holiday exceptions
	if dataItem.holidayExceptions and isHoliday then
		return dataItem.holidayExceptions.allowOnHoliday or false
	end
	
	-- All restrictions must pass
	return inTimeWindow and inSeason and inCustomSchedule
end

--// Performance Optimization and Cache Management Functions

local _dataCache = {}
local _cacheTimestamps = {}
local _optimizationSettings = {
	strategy = _OPTIMIZATION_STRATEGIES.BALANCED,
	preloadEnabled = _PRELOAD_ENABLED,
	cacheEnabled = _CACHE_ENABLED
}

local function _clearExpiredCache()
	local currentTime = os.time()
	local expiredKeys = {}
	
	for key, timestamp in pairs(_cacheTimestamps) do
		if currentTime - timestamp > _CACHE_TTL then
			expiredKeys[key] = true
		end
	end
	
	for key, _ in pairs(expiredKeys) do
		_dataCache[key] = nil
		_cacheTimestamps[key] = nil
	end
	
	if #_getTableKeys(expiredKeys) > 0 then
		_log("info", "Cleared "..#_getTableKeys(expiredKeys).." expired cache entries", false)
	end
end

local function _getCachedData(dataName)
	if not _optimizationSettings.cacheEnabled then return nil end
	
	_clearExpiredCache()
	return _dataCache[dataName]
end

local function _setCachedData(dataName, data)
	if not _optimizationSettings.cacheEnabled then return end
	
	_dataCache[dataName] = data
	_cacheTimestamps[dataName] = os.time()
end

local function _preloadData(dataName)
	if not _optimizationSettings.preloadEnabled then return end
	
	local dataItem = datas[dataName]
	if not dataItem then return end
	
	-- Preload the next predicted data
	local anchor = getGlobalAnchor()
	local restockTime = computeDeterministicBoundary(anchor, dataName, dataItem.RESTOCK_INTERVAL)
	local predictedData = _predictData(dataItem, restockTime)
	
	_setCachedData(dataName, predictedData)
	_log("info", "Preloaded data for '"..dataName.."'", false)
end

local function _optimizePollingInterval(dataItem, currentTime)
	local strategy = _optimizationSettings.strategy
	local baseInterval = _calculateNextPollingInterval(dataItem, currentTime)
	
	if strategy == _OPTIMIZATION_STRATEGIES.AGGRESSIVE then
		return math.max(_MIN_POLLING_INTERVAL, baseInterval * 0.7)
	elseif strategy == _OPTIMIZATION_STRATEGIES.CONSERVATIVE then
		return math.min(_MAX_POLLING_INTERVAL, baseInterval * 1.3)
	else
		return baseInterval -- Balanced strategy
	end
end

local function _getPerformanceRecommendations()
	local recommendations = {}
	
	-- Check cache hit rate
	local totalCacheAccess = 0
	local cacheHits = 0
	
	for dataName, _ in pairs(datas) do
		if _dataCache[dataName] then
			cacheHits = cacheHits + 1
		end
		totalCacheAccess = totalCacheAccess + 1
	end
	
	local cacheHitRate = totalCacheAccess > 0 and (cacheHits / totalCacheAccess) * 100 or 0
	
	if cacheHitRate < 50 then
		table.insert(recommendations, "Consider enabling preloading for better cache performance")
	end
	
	-- Check polling intervals
	for dataName, dataItem in pairs(datas) do
		if dataItem.RESTOCK_INTERVAL < 60 then
			table.insert(recommendations, "Data '"..dataName.."' has very frequent updates - consider increasing interval")
		end
	end
	
	-- Check memory usage
	local memoryUsage = #_dataCache + #_eventHistory
	if memoryUsage > 1000 then
		table.insert(recommendations, "High memory usage detected - consider reducing cache TTL or event history")
	end
	
	return recommendations
end

--// Data Persistence and Backup Functions

local function _serializeDataItem(dataItem)
	-- Create a serializable version of the data item
	local serialized = {
		dataItems = dataItem.dataItems,
		minItems = dataItem.minItems,
		maxItems = dataItem.maxItems,
		RESTOCK_INTERVAL = dataItem.RESTOCK_INTERVAL,
		_type = dataItem._type,
		_dataName = dataItem._dataName,
		_created = dataItem._created,
		allowedDays = dataItem.allowedDays,
		dateStart = dataItem.dateStart,
		dateEnd = dataItem.dateEnd
	}
	return serialized
end

local function _deserializeDataItem(serialized, globalKey)
	-- Reconstruct a data item from serialized data
	local dataItem = {
		dataItems = serialized.dataItems,
		minItems = serialized.minItems,
		maxItems = serialized.maxItems,
		RESTOCK_INTERVAL = serialized.RESTOCK_INTERVAL,
		globalKey = globalKey,
		_currentData = {},
		_running = false, -- Will be set to true when loaded
		_type = serialized._type,
		_dataName = serialized._dataName,
		_created = serialized._created,
		allowedDays = serialized.allowedDays,
		dateStart = serialized.dateStart,
		dateEnd = serialized.dateEnd
	}
	return dataItem
end

local function _saveDataConfig(dataName, dataItem)
	local success, result = pcall(function()
		local serialized = _serializeDataItem(dataItem)
		return configStore:SetAsync(dataName, {
			config = serialized,
			lastSaved = os.time(),
			version = _Version
		})
	end)
	
	if success then
		_log("info", "Data config saved for '"..dataName.."'", false)
		return true
	else
		_log("warn", "Failed to save data config for '"..dataName.."': "..tostring(result), true)
		return false
	end
end

local function _loadDataConfig(dataName)
	local success, result = pcall(function()
		return configStore:GetAsync(dataName)
	end)
	
	if success and result and result.config then
		_log("info", "Data config loaded for '"..dataName.."'", false)
		return result.config
	else
		_log("warn", "Failed to load data config for '"..dataName.."'", false)
		return nil
	end
end

local function _createBackup(dataName, dataItem)
	local backupId = dataName .. "_" .. os.time()
	local success, result = pcall(function()
		local serialized = _serializeDataItem(dataItem)
		return backupStore:SetAsync(backupId, {
			dataName = dataName,
			config = serialized,
			timestamp = os.time(),
			version = _Version
		})
	end)
	
	if success then
		_log("info", "Backup created for '"..dataName.."' with ID: "..backupId, false)
		return backupId
	else
		_log("warn", "Failed to create backup for '"..dataName.."': "..tostring(result), true)
		return nil
	end
end

local function _cleanupOldBackups()
	local cutoffTime = os.time() - (_BACKUP_RETENTION_DAYS * 24 * 60 * 60)
	
	-- This is a simplified cleanup - in production you might want more sophisticated cleanup
	pcall(function()
		-- Note: DataStore doesn't support listing all keys, so this is a placeholder
		-- In practice, you'd need to maintain a list of backup IDs or use a different approach
		_log("info", "Backup cleanup would run here (cutoff: "..cutoffTime..")", false)
	end)
end

--// Public API

--[[
	Creates and registers a new global data configuration
	
	@param dataName string Unique name of the data
	@param dataItems table List of items with chance, minAmount, maxAmount
	@param minItems number Minimum items to pick
	@param maxItems number Maximum items to pick
	@param restockInterval number Interval in seconds for data refresh
	@param dataType string Optional data type
	@param Info table Optional info for date/day restrictions
	@return table dataItem or nil, string error
]]
function GlobalDataService.CreateData(dataName, dataItems, minItems, maxItems, restockInterval, dataType, Info)
	-- Input validation
	if type(dataName) ~= "string" or dataName == "" then
		return nil, "dataName must be a non-empty string"
	end
	
	if type(dataItems) ~= "table" or #dataItems == 0 then
		return nil, "dataItems must be a non-empty table"
	end
	
	-- Validate data items
	local isValid, errorMsg = _validateDataItems(dataItems)
	if not isValid then
		return nil, errorMsg
	end
	
	minItems = tonumber(minItems) or 1
	maxItems = tonumber(maxItems) or minItems
	restockInterval = tonumber(restockInterval) or 50
	dataType = dataType or "Normal"
	
	if minItems < 1 then
		return nil, "minItems must be >= 1"
	end
	
	if maxItems < minItems then
		return nil, "maxItems must be >= minItems"
	end
	
	if restockInterval < 1 then
		return nil, "restockInterval must be >= 1"
	end
	
	if datas[dataName] then
		_log("warn", "Data '"..dataName.."' already exists. Overwriting.", true)
	end
	
	local globalKey = _ensureGlobalKeyAsync()
	if not globalKey then
		task.spawn(function()
			task.wait(5)
			_ensureGlobalKeyAsync()
		end)
	end
	
	local dataItem = {
		dataItems = dataItems,
		minItems = minItems,
		maxItems = maxItems,
		RESTOCK_INTERVAL = restockInterval,
		globalKey = globalKey,
		_currentData = {},
		_running = true,
		_type = string.lower(dataType),
		_dataName = dataName,
		_created = os.time()
	}
	
	if dataType:lower() == "datelimited" or dataType:lower() == "dayofweeklimited" then
		-- DateLimited setup (Info.start / Info.end with {year,month,day})
		if Info and Info.start and Info["end"] then
			dataItem.dateStart = convertToTime(Info.start)
			dataItem.dateEnd   = convertToTime(Info["end"])
		end
		
		-- DayOfWeekLimited setup (Info.days = {"Monday", "Friday"})
		if Info and Info.days then
			dataItem.allowedDays = {}
			for _, d in ipairs(Info.days) do
				local dayId = normalizeDayInput(d)
				dataItem.allowedDays[dayId] = true
			end
		end
	end
	
	datas[dataName] = dataItem
	task.spawn(function()
		_dataThread(dataName)
	end)
	
	-- Auto-save configuration
	_saveDataConfig(dataName, dataItem)
	
	_logEvent("data_created", dataName, {config = dataItem})
	return dataItem
end

--[[
	Gets the current data list for a data name
	
	@param dataName string
	@return table
]]
function GlobalDataService.GetCurrentData(dataName)
	local dataItem = datas[dataName]
	if not dataItem then return {} end
	
	-- Check cache first
	local cachedData = _getCachedData(dataName)
	if cachedData then
		return cachedData
	end
	
	local anchor = getGlobalAnchor()
	local restockTime = computeDeterministicBoundary(anchor, dataName, dataItem.RESTOCK_INTERVAL)
	
	local predictedData = _predictData(dataItem, restockTime)
	
	-- Cache the result
	_setCachedData(dataName, predictedData)
	
	return predictedData
end

--[[
	Gets the deterministic restock boundary and offset for a data
	
	@param dataName string
	@return currentBoundary, offset
]]
function GlobalDataService.GetDeterministicBoundary(dataName)
	local dataItem = datas[dataName]
	if not dataItem then
		return nil
	end
	local globalKey = dataItem.globalKey or _ensureGlobalKeyAsync()
	if not globalKey then
		return nil
	end
	local interval = dataItem.RESTOCK_INTERVAL or 100
	return computeDeterministicBoundary(globalKey, dataName, interval)
end

--[[
	Forces the next data to be a specific list for a given number of restocks
	
	@param dataName string
	@param dataList table The data items list to force
	@param restocks number Number of restocks before forced data expires
	@return boolean success
]]
function GlobalDataService.ForceNextData(dataName, dataList, restocks)
	assert(type(dataName) == "string", "dataName must be string")
	assert(type(dataList) == "table", "dataList must be table")
	
	restocks = tonumber(restocks) or 1
	
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "ForceNextData failed: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	-- Validate forced data list
	local isValid, errorMsg = _validateDataItems(dataList)
	if not isValid then
		_log("warn", "ForceNextData failed: " .. errorMsg, true)
		return false
	end
	
	_saveForcedDataToMemoryStore(dataName, dataList, restocks)
	
	local oldData = dataItem._currentData
	dataItem._currentData = dataList
	_callCallbacks(_onDataForceChangeCallbacks, dataName, oldData, dataList, 0)
	
	_logEvent("forced_data_set", dataName, {forcedData = dataList, restocks = restocks})
	_log("info", "Forced data set for '"..dataName.."' with expiration in "..tostring(restocks).." restocks", false)
	return true
end

--[[
	Clears forced data override for a data name
	
	@param dataName string
	@return boolean success
]]
function GlobalDataService.ClearForcedData(dataName)
	assert(type(dataName) == "string", "dataName must be string")
	
	local dataItem = datas[dataName]
	if not dataItem then
		return false
	end
	
	_clearForcedDataInMemoryStore(dataName)
	_logEvent("forced_data_cleared", dataName, {})
	_log("info", "Forced data cleared for '"..dataName.."'", false)
	return true
end

--[[
	Subscribe to data changed events (normal data changes)
	
	@param callback function(dataName, oldData, newData, restockTime)
	@return function unsubscribe function
]]
function GlobalDataService.OnDataChanged(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onDataChangedCallbacks + 1
	_onDataChangedCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onDataChangedCallbacks[callbackId] == callback then
			_onDataChangedCallbacks[callbackId] = nil
		end
	end
end

--[[
	Subscribe to forced data changed events
	
	@param callback function(dataName, oldData, newData, timer)
	@return function unsubscribe function
]]
function GlobalDataService.OnDataForceChanged(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onDataForceChangeCallbacks + 1
	_onDataForceChangeCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onDataForceChangeCallbacks[callbackId] == callback then
			_onDataForceChangeCallbacks[callbackId] = nil
		end
	end
end

--[[
	Subscribe to forced data expiration events
	
	@param callback function(dataName)
	@return function unsubscribe function
]]
function GlobalDataService.OnForcedDataExpired(callback)
	assert(type(callback) == "function", "callback must be function")
	
	local callbackId = #_onForcedDataExpiredCallbacks + 1
	_onForcedDataExpiredCallbacks[callbackId] = callback
	
	-- Return unsubscribe function
	return function()
		if _onForcedDataExpiredCallbacks[callbackId] == callback then
			_onForcedDataExpiredCallbacks[callbackId] = nil
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
		for name, dataItem in pairs(datas) do
			dataItem.globalKey = newKey
		end
		_logEvent("global_key_rotated", "system", {newKey = newKey})
		return true, newKey
	end
	
	return false, "Failed to rotate global key"
end

--[[
	Stops a data update loop cleanly
	
	@param dataName string
	@return boolean success
]]
function GlobalDataService.StopData(dataName)
	local dataItem = datas[dataName]
	if dataItem then
		dataItem._running = false
		_logEvent("data_stopped", dataName, {})
		return true
	end
	return false
end

--[[
	Stops all datas and cleans up resources
	
	@return boolean success
]]
function GlobalDataService.StopAllDatas()
	for dataName, dataItem in pairs(datas) do
		dataItem._running = false
	end
	
	-- Clear all callbacks
	_onDataChangedCallbacks = {}
	_onDataForceChangeCallbacks = {}
	_onForcedDataExpiredCallbacks = {}
	
	_logEvent("all_datas_stopped", "system", {})
	_log("info", "All datas stopped and callbacks cleared", true)
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
		activeDatas = _performanceMetrics.activeDatas,
		totalDatas = #datas,
		dataUpdates = _performanceMetrics.dataUpdates,
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
	Bulk operations for managing multiple datas
	
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
			success, result = GlobalDataService.CreateData(
				operation.dataName,
				operation.dataItems,
				operation.minItems,
				operation.maxItems,
				operation.restockInterval,
				operation.dataType,
				operation.info
			)
			if not success then
				errorMsg = result
			end
		elseif operation.action == "stop" then
			success = GlobalDataService.StopData(operation.dataName)
			result = success
		elseif operation.action == "force" then
			success = GlobalDataService.ForceNextData(
				operation.dataName,
				operation.dataList,
				operation.restocks
			)
			result = success
		else
			success = false
			errorMsg = "Unknown operation: " .. tostring(operation.action)
		end
		
		results[i] = {
			action = operation.action,
			dataName = operation.dataName,
			success = success,
			result = result,
			error = errorMsg
		}
	end
	
	return results
end

--[[
	Validates a data configuration without creating it
	
	@param dataItems table
	@param minItems number
	@param maxItems number
	@param restockInterval number
	@return boolean isValid, string errorMessage
]]
function GlobalDataService.ValidateDataConfig(dataItems, minItems, maxItems, restockInterval)
	if type(dataItems) ~= "table" or #dataItems == 0 then
		return false, "dataItems must be a non-empty table"
	end
	
	local isValid, errorMsg = _validateDataItems(dataItems)
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
	Gets information about a specific data
	
	@param dataName string
	@return table dataInfo or nil
]]
function GlobalDataService.GetDataInfo(dataName)
	local dataItem = datas[dataName]
	if not dataItem then
		return nil
	end
	
	return {
		name = dataName,
		type = dataItem._type,
		restockInterval = dataItem.RESTOCK_INTERVAL,
		minItems = dataItem.minItems,
		maxItems = dataItem.maxItems,
		currentData = dataItem._currentData,
		created = dataItem._created,
		running = dataItem._running,
		allowedDays = dataItem.allowedDays,
		dateStart = dataItem.dateStart,
		dateEnd = dataItem.dateEnd
	}
end

--[[
	Gets a list of all registered data names
	
	@return table dataNames
]]
function GlobalDataService.GetAllDataNames()
	local names = {}
	for dataName, _ in pairs(datas) do
		table.insert(names, dataName)
	end
	return names
end

--[[
	Saves a data configuration to persistent storage
	
	@param dataName string Name of the data to save
	@return boolean success
]]
function GlobalDataService.SaveDataConfig(dataName)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot save config: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	return _saveDataConfig(dataName, dataItem)
end

--[[
	Loads a data configuration from persistent storage
	
	@param dataName string Name of the data to load
	@param startRunning boolean Whether to start the data thread after loading
	@return boolean success
]]
function GlobalDataService.LoadDataConfig(dataName, startRunning)
	if datas[dataName] then
		_log("warn", "Cannot load config: Data '"..dataName.."' already exists", true)
		return false
	end
	
	local config = _loadDataConfig(dataName)
	if not config then
		return false
	end
	
	local globalKey = _ensureGlobalKeyAsync()
	if not globalKey then
		_log("warn", "Cannot load config: Failed to get global key", true)
		return false
	end
	
	local dataItem = _deserializeDataItem(config, globalKey)
	datas[dataName] = dataItem
	
	if startRunning then
		dataItem._running = true
		task.spawn(function()
			_dataThread(dataName)
		end)
		_log("info", "Data '"..dataName.."' loaded and started", false)
	else
		_log("info", "Data '"..dataName.."' loaded (not started)", false)
	end
	
	_logEvent("data_loaded", dataName, {config = dataItem})
	return true
end

--[[
	Creates a backup of a data configuration
	
	@param dataName string Name of the data to backup
	@return string backupId or nil
]]
function GlobalDataService.CreateBackup(dataName)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot create backup: Data '"..dataName.."' does not exist", true)
		return nil
	end
	
	local backupId = _createBackup(dataName, dataItem)
	if backupId then
		_logEvent("backup_created", dataName, {backupId = backupId})
	end
	return backupId
end

--[[
	Creates backups of all data configurations
	
	@return table backupResults
]]
function GlobalDataService.BackupAllConfigs()
	local results = {}
	
	for dataName, dataItem in pairs(datas) do
		local backupId = _createBackup(dataName, dataItem)
		results[dataName] = {
			success = backupId ~= nil,
			backupId = backupId
		}
	end
	
	_logEvent("all_backups_created", "system", {results = results})
	return results
end

--[[
	Restores a data configuration from a backup
	
	@param backupId string ID of the backup to restore
	@param overwriteExisting boolean Whether to overwrite existing data
	@return boolean success
]]
function GlobalDataService.RestoreFromBackup(backupId, overwriteExisting)
	local success, result = pcall(function()
		return backupStore:GetAsync(backupId)
	end)
	
	if not success or not result or not result.config then
		_log("warn", "Failed to retrieve backup: "..tostring(backupId), true)
		return false
	end
	
	local dataName = result.dataName
	if datas[dataName] and not overwriteExisting then
		_log("warn", "Cannot restore backup: Data '"..dataName.."' already exists", true)
		return false
	end
	
	-- Stop existing data if it exists
	if datas[dataName] then
		GlobalDataService.StopData(dataName)
	end
	
	local globalKey = _ensureGlobalKeyAsync()
	if not globalKey then
		_log("warn", "Cannot restore backup: Failed to get global key", true)
		return false
	end
	
	local dataItem = _deserializeDataItem(result.config, globalKey)
	datas[dataName] = dataItem
	
	-- Start the data thread
	dataItem._running = true
	task.spawn(function()
		_dataThread(dataName)
	end)
	
	_log("info", "Data '"..dataName.."' restored from backup: "..backupId, false)
	_logEvent("data_restored", dataName, {backupId = backupId, config = dataItem})
	return true
end

--[[
	Gets a list of available backups for a data name
	
	@param dataName string Name of the data
	@return table backupList or nil
]]
function GlobalDataService.GetBackupList(dataName)
	-- Note: This is a simplified implementation
	-- In production, you'd maintain a separate index of backup IDs
	local success, result = pcall(function()
		-- This would typically query a backup index
		return {message = "Backup listing not fully implemented - use specific backup IDs"}
	end)
	
	if success then
		return result
	else
		_log("warn", "Failed to get backup list: "..tostring(result), true)
		return nil
	end
end

--[[
	Sets a time window restriction for data availability
	
	@param dataName string Name of the data
	@param startHour number Start hour (0-23)
	@param endHour number End hour (0-23)
	@param timezone string Timezone (UTC, EST, PST, GMT, JST)
	@return boolean success
]]
function GlobalDataService.SetTimeWindow(dataName, startHour, endHour, timezone)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot set time window: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	if not startHour or not endHour or startHour < 0 or startHour > 23 or endHour < 0 or endHour > 23 then
		_log("warn", "Invalid time window: hours must be 0-23", true)
		return false
	end
	
	dataItem.timeWindow = {
		startHour = startHour,
		endHour = endHour,
		timezone = timezone or "UTC"
	}
	
	_log("info", "Time window set for '"..dataName.."': "..startHour..":00 to "..endHour..":00 "..(timezone or "UTC"), false)
	_logEvent("time_window_set", dataName, {startHour = startHour, endHour = endHour, timezone = timezone})
	return true
end

--[[
	Sets seasonal restrictions for data availability
	
	@param dataName string Name of the data
	@param seasons table Table of season names (spring, summer, autumn, winter)
	@return boolean success
]]
function GlobalDataService.SetSeasonalRestrictions(dataName, seasons)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot set seasonal restrictions: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	if type(seasons) ~= "table" then
		_log("warn", "Seasons must be a table", true)
		return false
	end
	
	-- Validate season names
	for seasonName, _ in pairs(seasons) do
		if not _SEASONS[seasonName] then
			_log("warn", "Invalid season: "..tostring(seasonName), true)
			return false
		end
	end
	
	dataItem.seasons = seasons
	_log("info", "Seasonal restrictions set for '"..dataName.."': "..table.concat(_getTableKeys(seasons), ", "), false)
	_logEvent("seasonal_restrictions_set", dataName, {seasons = seasons})
	return true
end

--[[
	Sets holiday exceptions for data availability
	
	@param dataName string Name of the data
	@param holidays table Table of holiday names
	@param allowOnHoliday boolean Whether to allow data on holidays
	@return boolean success
]]
function GlobalDataService.SetHolidayExceptions(dataName, holidays, allowOnHoliday)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot set holiday exceptions: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	if type(holidays) ~= "table" then
		_log("warn", "Holidays must be a table", true)
		return false
	end
	
	-- Validate holiday names
	for holidayName, _ in pairs(holidays) do
		if not _HOLIDAYS[holidayName] then
			_log("warn", "Invalid holiday: "..tostring(holidayName), true)
			return false
		end
	end
	
	dataItem.holidays = holidays
	dataItem.holidayExceptions = {
		allowOnHoliday = allowOnHoliday or false
	}
	
	_log("info", "Holiday exceptions set for '"..dataName.."': "..table.concat(_getTableKeys(holidays), ", ").." (allow: "..tostring(allowOnHoliday), false)
	_logEvent("holiday_exceptions_set", dataName, {holidays = holidays, allowOnHoliday = allowOnHoliday})
	return true
end

--[[
	Sets a custom schedule for data availability
	
	@param dataName string Name of the data
	@param schedule table Custom schedule table
	@return boolean success
]]
function GlobalDataService.SetCustomSchedule(dataName, schedule)
	local dataItem = datas[dataName]
	if not dataItem then
		_log("warn", "Cannot set custom schedule: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	if type(schedule) ~= "table" then
		_log("warn", "Schedule must be a table", true)
		return false
	end
	
	-- Validate schedule format
	for dayIndex, daySchedule in pairs(schedule) do
		if type(dayIndex) ~= "number" or dayIndex < 0 or dayIndex > 6 then
			_log("warn", "Invalid day index: "..tostring(dayIndex).." (must be 0-6)", true)
			return false
		end
		
		if type(daySchedule) ~= "table" then
			_log("warn", "Day schedule must be a table", true)
			return false
		end
		
		for _, timeSlot in ipairs(daySchedule) do
			if type(timeSlot) ~= "table" or not timeSlot.start or not timeSlot["end"] then
				_log("warn", "Invalid time slot format", true)
				return false
			end
			
			if timeSlot.start < 0 or timeSlot.start > 23.99 or timeSlot["end"] < 0 or timeSlot["end"] > 23.99 then
				_log("warn", "Invalid time: hours must be 0-23.99", true)
				return false
			end
		end
	end
	
	dataItem.customSchedule = schedule
	_log("info", "Custom schedule set for '"..dataName.."'", false)
	_logEvent("custom_schedule_set", dataName, {schedule = schedule})
	return true
end

--[[
	Gets the current time restrictions for a data item
	
	@param dataName string Name of the data
	@return table timeRestrictions or nil
]]
function GlobalDataService.GetTimeRestrictions(dataName)
	local dataItem = datas[dataName]
	if not dataItem then
		return nil
	end
	
	return {
		timeWindow = dataItem.timeWindow,
		seasons = dataItem.seasons,
		holidays = dataItem.holidays,
		holidayExceptions = dataItem.holidayExceptions,
		customSchedule = dataItem.customSchedule,
		allowedDays = dataItem.allowedDays,
		dateStart = dataItem.dateStart,
		dateEnd = dataItem.dateEnd
	}
end

--[[
	Sets the performance optimization strategy
	
	@param strategy string Strategy to use (aggressive, balanced, conservative)
	@return boolean success
]]
function GlobalDataService.SetOptimizationStrategy(strategy)
	if not _OPTIMIZATION_STRATEGIES[strategy] then
		_log("warn", "Invalid optimization strategy: "..tostring(strategy), true)
		return false
	end
	
	_optimizationSettings.strategy = strategy
	_log("info", "Optimization strategy set to: "..strategy, false)
	_logEvent("optimization_strategy_changed", "system", {strategy = strategy})
	return true
end

--[[
	Enables or disables data preloading
	
	@param enabled boolean Whether to enable preloading
	@return boolean success
]]
function GlobalDataService.SetPreloading(enabled)
	_optimizationSettings.preloadEnabled = enabled and true or false
	_log("info", "Data preloading " .. (_optimizationSettings.preloadEnabled and "enabled" or "disabled"), false)
	_logEvent("preloading_changed", "system", {enabled = _optimizationSettings.preloadEnabled})
	return true
end

--[[
	Enables or disables data caching
	
	@param enabled boolean Whether to enable caching
	@return boolean success
]]
function GlobalDataService.SetCaching(enabled)
	_optimizationSettings.cacheEnabled = enabled and true or false
	
	if not enabled then
		-- Clear existing cache
		_dataCache = {}
		_cacheTimestamps = {}
		_log("info", "Cache cleared and disabled", false)
	end
	
	_log("info", "Data caching " .. (_optimizationSettings.cacheEnabled and "enabled" or "disabled"), false)
	_logEvent("caching_changed", "system", {enabled = _optimizationSettings.cacheEnabled})
	return true
end

--[[
	Sets the cache TTL (Time To Live) in seconds
	
	@param ttl number Cache TTL in seconds
	@return boolean success
]]
function GlobalDataService.SetCacheTTL(ttl)
	if not ttl or ttl < 1 then
		_log("warn", "Cache TTL must be >= 1 second", true)
		return false
	end
	
	_CACHE_TTL = ttl
	_log("info", "Cache TTL set to "..ttl.." seconds", false)
	_logEvent("cache_ttl_changed", "system", {ttl = ttl})
	return true
end

--[[
	Preloads data for a specific data item
	
	@param dataName string Name of the data to preload
	@return boolean success
]]
function GlobalDataService.PreloadData(dataName)
	if not datas[dataName] then
		_log("warn", "Cannot preload: Data '"..dataName.."' does not exist", true)
		return false
	end
	
	_preloadData(dataName)
	return true
end

--[[
	Preloads data for all data items
	
	@return table preloadResults
]]
function GlobalDataService.PreloadAllData()
	local results = {}
	
	for dataName, _ in pairs(datas) do
		_preloadData(dataName)
		results[dataName] = true
	end
	
	_log("info", "Preloaded data for "..#_getTableKeys(results).." data items", false)
	_logEvent("all_data_preloaded", "system", {count = #_getTableKeys(results)})
	return results
end

--[[
	Clears the data cache
	
	@param dataName string Optional specific data name to clear, or nil for all
	@return boolean success
]]
function GlobalDataService.ClearCache(dataName)
	if dataName then
		_dataCache[dataName] = nil
		_cacheTimestamps[dataName] = nil
		_log("info", "Cache cleared for '"..dataName.."'", false)
	else
		_dataCache = {}
		_cacheTimestamps = {}
		_log("info", "All cache cleared", false)
	end
	
	_logEvent("cache_cleared", dataName or "system", {dataName = dataName})
	return true
end

--[[
	Gets performance optimization recommendations
	
	@return table recommendations
]]
function GlobalDataService.GetPerformanceRecommendations()
	return _getPerformanceRecommendations()
end

--[[
	Gets current optimization settings
	
	@return table settings
]]
function GlobalDataService.GetOptimizationSettings()
	return {
		strategy = _optimizationSettings.strategy,
		preloadEnabled = _optimizationSettings.preloadEnabled,
		cacheEnabled = _optimizationSettings.cacheEnabled,
		cacheTTL = _CACHE_TTL,
		cacheSize = #_getTableKeys(_dataCache)
	}
end

--// Start health check loop
task.spawn(function()
	while true do
		_performHealthCheck()
		task.wait(_HEALTH_CHECK_INTERVAL)
	end
end)

return GlobalDataService