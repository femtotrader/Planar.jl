# Glossary and Disambiguation

This glossary defines key terms and concepts used throughout Planar documentation and codebase.

## Core Concepts

### Trading Terms

**Asset**
: A structure created from parsing a symbol, typically representing an `Asset`, `Derivative`, or `AssetInstance`. Variables representing asset instances are often named `ai`, while simple assets are named `a` or `aa` (for `AbstractAsset`).

**Symbol (sym)**
: Though `Symbol` is a built-in Julia type, in trading contexts it often denotes the pairing of a base currency with a quote currency. Commonly refers to a `Symbol` for single currencies and a `String` for currency pairs.

**Pair**
: A `String` in the format `"BASE/QUOTE"` where the slash separates the base and quote currencies (e.g., `"BTC/USDT"`).

**Base Currency (bc) / Quote Currency (qc)**
: Base currency (`bc`) is the asset being traded; quote currency (`qc`) is the currency used to price the base. Both are `Symbol` types corresponding to `AbstractAsset` fields.

**Amount**
: The quantity of the base currency. For example, purchasing 100 USD worth of BTC at 1000 USD per BTC results in an amount of `0.1 BTC`.

**Price**
: The cost of one unit of base currency quoted in the quote currency. If BTC price is 1000 USD, then `1 BTC = 1000 USD`.

**Size**
: The quantity of quote currency used to execute a trade, inclusive of fees.

### Position and Order Terms

**Long/Short**
: Used exclusively in margin trading contexts. "Long" indicates betting on price increase; "short" indicates betting on price decrease.

**Side/Position**
: "Side" refers to trade direction ("buy" or "sell"). "Position" refers to market exposure ("long" or "short"). A trade's side is buy/sell; its position is long/short.

**Margin**
: Trading with borrowed funds to increase position size. Planar supports `NoMargin` (spot), `Isolated` (position-specific margin), and `Cross` (shared margin) modes.

**Leverage**
: The ratio of position size to margin. Higher leverage amplifies both profits and losses.

### Data and Market Terms

**OHLCV**
: Open, High, Low, Close, Volume - standard candlestick data format. Usually refers to a DataFrame containing this market data.

**Candle**
: A single OHLCV data point, can be a DataFrame row, named tuple, or `Candle` structure.

**Timeframe**
: The duration each candle represents (e.g., `tf"1m"` for 1-minute candles, `tf"1h"` for hourly).

**Pairdata**
: A complex data structure associating a DataFrame, Zarr array, and trading pair.

**Resample**
: Converting data between timeframes, usually downsampling (e.g., 1m → 1h) as upsampling is rarely beneficial.

### Exchange and Infrastructure Terms

**Exchange (exc)**
: Can refer to an `Exchange` instance, `ExchangeID`, or the `Symbol` of an exchange ID. A global `exc` variable is defined in `ExchangeTypes` for REPL convenience.

**Sandbox**
: Exchange-provided "testnet" for API testing. Distinct from paper trading - sandbox uses test APIs, paper trading uses live data with simulated execution.

**Instance**
: Typically implies an `AssetInstance` - the combination of an asset and exchange.

**Futures/Swap/Perps**
: Swaps are perpetual futures contracts. Following CCXT conventions: swaps use `"BASE/QUOTE:SETTLE"` format, futures include expiry as `"BASE/QUOTE:SETTLE-EXPIRY"`.

## Planar-Specific Terms

### Strategy System

**Strategy**
: A Julia module implementing trading logic through the `call!` dispatch system. Parameterized by execution mode, exchange, margin type, and quote currency.

**Dispatch**
: Julia's multiple dispatch system used throughout Planar for customization. Methods are selected based on argument types.

**Call! Function**
: The primary interface for strategy logic. Different method signatures handle different events (execution, loading, optimization, etc.).

**Strategy Environment**
: Macros like `@strategyenv!`, `@contractsenv!`, and `@optenv!` that import required types and functions into strategy modules.

### Execution Modes

**Sim Mode**
: Backtesting mode using historical data. Fast execution with simplified order simulation.

**Paper Mode**
: Real-time simulation using live market data but no actual trades. Tests strategy logic with realistic market conditions.

**Live Mode**
: Real trading with actual capital and exchange APIs. Includes full risk management and monitoring.

### Data System

**Zarr**
: Columnar storage format used for OHLCV data. Supports compression and chunked access for large datasets.

**LMDB**
: Lightning Memory-Mapped Database used as the default storage backend for Zarr arrays.

**ZarrInstance**
: Wrapper around Zarr storage providing the data access interface. Global instance available at `Data.zi[]`.

**Scraper**
: Module for downloading historical data archives from exchanges (currently Binance and Bybit).

**Fetch**
: Module for downloading data directly from exchange APIs using CCXT.

**Watcher**
: Real-time data monitoring system that continuously collects and stores live market data.

### Optimization and Analysis

**OptSession**
: Structure managing optimization parameters, configuration, and results. Can be saved and reloaded.

**Grid Search**
: Optimization method testing all combinations of parameter values.

**Bayesian Optimization**
: Advanced optimization using probabilistic models to efficiently explore parameter space.

**Objective Function**
: Function returning a score to maximize during optimization (e.g., Sharpe ratio, profit).

### Visualization

**Balloons**
: Planar's signature trade visualization showing entry/exit points on price charts.

**Backend**
: Graphics system for plotting (GLMakie for desktop, WGLMakie for web).

**Interactive Plots**
: Charts with zoom, pan, and hover capabilities for detailed analysis.

## Variable Naming Conventions

**Common Variable Names**
- `s` - Strategy instance
- `ai` - AssetInstance
- `exc` - Exchange
- `ts` - Timestamp
- `ats` - Available timestamp (validated for data availability)
- `ctx` - Context object
- `cfg` - Configuration object

**Type Abbreviations**
- `SC` - Strategy type with generic exchange parameter
- `S` - Complete strategy type with all parameters
- `AI` - AssetInstance type
- `TF` - TimeFrame type

## File and Directory Conventions

**Strategy Locations**
- Single file: `user/strategies/StrategyName.jl`
- Project: `user/strategies/StrategyName/src/StrategyName.jl`

**Configuration Files**
- Main config: `user/planar.toml`
- Secrets: `user/secrets.toml`
- Strategy config: `user/strategies/StrategyName/Project.toml`

**Data Storage**
- LMDB files: `user/data.mdb`, `user/lock.mdb`
- Logs: `user/logs/`

## See Also

- **[Strategy Development](strategy.md)** - Learn strategy concepts in detail
- **[Data Management](data.md)** - Understand data storage and access
- **[API Reference](API/)** - Complete function documentation
- **[Documentation Index](documentation-index.md)** - Find specific topics quickly