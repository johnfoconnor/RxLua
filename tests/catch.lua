describe('catch', function()
  it('ignores errors if no handler is specified', function()
    expect(Rx.Observable.throw():catch()).to.produce.nothing()
  end)

  it('continues producing values from the specified observable if the source errors', function()
    local handler = Rx.Subject.create()
    local observable = Rx.Observable.create(function(observer)
      observer:onNext(1)
      observer:onNext(2)
      observer:onError('ohno')
      observer:onNext(3)
      observer:onCompleted()
    end)

    handler:onNext(5)

    local onNext = observableSpy(observable:catch(handler))

    handler:onNext(6)
    handler:onNext(7)
    handler:onCompleted()

    expect(onNext).to.equal({{1}, {2}, {6}, {7}})
  end)

  it('allows a function as an argument', function()
    local handler = function() return Rx.Observable.empty() end
    expect(Rx.Observable.throw():catch(handler)).to.produce.nothing()
  end)
end)
