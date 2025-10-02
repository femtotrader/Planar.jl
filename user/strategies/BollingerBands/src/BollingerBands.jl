module BollingerBands
using Planar

const DESCRIPTION = "BollingerBands"
const EXC = :phemex
const MARGIN = Isolated
const TF = tf"1m"

@strategyenv!
@contractsenv!
using Indicators

function bbands!(ohlcv, from_date)
    ohlcv = viewfrom(ohlcv, from_date; offset=-20)
    bb = bbands(ohlcv.close; n=20, sigma=2.0)
    @assert bb[end, 1] <= bb[end, 2] <= bb[end, 3]
    [bb[:, 1] bb[:, 3]]
end

function call!(s::SC{<:ExchangeID,Sim}, ::ResetStrategy)
    call!(bbands!, s, InitData(); cols=(:bb_lower, :bb_upper))
end

call!(_::SC, ::WarmupPeriod) = Day(1)

function handler(s, ai, ats, ts)
    """
    1) Compute indicators from data
    """
    call!(bbands!, s, ai, UpdateData(); cols=(:bb_lower, :bb_upper))
    ohlcv = ai.data[s.timeframe]

    lower = ohlcv[ats, :bb_lower]
    upper = ohlcv[ats, :bb_upper]
    current_price = closeat(ohlcv, ats)

    """
    2) Fetch portfolio
    """
    # disposable balance not committed to any pending order
    balance_quoted = s.self.freecash(s)
    # we invest only 80% of available liquidity
    buy_value = float(balance_quoted) * 0.80

    """
    3) Fetch position for symbol
    """
    has_position = isopen(ai, Long())
    prev_trades = length(trades(ai))

    """
    4) Resolve buy or sell signals
    """
    if current_price < lower && !has_position
        @linfo "buy signal: creating market order" sym = raw(ai) buy_value current_price
        amount = buy_value / current_price
        call!(s, ai, MarketOrder{Buy}; date=ts, amount)
    elseif current_price > upper && has_position
        @linfo "sell signal: closing position" exposure = value(ai) current_price
        call!(s, ai, Long(), ts, PositionClose())
    end
    """
    5) Check strategy profitability
    """
    if length(trades(ai)) > prev_trades
        # ....
    end
end

function call!(s::T, ts::DateTime, _) where {T<:SC}
    ats = available(s.timeframe, ts)
    foreach(s.universe) do ai
        handler(s, ai, ats, ts)
    end
end

function call!(t::Type{<:SC}, config, ::LoadStrategy)
    assets = marketsid(t)
    sandbox = config.mode == Paper() ? false : config.sandbox
    timeframe = tf"1h"
    s = Strategy(@__MODULE__, assets; config, sandbox, timeframe)
    @assert marginmode(s) == config.margin
    @assert execmode(s) == config.mode
    s[:verbose] = false

    if issim(s)
        ##  whatever method to load the data, e.g.
        # pair = first(marketsid(s))
        # quote_currency = string(nameof(s.cash))
        # data = Scrapers.BinanceData.binanceload(pair; quote_currency)
        # Engine.stub!(s.universe, data)
        # NOTE: `Scrapers` is not imported by default, if you want to use it here you
        # have to add it manually to the strategy.
        # Recommended to just stub the data with a function defined in the REPL
    else
        call!(s, WatchOHLCV())
    end
    s
end

function call!(::Type{<:SC}, ::StrategyMarkets)
    String["BTC/USDT:USDT"]
end

## Optimization
# function call!(s::S, ::OptSetup)
#     (;
#         ctx=Context(Sim(), tf"15m", dt"2020-", now()),
#         params=(),
#         # space=(kind=:MixedPrecisionRectSearchSpace, precision=Int[]),
#     )
# end
# function call!(s::S, params, ::OptRun) end

# function call!(s::S, ::OptScore)::Vector
#     [mt.sharpe(s)]
# end

end
