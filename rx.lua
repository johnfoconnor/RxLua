-- RxLua v0.0.1
-- https://github.com/bjornbytes/rxlua
-- MIT License

local util = {}

util.pack = table.pack or function(...) return { n = select('#', ...), ... } end
util.unpack = table.unpack or unpack
util.eq = function(x, y) return x == y end
util.noop = function() end
util.identity = function(x) return x end
util.constant = function(x) return function() return x end end

--- @class Subscription
-- @description A handle representing the link between an Observer and an Observable, as well as any
-- work required to clean up after the Observable completes or the Observer unsubscribes.
local Subscription = {}
Subscription.__index = Subscription
Subscription.__tostring = util.constant('Subscription')

--- Creates a new Subscription.
-- @arg {function=} action - The action to run when the subscription is unsubscribed. It will only
--                           be run once.
-- @returns {Subscription}
function Subscription.create(action)
  local self = {
    action = action or util.noop,
    unsubscribed = false
  }

  return setmetatable(self, Subscription)
end

--- Unsubscribes the subscription, performing any necessary cleanup work.
function Subscription:unsubscribe()
  if self.unsubscribed then return end
  self.action(self)
  self.unsubscribed = true
end

--- @class Observer
-- @description Observers are simple objects that receive values from Observables.
local Observer = {}
Observer.__index = Observer
Observer.__tostring = util.constant('Observer')

--- Creates a new Observer.
-- @arg {function=} onNext - Called when the Observable produces a value.
-- @arg {function=} onError - Called when the Observable terminates due to an error.
-- @arg {function=} onCompleted - Called when the Observable completes normally.
-- @returns {Observer}
function Observer.create(onNext, onError, onCompleted)
  local self = {
    _onNext = onNext or util.noop,
    _onError = onError or error,
    _onCompleted = onCompleted or util.noop,
    stopped = false
  }

  return setmetatable(self, Observer)
end

--- Pushes zero or more values to the Observer.
-- @arg {*...} values
function Observer:onNext(...)
  if not self.stopped then
    self._onNext(...)
  end
end

--- Notify the Observer that an error has occurred.
-- @arg {string=} message - A string describing what went wrong.
function Observer:onError(message)
  if not self.stopped then
    self.stopped = true
    self._onError(message)
  end
end

--- Notify the Observer that the sequence has completed and will produce no more values.
function Observer:onCompleted()
  if not self.stopped then
    self.stopped = true
    self._onCompleted()
  end
end

--- @class Observable
-- @description Observables push values to Observers.
local Observable = {}
Observable.__index = Observable
Observable.__tostring = util.constant('Observable')

--- Creates a new Observable.
-- @arg {function} subscribe - The subscription function that produces values.
-- @returns {Observable}
function Observable.create(subscribe)
  local self = {
    _subscribe = subscribe
  }

  return setmetatable(self, Observable)
end

--- Shorthand for creating an Observer and passing it to this Observable's subscription function.
-- @arg {function} onNext - Called when the Observable produces a value.
-- @arg {function} onError - Called when the Observable terminates due to an error.
-- @arg {function} onCompleted - Called when the Observable completes normally.
function Observable:subscribe(onNext, onError, onCompleted)
  if type(onNext) == 'table' then
    return self._subscribe(onNext)
  else
    return self._subscribe(Observer.create(onNext, onError, onCompleted))
  end
end

--- Returns an Observable that immediately completes without producing a value.
function Observable.empty()
  return Observable.create(function(observer)
    observer:onCompleted()
  end)
end

--- Returns an Observable that never produces values and never completes.
function Observable.never()
  return Observable.create(function(observer) end)
end

--- Returns an Observable that immediately produces an error.
function Observable.throw(message)
  return Observable.create(function(observer)
    observer:onError(message)
  end)
end

--- Creates an Observable that produces a single value.
-- @arg {*} value
-- @returns {Observable}
function Observable.fromValue(value)
  return Observable.create(function(observer)
    observer:onNext(value)
    observer:onCompleted()
  end)
end

--- Creates an Observable that produces a range of values in a manner similar to a Lua for loop.
-- @arg {number} initial - The first value of the range, or the upper limit if no other arguments
--                         are specified.
-- @arg {number=} limit - The second value of the range.
-- @arg {number=1} step - An amount to increment the value by each iteration.
-- @returns {Observable}
function Observable.fromRange(initial, limit, step)
  if not limit and not step then
    initial, limit = 1, initial
  end

  step = step or 1

  return Observable.create(function(observer)
    for i = initial, limit, step do
      observer:onNext(i)
    end

    observer:onCompleted()
  end)
end

--- Creates an Observable that produces values from a table.
-- @arg {table} table - The table used to create the Observable.
-- @arg {function=pairs} iterator - An iterator used to iterate the table, e.g. pairs or ipairs.
-- @arg {boolean} keys - Whether or not to also emit the keys of the table.
-- @returns {Observable}
function Observable.fromTable(t, iterator, keys)
  iterator = iterator or pairs
  return Observable.create(function(observer)
    for key, value in iterator(t) do
      observer:onNext(value, keys and key or nil)
    end

    observer:onCompleted()
  end)
end

--- Creates an Observable that produces values when the specified coroutine yields.
-- @arg {thread} coroutine
-- @returns {Observable}
function Observable.fromCoroutine(thread, scheduler)
  thread = type(thread) == 'function' and coroutine.create(thread) or thread
  return Observable.create(function(observer)
    return scheduler:schedule(function()
      while not observer.stopped do
        local success, value = coroutine.resume(thread)

        if success then
          observer:onNext(value)
        else
          return observer:onError(value)
        end

        if coroutine.status(thread) == 'dead' then
          return observer:onCompleted()
        end

        coroutine.yield()
      end
    end)
  end)
end

--- Creates an Observable that creates a new Observable for each observer using a factory function.
-- @arg {function} factory - A function that returns an Observable.
-- @returns {Observable}
function Observable.defer(fn)
  return setmetatable({
    subscribe = function(_, ...)
      local observable = fn()
      return observable:subscribe(...)
    end
  }, Observable)
end

--- Subscribes to this Observable and prints values it produces.
-- @arg {string=} name - Prefixes the printed messages with a name.
-- @arg {function=tostring} formatter - A function that formats one or more values to be printed.
function Observable:dump(name, formatter)
  name = name and (name .. ' ') or ''
  formatter = formatter or tostring

  local onNext = function(...) print(name .. 'onNext: ' .. formatter(...)) end
  local onError = function(e) print(name .. 'onError: ' .. e) end
  local onCompleted = function() print(name .. 'onCompleted') end

  return self:subscribe(onNext, onError, onCompleted)
end

--- Determine whether all items emitted by an Observable meet some criteria.
-- @arg {function=identity} predicate - The predicate used to evaluate objects.
function Observable:all(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local function onNext(...)
      if not predicate(...) then
        observer:onNext(false)
        observer:onCompleted()
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      observer:onNext(true)
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Given a set of Observables, produces values from only the first one to produce a value.
-- @arg {Observable...} observables
-- @returns {Observable}
function Observable.amb(a, b, ...)
  if not a or not b then return a end

  return Observable.create(function(observer)
    local subscriptionA, subscriptionB

    local function onNextA(...)
      if subscriptionB then subscriptionB:unsubscribe() end
      observer:onNext(...)
    end

    local function onErrorA(e)
      if subscriptionB then subscriptionB:unsubscribe() end
      observer:onError(e)
    end

    local function onCompletedA()
      if subscriptionB then subscriptionB:unsubscribe() end
      observer:onCompleted()
    end

    local function onNextB(...)
      if subscriptionA then subscriptionA:unsubscribe() end
      observer:onNext(...)
    end

    local function onErrorB(e)
      if subscriptionA then subscriptionA:unsubscribe() end
      observer:onError(e)
    end

    local function onCompletedB()
      if subscriptionA then subscriptionA:unsubscribe() end
      observer:onCompleted()
    end

    subscriptionA = a:subscribe(onNextA, onErrorA, onCompletedA)
    subscriptionB = b:subscribe(onNextB, onErrorB, onCompletedB)

    return Subscription.create(function()
      subscriptionA:unsubscribe()
      subscriptionB:unsubscribe()
    end)
  end):amb(...)
end

--- Returns an Observable that produces the average of all values produced by the original.
-- @returns {Observable}
function Observable:average()
  return Observable.create(function(observer)
    local sum, count = 0, 0

    local function onNext(value)
      sum = sum + value
      count = count + 1
    end

    local function onError(e)
      observer:onError(e)
    end

    local function onCompleted()
      if count > 0 then
        observer:onNext(sum / count)
      end

      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that buffers values from the original and produces them as multiple
-- values.
-- @arg {number} size - The size of the buffer.
function Observable:buffer(size)
  return Observable.create(function(observer)
    local buffer = {}

    local function emit()
      if #buffer > 0 then
        observer:onNext(util.unpack(buffer))
        buffer = {}
      end
    end

    local function onNext(...)
      local values = {...}
      for i = 1, #values do
        table.insert(buffer, values[i])
        if #buffer >= size then
          emit()
        end
      end
    end

    local function onError(message)
      emit()
      return observer:onError(message)
    end

    local function onCompleted()
      emit()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that intercepts any errors from the previous and replace them with values
-- produced by a new Observable.
-- @arg {function|Observable} handler - An Observable or a function that returns an Observable to
--                                       replace the source Observable in the event of an error.
-- @returns {Observable}
function Observable:catch(handler)
  handler = handler and (type(handler) == 'function' and handler or util.constant(handler))

  return Observable.create(function(observer)
    local subscription

    local function onNext(...)
      return observer:onNext(...)
    end

    local function onError(e)
      if not handler then
        return observer:onCompleted()
      end

      local continue = handler(e)
      if continue then
        if subscription then subscription:unsubscribe() end
        continue:subscribe(observer)
      else
        observer:onError(e)
      end
    end

    local function onCompleted()
      observer:onCompleted()
    end

    subscription = self:subscribe(onNext, onError, onCompleted)
    return subscription
  end)
end

--- Returns a new Observable that runs a combinator function on the most recent values from a set
-- of Observables whenever any of them produce a new value. The results of the combinator function
-- are produced by the new Observable.
-- @arg {Observable...} observables - One or more Observables to combine.
-- @arg {function} combinator - A function that combines the latest result from each Observable and
--                              returns a single value.
-- @returns {Observable}
function Observable:combineLatest(...)
  local sources = {...}
  local combinator = table.remove(sources)
  if type(combinator) ~= 'function' then
    table.insert(sources, combinator)
    combinator = function(...) return ... end
  end
  table.insert(sources, 1, self)

  return Observable.create(function(observer)
    local latest = {}
    local pending = {util.unpack(sources)}
    local completed = {}

    local function onNext(i)
      return function(value)
        latest[i] = value
        pending[i] = nil

        if not next(pending) then
          observer:onNext(combinator(util.unpack(latest)))
        end
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted(i)
      return function()
        table.insert(completed, i)

        if #completed == #sources then
          observer:onCompleted()
        end
      end
    end

    for i = 1, #sources do
      sources[i]:subscribe(onNext(i), onError, onCompleted(i))
    end
  end)
end

--- Returns a new Observable that produces the values of the first with falsy values removed.
-- @returns {Observable}
function Observable:compact()
  return self:filter(util.identity)
end

--- Returns a new Observable that produces the values produced by all the specified Observables in
-- the order they are specified.
-- @arg {Observable...} sources - The Observables to concatenate.
-- @returns {Observable}
function Observable:concat(other, ...)
  if not other then return self end

  local others = {...}

  return Observable.create(function(observer)
    local function onNext(...)
      return observer:onNext(...)
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    local function chain()
      return other:concat(util.unpack(others)):subscribe(onNext, onError, onCompleted)
    end

    return self:subscribe(onNext, onError, chain)
  end)
end

--- Returns a new Observable that produces a single boolean value representing whether or not the
-- specified value was produced by the original.
-- @arg {*} value - The value to search for.  == is used for equality testing.
-- @returns {Observable}
function Observable:contains(value)
  return Observable.create(function(observer)
    local subscription

    local function onNext(...)
      local args = util.pack(...)

      if #args == 0 and value == nil then
        observer:onNext(true)
        if subscription then subscription:unsubscribe() end
        return observer:onCompleted()
      end

      for i = 1, #args do
        if args[i] == value then
          observer:onNext(true)
        if subscription then subscription:unsubscribe() end
          return observer:onCompleted()
        end
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      observer:onNext(false)
      return observer:onCompleted()
    end

    subscription = self:subscribe(onNext, onError, onCompleted)
    return subscription
  end)
end

--- Returns an Observable that produces a single value representing the number of values produced
-- by the source value that satisfy an optional predicate.
-- @arg {function=} predicate - The predicate used to match values.
function Observable:count(predicate)
  predicate = predicate or util.constant(true)

  return Observable.create(function(observer)
    local count = 0

    local function onNext(...)
      if predicate(...) then
        count = count + 1
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      observer:onNext(count)
      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces a default set of items if the source Observable produces
-- no values.
-- @arg {*...} values - Zero or more values to produce if the source completes without emitting
--                      anything.
-- @returns {Observable}
function Observable:defaultIfEmpty(...)
  local defaults = util.pack(...)

  return Observable.create(function(observer)
    local hasValue = false

    local function onNext(...)
      hasValue = true
      observer:onNext(...)
    end

    local function onError(e)
      observer:onError(e)
    end

    local function onCompleted()
      if not hasValue then
        observer:onNext(util.unpack(defaults))
      end

      observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces the values from the original with duplicates removed.
-- @returns {Observable}
function Observable:distinct()
  return Observable.create(function(observer)
    local values = {}

    local function onNext(x)
      if not values[x] then
        observer:onNext(x)
      end

      values[x] = true
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that only produces values from the original if they are different from
-- the previous value.
-- @arg {function} comparator - A function used to compare 2 values. If unspecified, == is used.
-- @returns {Observable}
function Observable:distinctUntilChanged(comparator)
  comparator = comparator or util.eq

  return Observable.create(function(observer)
    local first = true
    local currentValue = nil

    local function onNext(value, ...)
      if first or not comparator(value, currentValue) then
        observer:onNext(value, ...)
        currentValue = value
        first = false
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that produces the nth element produced by the source Observable.
-- @arg {number} index - The index of the item, with an index of 1 representing the first.
-- @returns {Observable}
function Observable:elementAt(index)
  return Observable.create(function(observer)
    local subscription
    local i = 1

    local function onNext(...)
      if i == index then
        observer:onNext(...)
        observer:onCompleted()
        if subscription then
          subscription:unsubscribe()
        end
      else
        i = i + 1
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    subscription = self:subscribe(onNext, onError, onCompleted)
    return subscription
  end)
end

--- Returns a new Observable that only produces values of the first that satisfy a predicate.
-- @arg {function} predicate - The predicate used to filter values.
-- @returns {Observable}
function Observable:filter(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local function onNext(...)
      if predicate(...) then
        return observer:onNext(...)
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces the first value of the original that satisfies a
-- predicate.
-- @arg {function} predicate - The predicate used to find a value.
function Observable:find(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local function onNext(...)
      if predicate(...) then
        observer:onNext(...)
        return observer:onCompleted()
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that only produces the first result of the original.
-- @returns {Observable}
function Observable:first()
  return self:take(1)
end

--- Returns a new Observable that transform the items emitted by an Observable into Observables,
-- then flatten the emissions from those into a single Observable
-- @arg {function} callback - The function to transform values from the original Observable.
-- @returns {Observable}
function Observable:flatMap(callback)
  callback = callback or util.identity
  return self:map(callback):flatten()
end

--- Returns a new Observable that uses a callback to create Observables from the values produced by
-- the source, then produces values from the most recent of these Observables.
-- @arg {function=identity} callback - The function used to convert values to Observables.
-- @returns {Observable}
function Observable:flatMapLatest(callback)
  callback = callback or util.identity
  return Observable.create(function(observer)
    local innerSubscription

    local function onNext(...)
      observer:onNext(...)
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    local function subscribeInner(...)
      if innerSubscription then
        innerSubscription:unsubscribe()
      end

      innerSubscription = callback(...):subscribe(onNext, onError)
    end

    local subscription = self:subscribe(subscribeInner, onError, onCompleted)
    return Subscription.create(function()
      if innerSubscription then
        innerSubscription:unsubscribe()
      end

      if subscription then
        subscription:unsubscribe()
      end
    end)
  end)
end

--- Returns a new Observable that subscribes to the Observables produced by the original and
-- produces their values.
-- @returns {Observable}
function Observable:flatten()
  return Observable.create(function(observer)
    local function onError(message)
      return observer:onError(message)
    end

    local function onNext(observable)
      local function innerOnNext(...)
        observer:onNext(...)
      end

      observable:subscribe(innerOnNext, onError, util.noop)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that only produces the last result of the original.
-- @returns {Observable}
function Observable:last()
  return Observable.create(function(observer)
    local value
    local empty = true

    local function onNext(...)
      value = {...}
      empty = false
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      if not empty then
        observer:onNext(util.unpack(value or {}))
      end

      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces the values of the original transformed by a function.
-- @arg {function} callback - The function to transform values from the original Observable.
-- @returns {Observable}
function Observable:map(callback)
  return Observable.create(function(observer)
    callback = callback or util.identity

    local function onNext(...)
      return observer:onNext(callback(...))
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces the maximum value produced by the original.
-- @returns {Observable}
function Observable:max()
  return self:reduce(math.max)
end

--- Returns a new Observable that produces the values produced by all the specified Observables in
-- the order they are produced.
-- @arg {Observable...} sources - One or more Observables to merge.
-- @returns {Observable}
function Observable:merge(...)
  local sources = {...}
  table.insert(sources, 1, self)

  return Observable.create(function(observer)
    local function onNext(...)
      return observer:onNext(...)
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted(i)
      return function()
        sources[i] = nil

        if not next(sources) then
          observer:onCompleted()
        end
      end
    end

    for i = 1, #sources do
      sources[i]:subscribe(onNext, onError, onCompleted(i))
    end
  end)
end

--- Returns a new Observable that produces the minimum value produced by the original.
-- @returns {Observable}
function Observable:min()
  return self:reduce(math.min)
end

--- Returns an Observable that produces the values of the original inside tables.
-- @returns {Observable}
function Observable:pack()
  return self:map(util.pack)
end

--- Returns two Observables: one that produces values for which the predicate returns truthy for,
-- and another that produces values for which the predicate returns falsy.
-- @arg {function} predicate - The predicate used to partition the values.
-- @returns {Observable}
-- @returns {Observable}
function Observable:partition(predicate)
  return self:filter(predicate), self:reject(predicate)
end

--- Returns a new Observable that produces values computed by extracting the given keys from the
-- tables produced by the original.
-- @arg {string...} keys - The key to extract from the table. Multiple keys can be specified to
--                         recursively pluck values from nested tables.
-- @returns {Observable}
function Observable:pluck(key, ...)
  if not key then return self end

  return Observable.create(function(observer)
    local function onNext(t)
      return observer:onNext(t[key])
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end):pluck(...)
end

--- Returns a new Observable that produces a single value computed by accumulating the results of
-- running a function on each value produced by the original Observable.
-- @arg {function} accumulator - Accumulates the values of the original Observable. Will be passed
--                               the return value of the last call as the first argument and the
--                               current values as the rest of the arguments.
-- @arg {*} seed - A value to pass to the accumulator the first time it is run.
-- @returns {Observable}
function Observable:reduce(accumulator, seed)
  return Observable.create(function(observer)
    local result = seed
    local first = true

    local function onNext(...)
      if first and seed == nil then
        result = ...
        first = false
      else
        result = accumulator(result, ...)
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      observer:onNext(result)
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces values from the original which do not satisfy a
-- predicate.
-- @arg {function} predicate - The predicate used to reject values.
-- @returns {Observable}
function Observable:reject(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local function onNext(...)
      if not predicate(...) then
        return observer:onNext(...)
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that skips over a specified number of values produced by the original
-- and produces the rest.
-- @arg {number=1} n - The number of values to ignore.
-- @returns {Observable}
function Observable:skip(n)
  n = n or 1

  return Observable.create(function(observer)
    local i = 1

    local function onNext(...)
      if i > n then
        observer:onNext(...)
      else
        i = i + 1
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that skips over values produced by the original until the specified
-- Observable produces a value.
-- @arg {Observable} other - The Observable that triggers the production of values.
-- @returns {Observable}
function Observable:skipUntil(other)
  return Observable.create(function(observer)
    local triggered = false
    local function trigger()
      triggered = true
    end

    other:subscribe(trigger, trigger, trigger)

    local function onNext(...)
      if triggered then
        observer:onNext(...)
      end
    end

    local function onError()
      if triggered then
        observer:onError()
      end
    end

    local function onCompleted()
      if triggered then
        observer:onCompleted()
      end
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that skips elements until the predicate returns falsy for one of them.
-- @arg {function} predicate - The predicate used to continue skipping values.
-- @returns {Observable}
function Observable:skipWhile(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local skipping = true

    local function onNext(...)
      if skipping then
        skipping = predicate(...)
      end

      if not skipping then
        return observer:onNext(...)
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that produces a single value representing the sum of the values produced
-- by the original.
-- @returns {Observable}
function Observable:sum()
  return self:reduce(function(x, y) return x + y end, 0)
end

--- Returns a new Observable that only produces the first n results of the original.
-- @arg {number=1} n - The number of elements to produce before completing.
-- @returns {Observable}
function Observable:take(n)
  n = n or 1

  return Observable.create(function(observer)
    if n <= 0 then
      observer:onCompleted()
      return
    end

    local i = 1

    local function onNext(...)
      observer:onNext(...)

      i = i + 1

      if i > n then
        observer:onCompleted()
      end
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that completes when the specified Observable fires.
-- @arg {Observable} other - The Observable that triggers completion of the original.
-- @returns {Observable}
function Observable:takeUntil(other)
  return Observable.create(function(observer)
    local function onNext(...)
      return observer:onNext(...)
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    other:subscribe(onCompleted, onCompleted, onCompleted)

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns a new Observable that produces elements until the predicate returns falsy.
-- @arg {function} predicate - The predicate used to continue production of values.
-- @returns {Observable}
function Observable:takeWhile(predicate)
  predicate = predicate or util.identity

  return Observable.create(function(observer)
    local taking = true

    local function onNext(...)
      if taking then
        taking = predicate(...)

        if taking then
          return observer:onNext(...)
        else
          return observer:onCompleted()
        end
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Runs a function each time this Observable has activity. Similar to subscribe but does not
-- create a subscription.
-- @arg {function=} onNext - Run when the Observable produces values.
-- @arg {function=} onError - Run when the Observable encounters a problem.
-- @arg {function=} onCompleted - Run when the Observable completes.
-- @returns {Observable}
function Observable:tap(_onNext, _onError, _onCompleted)
  _onNext = _onNext or util.noop
  _onError = _onError or util.noop
  _onCompleted = _onCompleted or util.noop

  return Observable.create(function(observer)
    local function onNext(...)
      _onNext(...)
      return observer:onNext(...)
    end

    local function onError(message)
      _onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      _onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that unpacks the tables produced by the original.
-- @returns {Observable}
function Observable:unpack()
  return self:map(util.unpack)
end

--- Returns an Observable that takes any values produced by the original that consist of multiple
-- return values and produces each value individually.
-- @returns {Observable}
function Observable:unwrap()
  return Observable.create(function(observer)
    local function onNext(...)
      local values = {...}
      for i = 1, #values do
        observer:onNext(values[i])
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that produces a sliding window of the values produced by the original.
-- @arg {number} size - The size of the window. The returned observable will produce this number
--                      of the most recent values as multiple arguments to onNext.
-- @returns {Observable}
function Observable:window(size)
  return Observable.create(function(observer)
    local window = {}

    local function onNext(value)
      table.insert(window, value)

      if #window >= size then
        observer:onNext(util.unpack(window))
        table.remove(window, 1)
      end
    end

    local function onError(message)
      return observer:onError(message)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- Returns an Observable that produces values from the original along with the most recently
-- produced value from all other specified Observables. Note that only the first argument from each
-- source Observable is used.
-- @arg {Observable...} sources - The Observables to include the most recent values from.
-- @returns {Observable}
function Observable:with(...)
  local sources = {...}

  return Observable.create(function(observer)
    local latest = setmetatable({}, {__len = util.constant(#sources)})

    local function setLatest(i)
      return function(value)
        latest[i] = value
      end
    end

    local function onNext(value)
      return observer:onNext(value, util.unpack(latest))
    end

    local function onError(e)
      return observer:onError(e)
    end

    local function onCompleted()
      return observer:onCompleted()
    end

    for i = 1, #sources do
      sources[i]:subscribe(setLatest(i), util.noop, util.noop)
    end

    return self:subscribe(onNext, onError, onCompleted)
  end)
end

--- @class ImmediateScheduler
-- @description Schedules Observables by running all operations immediately.
local ImmediateScheduler = {}
ImmediateScheduler.__index = ImmediateScheduler
ImmediateScheduler.__tostring = util.constant('ImmediateScheduler')

--- Creates a new ImmediateScheduler.
-- @returns {ImmediateScheduler}
function ImmediateScheduler.create()
  return setmetatable({}, ImmediateScheduler)
end

--- Schedules a function to be run on the scheduler. It is executed immediately.
-- @arg {function} action - The function to execute.
function ImmediateScheduler:schedule(action)
  action()
end

--- @class CooperativeScheduler
-- @description Manages Observables using coroutines and a virtual clock that must be updated
-- manually.
local CooperativeScheduler = {}
CooperativeScheduler.__index = CooperativeScheduler
CooperativeScheduler.__tostring = util.constant('CooperativeScheduler')

--- Creates a new CooperativeScheduler.
-- @arg {number=0} currentTime - A time to start the scheduler at.
-- @returns {Scheduler.CooperativeScheduler}
function CooperativeScheduler.create(currentTime)
  local self = {
    tasks = {},
    currentTime = currentTime or 0
  }

  return setmetatable(self, CooperativeScheduler)
end

--- Schedules a function to be run after an optional delay.
-- @arg {function} action - The function to execute. Will be converted into a coroutine. The
--                          coroutine may yield execution back to the scheduler with an optional
--                          number, which will put it to sleep for a time period.
-- @arg {number=0} delay - Delay execution of the action by a time period.
function CooperativeScheduler:schedule(action, delay)
  local task = {
    thread = coroutine.create(action),
    due = self.currentTime + (delay or 0)
  }

  table.insert(self.tasks, task)

  return Subscription.create(function()
    return self:unschedule(task)
  end)
end

function CooperativeScheduler:unschedule(task)
  for i = 1, #self.tasks do
    if self.tasks[i] == task then
      table.remove(self.tasks, i)
    end
  end
end

--- Triggers an update of the CooperativeScheduler. The clock will be advanced and the scheduler
-- will run any coroutines that are due to be run.
-- @arg {number=0} delta - An amount of time to advance the clock by. It is common to pass in the
--                         time in seconds or milliseconds elapsed since this function was last
--                         called.
function CooperativeScheduler:update(delta)
  self.currentTime = self.currentTime + (delta or 0)

  for i = #self.tasks, 1, -1 do
    local task = self.tasks[i]

    if self.currentTime >= task.due then
      local success, delay = coroutine.resume(task.thread)

      if success then
        task.due = math.max(task.due + (delay or 0), self.currentTime)
      else
        error(delay)
      end

      if coroutine.status(task.thread) == 'dead' then
        table.remove(self.tasks, i)
      end
    end
  end
end

--- Returns whether or not the CooperativeScheduler's queue is empty.
function CooperativeScheduler:isEmpty()
  return not next(self.tasks)
end

--- @class Subject
-- @description Subjects function both as an Observer and as an Observable. Subjects inherit all
-- Observable functions, including subscribe. Values can also be pushed to the Subject, which will
-- be broadcasted to any subscribed Observers.
local Subject = setmetatable({}, Observable)
Subject.__index = Subject
Subject.__tostring = util.constant('Subject')

--- Creates a new Subject.
-- @returns {Subject}
function Subject.create()
  local self = {
    observers = {},
    stopped = false
  }

  return setmetatable(self, Subject)
end

--- Creates a new Observer and attaches it to the Subject.
-- @arg {function|table} onNext|observer - A function called when the Subject produces a value or
--                                         an existing Observer to attach to the Subject.
-- @arg {function} onError - Called when the Subject terminates due to an error.
-- @arg {function} onCompleted - Called when the Subject completes normally.
function Subject:subscribe(onNext, onError, onCompleted)
  local observer

  if type(onNext) == 'table' then
    observer = onNext
  else
    observer = Observer.create(onNext, onError, onCompleted)
  end

  table.insert(self.observers, observer)

  return Subscription.create(function()
    for i = 1, #self.observers do
      if self.observers[i] == observer then
        table.remove(self.observers, i)
        return
      end
    end
  end)
end

--- Pushes zero or more values to the Subject. They will be broadcasted to all Observers.
-- @arg {*...} values
function Subject:onNext(...)
  if not self.stopped then
    for i = 1, #self.observers do
      self.observers[i]:onNext(...)
    end
  end
end

--- Signal to all Observers that an error has occurred.
-- @arg {string=} message - A string describing what went wrong.
function Subject:onError(message)
  if not self.stopped then
    for i = 1, #self.observers do
      self.observers[i]:onError(message)
    end

    self.stopped = true
  end
end

--- Signal to all Observers that the Subject will not produce any more values.
function Subject:onCompleted()
  if not self.stopped then
    for i = 1, #self.observers do
      self.observers[i]:onCompleted()
    end

    self.stopped = true
  end
end

Subject.__call = Subject.onNext

--- @class BehaviorSubject
-- @description A Subject that tracks its current value. Provides an accessor to retrieve the most
-- recent pushed value, and all subscribers immediately receive the latest value.
local BehaviorSubject = setmetatable({}, Subject)
BehaviorSubject.__index = BehaviorSubject
BehaviorSubject.__tostring = util.constant('BehaviorSubject')

--- Creates a new BehaviorSubject.
-- @arg {*...} value - The initial values.
-- @returns {Subject}
function BehaviorSubject.create(...)
  local self = {
    observers = {},
    stopped = false
  }

  if select('#', ...) > 0 then
    self.value = util.pack(...)
  end

  return setmetatable(self, BehaviorSubject)
end

--- Creates a new Observer and attaches it to the Subject. Immediately broadcasts the most recent
-- value to the Observer.
-- @arg {function} onNext - Called when the Subject produces a value.
-- @arg {function} onError - Called when the Subject terminates due to an error.
-- @arg {function} onCompleted - Called when the Subject completes normally.
function BehaviorSubject:subscribe(onNext, onError, onCompleted)
  local observer = Observer.create(onNext, onError, onCompleted)
  Subject.subscribe(self, observer)
  if self.value then
    observer:onNext(unpack(self.value))
  end
end

--- Pushes zero or more values to the BehaviorSubject. They will be broadcasted to all Observers.
-- @arg {*...} values
function BehaviorSubject:onNext(...)
  self.value = util.pack(...)
  return Subject.onNext(self, ...)
end

--- Returns the last value emitted by the Subject, or the initial value passed to the constructor
-- if nothing has been emitted yet.
-- @returns {*...}
function BehaviorSubject:getValue()
  return self.value and util.unpack(self.value)
end

Observable.wrap = Observable.buffer

return {
  util = util,
  Subscription = Subscription,
  Observer = Observer,
  Observable = Observable,
  ImmediateScheduler = ImmediateScheduler,
  CooperativeScheduler = CooperativeScheduler,
  Subject = Subject,
  BehaviorSubject = BehaviorSubject
}