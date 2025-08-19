# GlobalDataService

A Roblox module for managing global stock across servers using DataStoreService and MemoryStoreService. Supports forced stock overrides, automatic restocking, random stock prediction based on a global key, callbacks for stock changes, and advanced stock types with date/time restrictions.

---

## Features

- Global stock generation with a shared global key
- Automatic periodic restocking with configurable intervals
- Forced stock overrides with expiration via MemoryStoreService
- Callbacks for stock changes and forced stock updates
- Safe update retries and key rotation support
- Debug logging and version update notifications
- Day-of-week and date range restrictions for stock availability
- Performance monitoring and health checks
- Bulk operations for managing multiple stocks
- Stock validation and configuration management
- Event history tracking for debugging
- Smart polling intervals based on restock timing
- Deterministic stock generation across servers

---

## Update logs, Version "v1.1.5"
- Performance monitoring and health checks
- Bulk operations for managing multiple stocks
- Stock validation and configuration management
- Event history tracking for debugging
- Smart polling intervals based on restock timing
- Enhanced error handling and callback management
- Stock types (current types: "normal", "datelimited", "dayofweeklimited")
- Date range restrictions
- Day-of-week restrictions

## Example usage:
```lua
local GlobalStockService = require(path.to.GlobalStockService)

--// Example 1: Normal Stock
GlobalStockService.CreateStock(
	"NormalStock", -- stock name
	{
		{name = "Apple", chance = 80, minAmount = 1, maxAmount = 5},
		{name = "Banana", chance = 50, minAmount = 1, maxAmount = 3},
	}, -- items
	1, -- minItems
	2, -- maxItems
	60 -- restockInterval in seconds
)

--// Example 2: DateLimited Stock
GlobalStockService.CreateStock(
	"HolidayStock",
	{
		{name = "CandyCane", chance = 100, minAmount = 1, maxAmount = 2},
		{name = "GiftBox", chance = 60, minAmount = 1, maxAmount = 1},
	},
	1, -- minItems
	2, -- maxItems
	200, -- restockInterval
	"DateLimited", -- type
	{
		start = {year = 2025, month = 12, day = 23},
		["end"] = {year = 2025, month = 12, day = 31}
	} -- date range
)

--// Example 3: DayOfWeekLimited Stock
GlobalStockService.CreateStock(
	"WeekendStock",
	{
		{name = "Chocolate", chance = 90, minAmount = 1, maxAmount = 4},
		{name = "Juice", chance = 70, minAmount = 1, maxAmount = 2},
	},
	1, -- minItems
	2, -- maxItems
	5, -- restockInterval
	"DayOfWeekLimited", -- type
	{
		days = {"Thursday", "Sunday"}
	} -- days of the week
)

-- Callback to see when stocks change
GlobalStockService.OnStockChanged(function(stockName, oldStock, newStock, time)
	print("Stock changed:", stockName)
	print("Old stock:", oldStock)
	print("New stock:", newStock)
	print("Time:", time)
end)
```

---

## Installation

1. Copy `GlobalStockService.lua` into your Roblox project (ideally in `ServerScriptService`).
2. Require it in your script:
```lua
local GlobalStockService = require(path.to.GlobalStockService)
```

## Basic Usage
### Create a stock configuration and start its update loop:
```lua
local stockItems = {
    {name = "ItemA", chance = 50, minAmount = 1, maxAmount = 3},
    {name = "ItemB", chance = 30, minAmount = 2, maxAmount = 5},
    {name = "ItemC", chance = 80, minAmount = 1, maxAmount = 1},
}

local myStock = GlobalStockService.CreateStock("MyShopStock", stockItems, 1, 3, 600)

local currentStock = GlobalStockService.GetCurrentStock("MyShopStock")
for _, item in ipairs(currentStock) do
    print(item.name, item.amount)
end
```

## Forced Stock Overrides
### Force the next stock to a specific list for a defined number of restocks:
```lua
local forcedStock = {
    {name = "SpecialItem", amount = 10}
}

GlobalStockService.ForceNextStock("MyShopStock", forcedStock, 2)

-- Clear forced stock override:
GlobalStockService.ClearForcedStock("MyShopStock")
```

## Event Callbacks
### Subscribe to stock change events:
```lua
GlobalStockService.OnStockChanged(function(stockName, oldStock, newStock, restockTime)
    print("Stock changed for", stockName)
end)
```
### Subscribe to forced stock change events:
```lua
GlobalStockService.OnStockForceChanged(function(stockName, oldStock, newStock, timer)
    print("Forced stock changed for", stockName)
end)
```
### Subscribe to forced stock expiration events:
```lua
GlobalStockService.OnForcedStockExpired(function(stockName)
    print("Forced stock expired for", stockName)
end)
```

## Advanced Usage
### Rotate the global key manually
```lua
local success, newKeyOrError = GlobalStockService.ForceRotateGlobalKey()
if success then
    print("Global key rotated successfully")
else
    warn("Failed to rotate global key:", newKeyOrError)
end
```

### Enable or disable debug logging
```lua
GlobalStockService.SetDebug(true) -- Enable debug logs
GlobalStockService.SetDebug(false) -- Disable debug logs
```

### Get performance metrics and health information
```lua
local metrics = GlobalStockService.GetPerformanceMetrics()
print("Active stocks:", metrics.activeStocks)
print("Total stocks:", metrics.totalStocks)
print("Stock updates:", metrics.stockUpdates)
print("Global key status:", metrics.globalKeyStatus)
print("Version:", metrics.version)
```

### Get event history for debugging
```lua
local events = GlobalStockService.GetEventHistory(10) -- Get last 10 events
for _, event in ipairs(events) do
    print(event.timestamp, event.type, event.stockName)
end
```

### Bulk operations for managing multiple stocks
```lua
local operations = {
    {
        action = "create",
        stockName = "Stock1",
        stockItems = {{name = "Item1", chance = 100, minAmount = 1, maxAmount = 1}},
        minItems = 1,
        maxItems = 1,
        restockInterval = 60
    },
    {
        action = "force",
        stockName = "Stock2",
        stockList = {{name = "SpecialItem", amount = 5}},
        restocks = 2
    },
    {
        action = "stop",
        stockName = "Stock3"
    }
}

local results = GlobalStockService.BulkOperation(operations)
for _, result in ipairs(results) do
    print(result.action, result.stockName, result.success)
end
```

### Validate stock configuration without creating it
```lua
local isValid, errorMsg = GlobalStockService.ValidateStockConfig(
    {{name = "Item1", chance = 100, minAmount = 1, maxAmount = 1}},
    1, 1, 60
)
if isValid then
    print("Configuration is valid")
else
    warn("Configuration error:", errorMsg)
end
```

### Get information about a specific stock
```lua
local stockInfo = GlobalStockService.GetStockInfo("MyShopStock")
if stockInfo then
    print("Stock type:", stockInfo.type)
    print("Restock interval:", stockInfo.restockInterval)
    print("Running:", stockInfo.running)
    print("Created:", stockInfo.created)
end
```

### Get all registered stock names
```lua
local stockNames = GlobalStockService.GetAllStockNames()
for _, name in ipairs(stockNames) do
    print("Stock:", name)
end
```

### Get deterministic boundary for a stock
```lua
local boundary = GlobalStockService.GetDeterministicBoundary("MyShopStock")
if boundary then
    print("Next restock boundary:", boundary)
end
```

### Stop a specific stock
```lua
GlobalStockService.StopStock("MyShopStock")
```

### Stop all stocks and clean up
```lua
GlobalStockService.StopAllStocks()
```

## API Overview

### Core Functions
- `CreateStock(name, items, min, max, interval, type, info)` - Create and start a new stock configuration
- `GetCurrentStock(name)` - Get current stock for a stock name
- `ForceNextStock(name, list, restocks)` - Force next stock list for a given number of restocks
- `ClearForcedStock(name)` - Clear forced stock override
- `StopStock(name)` - Stop the stock update loop for a stock
- `StopAllStocks()` - Stop all stocks and clean up resources

### Event Callbacks
- `OnStockChanged(callback)` - Subscribe to normal stock change events
- `OnStockForceChanged(callback)` - Subscribe to forced stock change events
- `OnForcedStockExpired(callback)` - Subscribe to forced stock expiration events

### Utility Functions
- `ForceRotateGlobalKey()` - Manually rotate the global key
- `SetDebug(enabled)` - Enable or disable debug logging
- `GetPerformanceMetrics()` - Get performance metrics and health information
- `GetEventHistory(limit)` - Get recent event history for debugging
- `BulkOperation(operations)` - Perform bulk operations on multiple stocks
- `ValidateStockConfig(items, min, max, interval)` - Validate stock configuration
- `GetStockInfo(name)` - Get information about a specific stock
- `GetAllStockNames()` - Get list of all registered stock names
- `GetDeterministicBoundary(name)` - Get deterministic restock boundary

## Stock Types

### Normal Stock
Default stock type with no time restrictions.

### DateLimited Stock
Stock that is only available within a specific date range.
```lua
{
    start = {year = 2025, month = 12, day = 23},
    ["end"] = {year = 2025, month = 12, day = 31}
}
```

### DayOfWeekLimited Stock
Stock that is only available on specific days of the week.
```lua
{
    days = {"Monday", "Friday", "Sunday"}
}
```

## Configuration Options

### Stock Items
Each item in the stock configuration should have:
- `name` (string) - The name of the item
- `chance` (number, 0-100) - Probability of the item appearing (optional, defaults to 100)
- `minAmount` (number) - Minimum amount of the item (optional, defaults to 1)
- `maxAmount` (number) - Maximum amount of the item (optional, defaults to minAmount)

### Date Configuration
For date-limited stocks, use:
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
- Smart polling intervals that adjust based on restock timing
- Global key health monitoring
- Callback error tracking and cleanup

## Error Handling

The service includes robust error handling:
- Automatic retries for DataStore operations
- Graceful handling of callback errors
- Fallback mechanisms for stock generation
- Validation of all input parameters
- Comprehensive logging for debugging

## License

MIT — see [LICENSE](LICENSE) for details.
