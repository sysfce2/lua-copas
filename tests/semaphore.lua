-- make sure we are pointing to the local copas first
package.path = string.format("../src/?.lua;%s", package.path)


local copas = require "copas"
local now = copas.gettime
local semaphore = copas.semaphore



local test_complete = false
copas.loop(function()

  local sema = semaphore.new(10, 5, 1)
  assert(sema:get_count() == 5)

  assert(sema:take(3))
  assert(sema:get_count() == 2)

  local ok, _, err
  local start = now()
  _, err = sema:take(3, 0) -- 1 too many, immediate timeout
  assert(err == "timeout", "expected a timeout")
  assert(now() - start < 0.001, "expected it not to block with timeout = 0")

  start = now()
  _, err = sema:take(10, 0) -- way too many, immediate timeout
  assert(err == "timeout", "expected a timeout")
  assert(now() - start < 0.001, "expected it not to block with timeout = 0")

  start = now()
  _, err = sema:take(11) -- more than 'max'; "too many" error
  assert(err == "too many", "expected a 'too many' error")
  assert(now() - start < 0.001, "expected it not to block")

  start = now()
  _, err = sema:take(10) -- not too many, let's timeout
  assert(err == "timeout", "expected a 'timeout' error")
  assert(now() - start > 1, "expected it to block for 1s")

  assert(sema:get_count() == 2)

  --validate async threads
  local state = 0
  copas.addthread(function()
    assert(sema:take(5))
    print("got the first 5!")
    state = state + 1
  end)
  copas.addthread(function()
    assert(sema:take(5))
    print("got the next 5!")
    state = state + 2
  end)
  copas.pause(0.1)
  assert(state == 0, "expected state to still be 0")
  assert(sema:get_count() == 2, "expected count to still have 2 resources")

  assert(sema:give(4))
  assert(sema:get_count() == 1, "expected count to now have 1 resource")
  copas.pause(0.1)
  assert(state == 1, "expected 1 from the first thread to be added to state")

  assert(sema:give(4))
  assert(sema:get_count() == 0, "gave 4 more, so 5 in total, releasing 5, leaves 0 as expected")
  copas.pause(0.1)
  assert(state == 3, "expected 2 from the 2nd thread to be added to state")


  ok, err = sema:give(100)
  assert(not ok)
  assert(err == "too many")
  assert(sema:get_count() == 10)

  -- validate destroying
  assert(sema:take(sema:get_count())) -- empty the semaphore
  assert(sema:get_count() == 0, "should be empty now")
  local state = 0
  copas.addthread(function()
    local ok, err = sema:take(5)
    if ok then
      print("got 5, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.addthread(function()
    local ok, err = sema:take(5)
    if ok then
      print("got 5, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.pause(0.1)
  assert(sema:destroy())
  copas.pause(0.1)
  assert(state == 2, "expected 2 threads to error with 'destroyed'")

  -- only returns errors from now on, on all methods
  ok, err = sema:destroy();   assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:give(1);     assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:take(1);     assert(ok == nil and err == "destroyed", "expected an error")
  ok, err = sema:get_count(); assert(ok == nil and err == "destroyed", "expected an error")



  -- timeouts get cancelled upon destruction
  -- we set a timeout to 0.5 seconds, then destroy the semaphore
  -- the timeout should not execute
  -- Reproduce https://github.com/lunarmodules/copas/issues/118
  local track_table = setmetatable({}, { __mode = "v" })
  local sema = semaphore.new(10, 0, 0.5)
  track_table.sema = sema
  local state = 0
  track_table.coro = copas.addthread(function()
    local ok, err = sema:take(1)
    if ok then
      print("got one, this is unexpected")
    elseif err == "destroyed" then
      state = state + 1
    end
  end)
  copas.pause(0.1)
  assert(sema:destroy())
  copas.pause(0.1)
  assert(state == 1, "expected 1 thread to error with 'destroyed'")
  sema = nil

  local errors = 0
  copas.setErrorHandler(function(msg)
    print("got error: "..tostring(msg))
    print("--------------------------------------")
    errors = errors + 1
  end, true)

  collectgarbage()  -- collect garbage to force eviction from the semaphore registry
  collectgarbage()

  copas.pause(0.5) -- wait for the timeout to expire if it is still set
  assert(errors == 0, "expected no errors")

  test_complete = true
end)
assert(test_complete, "test did not complete!")
print("test success!")
