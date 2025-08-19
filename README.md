# GlobalDataService

A Roblox module for managing global data across servers using DataStoreService and MemoryStoreService. Supports forced data overrides, automatic refreshing, random data prediction based on a global key, callbacks for data changes, and advanced data types with date/time restrictions.

---

## Features

- Global data generation with a shared global key
- Automatic periodic refreshing with configurable intervals
- Forced data overrides with expiration via MemoryStoreService
- Callbacks for data changes and forced data updates
- Safe update retries and key rotation support
- Debug logging and version update notifications
- Day-of-week and date range restrictions for data availability
- Performance monitoring and health checks
- Bulk operations for managing multiple data sets
- Data validation and configuration management
- Event history tracking for debugging
- Smart polling intervals based on refresh timing
- Deterministic data generation across servers

---

## Update logs
- Performance monitoring and health checks
- Bulk operations for managing multiple data sets
- Data validation and configuration management
- Event history tracking for debugging
- Smart polling intervals based on refresh timing
- Enhanced error handling and callback management
- Data types (current types: "normal", "datelimited", "dayofweeklimited")
- Date range restrictions
- Day-of-week restrictions

## Example usage:
```lua
local GlobalDataService = require(path.to.GlobalDataService)

--// Example 1: Normal Data
GlobalDataService.CreateData(
	"NormalData", -- data name
	{
		{name = "Apple", chance = 80, minAmount = 1, maxAmount = 5},
		{name = "Banana", chance = 50, minAmount = 1, maxAmount = 3},
	}, -- items
	1, -- minItems
	2, -- maxItems
	60 -- refreshInterval in seconds
)

--// Example 2: DateLimited Data
GlobalDataService.CreateData(
	"HolidayData",
	{
		{name = "CandyCane", chance = 100, minAmount = 1, maxAmount = 2},
		{name = "GiftBox", chance = 60, minAmount = 1, maxAmount = 1},
	},
	1, -- minItems
	2, -- maxItems
	200, -- refreshInterval
	"DateLimited", -- type
	{
		start = {year = 2025, month = 12, day = 23},
		["end"] = {year = 2025, month = 12, day = 31}
	} -- date range
)

--// Example 3: DayOfWeekLimited Data
GlobalDataService.CreateData(
	"WeekendData",
	{
		{name = "Chocolate", chance = 90, minAmount = 1, maxAmount = 4},
		{name = "Juice", chance = 70, minAmount = 1, maxAmount = 2},
	},
	1, -- minItems
	2, -- maxItems
	5, -- refreshInterval
	"DayOfWeekLimited", -- type
	{
		days = {"Thursday", "Sunday"}
	} -- days of the week
)

-- Callback to see when data changes
GlobalDataService.OnDataChanged(function(dataName, oldData, newData, time)
	print("Data changed:", dataName)
	print("Old data:", oldData)
	print("New data:", newData)
	print("Time:", time)
end)
```

---

## Installation

1. Copy `GlobalDataService.lua` into your Roblox project (ideally in `ServerScriptService`).
2. Require it in your script:
```lua
local GlobalDataService = require(path.to.GlobalDataService)
```

## Basic Usage
### Create a data configuration and start its update loop:
```lua
local dataItems = {
    {name = "ItemA", chance = 50, minAmount = 1, maxAmount = 3},
    {name = "ItemB", chance = 30, minAmount = 2, maxAmount = 5},
    {name = "ItemC", chance = 80, minAmount = 1, maxAmount = 1},
}

local myData = GlobalDataService.CreateData("MyShopData", dataItems, 1, 3, 600)

local currentData = GlobalDataService.GetCurrentData("MyShopData")
for _, item in ipairs(currentData) do
    print(item.name, item.amount)
end
```

## Forced Data Overrides
### Force the next data to a specific list for a defined number of refreshes:
```lua
local forcedData = {
    {name = "SpecialItem", amount = 10}
}

GlobalDataService.ForceNextData("MyShopData", forcedData, 2)

-- Clear forced data override:
GlobalDataService.ClearForcedData("MyShopData")
```

## Event Callbacks
### Subscribe to data change events:
```lua
GlobalDataService.OnDataChanged(function(dataName, oldData, newData, refreshTime)
    print("Data changed for", dataName)
end)
```
### Subscribe to forced data change events:
```lua
GlobalDataService.OnDataForceChanged(function(dataName, oldData, newData, timer)
    print("Forced data changed for", dataName)
end)
```
### Subscribe to forced data expiration events:
```lua
GlobalDataService.OnForcedDataExpired(function(dataName)
    print("Forced data expired for", dataName)
end)
```

## Advanced Usage
### Rotate the global key manually
```lua
local success, newKeyOrError = GlobalDataService.ForceRotateGlobalKey()
if success then
    print("Global key rotated successfully")
else
    warn("Failed to rotate global key:", newKeyOrError)
end
```

### Enable or disable debug logging
```lua
GlobalDataService.SetDebug(true) -- Enable debug logs
GlobalDataService.SetDebug(false) -- Disable debug logs
```

### Get performance metrics and health information
```lua
local metrics = GlobalDataService.GetPerformanceMetrics()
print("Active data sets:", metrics.activeDataSets)
print("Total data sets:", metrics.totalDataSets)
print("Data updates:", metrics.dataUpdates)
print("Global key status:", metrics.globalKeyStatus)
print("Version:", metrics.version)
```

### Get event history for debugging
```lua
local events = GlobalDataService.GetEventHistory(10) -- Get last 10 events
for _, event in ipairs(events) do
    print(event.timestamp, event.type, event.dataName)
end
```

### Bulk operations for managing multiple data sets
```lua
local operations = {
    {
        action = "create",
        dataName = "Data1",
        dataItems = {{name = "Item1", chance = 100, minAmount = 1, maxAmount = 1}},
        minItems = 1,
        maxItems = 1,
        refreshInterval = 60
    },
    {
        action = "force",
        dataName = "Data2",
        dataList = {{name = "SpecialItem", amount = 5}},
        refreshes = 2
    },
    {
        action = "stop",
        dataName = "Data3"
    }
}

local results = GlobalDataService.BulkOperation(operations)
for _, result in ipairs(results) do
    print(result.action, result.dataName, result.success)
end
```

### Validate data configuration without creating it
```lua
local isValid, errorMsg = GlobalDataService.ValidateDataConfig(
    {{name = "Item1", chance = 100, minAmount = 1, maxAmount = 1}},
    1, 1, 60
)
if isValid then
    print("Configuration is valid")
else
    warn("Configuration error:", errorMsg)
end
```

### Get information about a specific data set
```lua
local dataInfo = GlobalDataService.GetDataInfo("MyShopData")
if dataInfo then
    print("Data type:", dataInfo.type)
    print("Refresh interval:", dataInfo.refreshInterval)
    print("Running:", dataInfo.running)
    print("Created:", dataInfo.created)
end
```

### Get all registered data names
```lua
local dataNames = GlobalDataService.GetAllDataNames()
for _, name in ipairs(dataNames) do
    print("Data:", name)
end
```

### Get deterministic boundary for a data set
```lua
local boundary = GlobalDataService.GetDeterministicBoundary("MyShopData")
if boundary then
    print("Next refresh boundary:", boundary)
end
```

### Stop a specific data set
```lua
GlobalDataService.StopData("MyShopData")
```

### Stop all data sets and clean up
```lua
GlobalDataService.StopAllData()
```

## API Overview

### Core Functions
- `CreateData(name, items, min, max, interval, type, info)` - Create and start a new data configuration
- `GetCurrentData(name)` - Get current data for a data name
- `ForceNextData(name, list, refreshes)` - Force next data list for a given number of refreshes
- `ClearForcedData(name)` - Clear forced data override
- `StopData(name)` - Stop the data update loop for a data set
- `StopAllData()` - Stop all data sets and clean up resources

### Event Callbacks
- `OnDataChanged(callback)` - Subscribe to normal data change events
- `OnDataForceChanged(callback)` - Subscribe to forced data change events
- `OnForcedDataExpired(callback)` - Subscribe to forced data expiration events

### Utility Functions
- `ForceRotateGlobalKey()` - Manually rotate the global key
- `SetDebug(enabled)` - Enable or disable debug logging
- `GetPerformanceMetrics()` - Get performance metrics and health information
- `GetEventHistory(limit)` - Get recent event history for debugging
- `BulkOperation(operations)` - Perform bulk operations on multiple data sets
- `ValidateDataConfig(items, min, max, interval)` - Validate data configuration
- `GetDataInfo(name)` - Get information about a specific data set
- `GetAllDataNames()` - Get list of all registered data names
- `GetDeterministicBoundary(name)` - Get deterministic refresh boundary

## Data Types

### Normal Data
Default data type with no time restrictions.

### DateLimited Data
Data that is only available within a specific date range.
```lua
{
    start = {year = 2025, month = 12, day = 23},
    ["end"] = {year = 2025, month = 12, day = 31}
}
```

### DayOfWeekLimited Data
Data that is only available on specific days of the week.
```lua
{
    days = {"Monday", "Friday", "Sunday"}
}
```

## Configuration Options

### Data Items
Each item in the data configuration should have:
- `name` (string) - The name of the item
- `chance` (number, 0-100) - Probability of the item appearing (optional, defaults to 100)
- `minAmount` (number) - Minimum amount of the item (optional, defaults to 1)
- `maxAmount` (number) - Maximum amount of the item (optional, defaults to minAmount)

### Date Configuration
For date-limited data sets, use:
- `year` (number) - Year
- `month` (number) - Month (1-12)
- `day` (number) - Day (1-31)
- `hour` (number, optional) - Hour (0-23, defaults to 0)
- `min` or `minute` (number, optional) - Minute (0-59, defaults to 0)
- `sec` or `second` (number, optional) - Second (0-59, defaults to 0)
- `timezoneOffset` or `tzOffset` (number, optional) - Timezone offset in hours

### Day Names
Supported day names for day-of-week restrictions:
- "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"
- Or use numbers 1-7 (1 = Sunday, 7 = Saturday)

## Performance and Monitoring

The service includes built-in performance monitoring:
- Automatic health checks every 60 seconds
- Performance metrics tracking
- Event history for debugging
- Smart polling intervals that adjust based on refresh timing
- Global key health monitoring
- Callback error tracking and cleanup

## Error Handling

The service includes robust error handling:
- Automatic retries for DataStore operations
- Graceful handling of callback errors
- Fallback mechanisms for data generation
- Validation of all input parameters
- Comprehensive logging for debugging

## License

MIT — see [LICENSE](LICENSE) for details.
