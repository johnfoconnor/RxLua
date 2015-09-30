describe('skip', function()
  it('produces an error if its parent errors', function()
    local observable = Rx.Observable.fromValue(''):map(function(x) return x() end)
    expect(observable.subscribe).to.fail()
    expect(observable:skip(1).subscribe).to.fail()
  end)

  it('skips one element if no count is specified', function()
    local observable = Rx.Observable.fromTable({2, 3, 4}, ipairs):skip()
    expect(observable).to.produce(3, 4)
  end)

  it('produces no values if it skips over all of the values of the original', function()
    local observable = Rx.Observable.fromTable({1, 2}):skip(2)
    expect(observable).to.produce({})
  end)

  it('completes and does not fail if it skips over more values than were produced', function()
    local observable = Rx.Observable.fromValue(3):skip(5)
    local onNext, onError, onComplete = observableSpy(observable)
    expect(#onNext).to.equal(0)
    expect(#onError).to.equal(0)
    expect(#onComplete).to.equal(1)
  end)

  it('produces the elements it did not skip over', function()
    local observable = Rx.Observable.fromTable({4, 5, 6}, ipairs):skip(2)
    expect(observable).to.produce(6)
  end)
end)