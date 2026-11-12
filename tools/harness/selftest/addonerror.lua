-- Noir Guides, GPLv3. See LICENSE.
-- Fixture for tools/test/harness.test.js: the assertions hold, but code running inside the mock client raised a
-- Lua error (first test) or made a forbidden call (second test). Both must fail, on purpose.
test("an error inside the addon fails the test", function()
  local c = HARNESS.Client.new({ files = {} })
  local f = c.G.CreateFrame("Frame")
  f:SetScript("OnEvent", function() error("raised inside the addon") end)
  f:RegisterEvent("PLAYER_LOGIN")
  c:fire("PLAYER_LOGIN")
end)
test("a forbidden call fails the test", function()
  local c = HARNESS.Client.new({ files = {} })
  c.G.CreateFrame("Frame"):RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end)
