using Watchers
using Watchers: default_init
using Watchers.WatchersImpls:
    _tfunc!,
    _tfunc,
    _exc!,
    _exc,
    _lastpushed!,
    _lastpushed,
    _lastprocessed!,
    _lastprocessed,
    _lastcount!,
    _lastcount
@watcher_interface!
using .Exchanges: check_timeout
using .Exchanges.Python: @py
using .Lang: splitkws, withoutkws, safenotify, safewait

const CcxtBalanceVal = Val{:ccxt_balance_val}

@doc """ Sets up a watcher for CCXT balance.

$(TYPEDSIGNATURES)

This function sets up a watcher for balance in the CCXT library. The watcher keeps track of the balance and updates it as necessary.
"""
function ccxt_balance_watcher(
    s::Strategy;
    interval=Second(1),
    wid="ccxt_balance",
    buffer_capacity=10,
    start=false,
    params=LittleDict{Any,Any}(),
    kwargs...,
)
    exc = st.exchange(s)
    check_timeout(exc, interval)
    attrs = Dict{Symbol,Any}()
    params["type"] = @pystr(lowercase(string(balance_type(s))))
    _exc!(attrs, exc)
    attrs[:strategy] = s
    attrs[:iswatch] = @lget! s.attrs :is_watch_balance has(exc, :watchBalance)
    attrs[:func_kwargs] = (; params, kwargs...)
    attrs[:interval] = interval
    watcher_type = Py
    wid = string(wid, "-", hash((exc.id, nameof(s), account(s))))
    watcher(
        watcher_type,
        wid,
        CcxtBalanceVal();
        start,
        load=false,
        flush=false,
        process=false,
        buffer_capacity,
        view_capacity=1,
        fetch_interval=interval,
        attrs,
    )
end

@doc """ Wraps a fetch balance function with a specified interval.

$(TYPEDSIGNATURES)

This function wraps a fetch balance function `s` with a specified `interval`. Additional keyword arguments `kwargs` are passed to the fetch balance function.
"""
function _balance_setup_state!(s, w, attrs)
    exc = exchange(s)
    timeout = throttle(s)
    interval = attrs[:interval]
    params, rest = _ccxt_balance_args(s, attrs[:func_kwargs])
    buffer_size = attr(s, :live_buffer_size, 1000)
    s[:balance_buffer] = w[:buf_process] = buf = Vector{Any}()
    # NOTE: this is NOT a Threads.Condition because we shouldn't yield inside the push function
    # (we can't lock (e.g. by using `safenotify`) must use plain `notify`)
    s[:balance_notify] = w[:buf_notify] = buf_notify = Condition()
    sizehint!(buf, buffer_size)
    tasks = w[:process_tasks] = Vector{Task}()
    errors = w[:errors_count] = Ref(0)
    (
        s=s,
        w=w,
        attrs=attrs,
        exc=exc,
        timeout=timeout,
        interval=interval,
        params=params,
        rest=rest,
        buf=buf,
        buf_notify=buf_notify,
        tasks=tasks,
        errors=errors,
    )
end

function _balance_setup_stall_guard!(state)
    s = state.s; w = state.w; attrs = state.attrs
    # Stop any existing stall_guard_task using stop_task
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
    w[:stall_guard_task] = @start_task IdDict() begin
        while isstarted(w)
            try
                last = _lastprocessed(w)
                if now() - last > Second(60)
                    @warn "balance watcher: forcing fetch due to stall" last now() s
                    _force_fetchbal(s; fallback_kwargs=attrs[:func_kwargs])
                end
            catch e
                @warn "balance watcher: stall guard error" exception=e
            end
            sleep(10)
        end
    end
end

function _balance_process_bal!(state, w, v)
    if !isnothing(v)
        if !isnothing(_dopush!(w, v; if_func=isdict))
            push!(state.tasks, @async process!(w))
            filter!(!istaskdone, state.tasks)
        end
    end
    nothing
end

function _balance_init_watch!(state)
    s = state.s; w = state.w
    v = @lock w fetch_balance(s; state.timeout, state.params, state.rest...)
    _balance_process_bal!(state, w, v)
    state_init = Ref(false)
    f_push(v) = begin
        push!(state.buf, v)
        notify(state.buf_notify)
        maybe_backoff!(state.errors, v)
    end
    h = w[:balance_handler] = watch_balance_handler(state.exc; f_push, state.params, state.rest...)
    start_handler!(h)
    state_init
end

function _balance_watch_closure(state)
    init_ref = Ref(true)
    function _balance_watch_do_init!()
        if init_ref[]
            _ = _balance_init_watch!(state)
            init_ref[] = false
        end
        nothing
    end
    function balance_watch_step(w)
        _balance_watch_do_init!()
        while isempty(state.buf) && isstarted(w)
            wait(state.buf_notify)
        end
        if !isempty(state.buf)
            v = popfirst!(state.buf)
            if v isa Exception
                @error "balance watcher: unexpected value" exception = v
                maybe_backoff!(state.errors, v)
                sleep(1)
            else
                _balance_process_bal!(state, w, pydict(v))
            end
        end
        nothing
    end
    balance_watch_step
end

function _balance_flush_buf_notify!(state, w)
    while !isempty(state.buf)
        v = popfirst!(state.buf)
        _dopush!(w, v)
        push!(state.tasks, @async process!(w))
        filter!(!istaskdone, state.tasks)
    end
end

function _balance_fetch_closure(state)
    s = state.s
    function balance_fetch_step(w)
        start = now()
        try
            _balance_flush_buf_notify!(state, w)
            v = @lock w fetch_balance(s; state.timeout, state.params, state.rest...)
            _dopush!(w, v; if_func=isdict)
            push!(state.tasks, @async process!(w))
            _balance_flush_buf_notify!(state, w)
            filter!(!istaskdone, state.tasks)
        finally
            sleep_pad(start, state.interval)
        end
        nothing
    end
    balance_fetch_step
end

function _w_balance_func(s, w, attrs)
    state = _balance_setup_state!(s, w, attrs)
    if attrs[:iswatch]
        _balance_setup_stall_guard!(state)
        return _balance_watch_closure(state)
    else
        return _balance_fetch_closure(state)
    end
end

_balance_task!(w) = begin
    f = _tfunc(w)
    errors = w.errors_count
    w[:balance_task] = (@async while isstarted(w)
        try
            f(w)
            safenotify(w.beacon.fetch)
        catch e
            if e isa InterruptException
                break
            else
                maybe_backoff!(errors, e)
                @debug_backtrace LogWatchBalance
            end
        end
    end) |> errormonitor
end

_balance_task(w) = @lget! attrs(w) :balance_task _balance_task!(w)

function Watchers._stop!(w::Watcher, ::CcxtBalanceVal)
    handler = attr(w, :balance_handler, nothing)
    if !isnothing(handler)
        stop_handler!(handler)
    end
    if haskey(w, :stall_guard_task)
        stop_task(w[:stall_guard_task])
        delete!(w, :stall_guard_task)
    end
    notify(w.buf_notify)
    nothing
end

function Watchers._fetch!(w::Watcher, ::CcxtBalanceVal)
    fetch_task = _balance_task(w)
    if !istaskrunning(fetch_task)
        _balance_task!(w)
    end
    return true
end

function _init!(w::Watcher, ::CcxtBalanceVal)
    default_init(w, BalanceDict(), false)
    _lastpushed!(w, DateTime(0))
    _lastprocessed!(w, DateTime(0))
    _lastcount!(w, ())
end

@doc """ Processes balance for a watcher using the CCXT library.

$(TYPEDSIGNATURES)

This function processes balance for a watcher `w` using the CCXT library. It goes through the balance stored in the watcher and updates it based on the latest data from the exchange.

"""
function Watchers._process!(w::Watcher, ::CcxtBalanceVal; fetched=false)
    if isempty(w.buffer)
        return nothing
    end
    eid = typeof(exchangeid(_exc(w)))
    data_date, data = last(w.buffer)
    baldict = w.view.assets
    if !isdict(data) || resp_event_type(data, eid) != ot.BalanceUpdated
        @debug "balance watcher: wrong data type" _module = LogWatchBalProcess data_date typeof(
            data
        )
        _lastprocessed!(w, data_date)
        _lastcount!(w, ())
        return nothing
    end
    if data_date == _lastprocessed(w) && length(data) == _lastcount(w)
        @debug "balance watcher: already processed" _module = LogWatchBalProcess data_date
        return nothing
    end
    date = @something pytodate(data, eid) now()
    if date == w.view.date
        _lastprocessed!(w, data_date)
        return nothing
    end
    s = w.strategy
    symsdict = w.symsdict
    assets_value = current_total(s; bal=w.view) - s.cash
    qc_upper, qc_lower = @lget! attrs(w) :qc_syms begin
        upper = nameof(cash(s))
        lower = string(upper) |> lowercase |> Symbol
        upper, lower
    end
    for (sym, sym_bal) in data.items()
        if isdict(sym_bal) && haskey(sym_bal, @pyconst("free"))
            k = Symbol(sym)
            total = get_float(sym_bal, "total")
            free = let v = get_float(sym_bal, "free")
                if iszero(v)
                    max(zero(total), total - assets_value)
                else
                    v
                end
            end
            isqc = k == qc_upper || k == qc_lower
            used = let v = get_float(sym_bal, "used")
                if iszero(v)
                    used = v
                    # TODO: add fees?
                    if isqc
                        for o in orders(s)
                            if o isa IncreaseOrder
                                used += unfilled(o) * o.price
                            end
                        end
                    else
                        ai = asset_bysym(s, string(sym), symsdict)
                        if !isnothing(ai)
                            for o in orders(s, ai)
                                if o isa ReduceOrder
                                    used += unfilled(o)
                                end
                            end
                        end
                    end
                    used
                else
                    v
                end
            end
            bal = if haskey(baldict, k)
                update!(baldict[k], date; total, free, used)
            else
                baldict[k] = BalanceSnapshot(; currency=sym, date, total, free, used)
            end
            if isqc
                s_events = get_events(s)
                func = () -> _live_sync_strategy_cash!(s; bal)
                sendrequest!(s, bal.date, func)
            elseif s isa NoMarginStrategy
                ai = asset_bysym(s, sym, symsdict)
                if !isnothing(ai)
                    func = () -> _live_sync_cash!(s, ai; bal)
                    sendrequest!(ai, bal.date, func)
                end
            end
        end
    end
    w.view.date = date
    _lastprocessed!(w, data_date)
    _lastcount!(w, data)
    @debug "balance watcher data:" _module = LogWatchBalProcess date get(bal, :BTC, nothing) _module =
        :Watchers
end

@doc """ Starts a watcher for balance in a live strategy.

$(TYPEDSIGNATURES)

This function starts a watcher for balance in a live strategy `s`. The watcher checks and updates the balance at a specified interval.

"""
function watch_balance!(s::LiveStrategy; interval=st.throttle(s), wait=false)
    @debug "live: watch balance get" _module = LogWatchBalance islocked(s)
    w = @lock s @lget! s :live_balance_watcher ccxt_balance_watcher(s; interval)
    just_started = if isstopped(w) && !attr(s, :stopped, false)
        @debug "live: locking" _module = LogWatchBalance
        @lock w if isstopped(w)
            @debug "live: start" _module = LogWatchBalance
            start!(w)
            @debug "live: started" _module = LogWatchBalance
            true
        else
            @debug "live: already started" _module = LogWatchBalance
            false
        end
    else
        false
    end
    while wait && just_started && _lastprocessed(w) == DateTime(0)
        @debug "live: waiting for initial balance" _module = LogWatchBalance
        safewait(w.beacon.process)
    end
    w
end

@doc """ Stops the watcher for balance in a live strategy.

$(TYPEDSIGNATURES)

This function stops the watcher that is tracking and updating balance for a live strategy `s`.

"""
function stop_watch_balance!(s::LiveStrategy)
    w = get(s.attrs, :live_balance_watcher, nothing)
    if w isa Watcher
        @debug "live: stopping balance watcher" _module = LogWatchBalance islocked(w)
        if isstarted(w)
            stop!(w)
        end
        @debug "live: balance watcher stopped" _module = LogWatchBalance
    end
end

@doc """ Retrieves the balance watcher for a live strategy.

$(TYPEDSIGNATURES)
"""
balance_watcher(s) = s[:live_balance_watcher]

# function _load!(w::Watcher, ::CcxtBalanceVal) end

# function _process!(w::Watcher, ::CcxtBalanceVal) end

function _start!(w::Watcher, ::CcxtBalanceVal)
    _lastprocessed!(w, DateTime(0))
    attrs = w.attrs
    view = attrs[:view]
    reset!(view)
    s = attrs[:strategy]
    w[:symsdict] = symsdict(s)
    exc = exchange(s)
    _exc!(attrs, exc)
    _tfunc!(attrs, _w_balance_func(s, w, attrs))
end
