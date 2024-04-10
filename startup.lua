-- PASTEBIN EXCLUDE

local function sleep(time_sec)
  print("Sleeping " .. time_sec)
end

local fs = {
  find = function(filename) return {"yeah"} end
}

local peripheral = {
  find = function(e) return {
    clear = function () end,
    write = function (_) end,
    setCursorPos = function (_, _) end
  } end
}

Events = {}

local function add_event(event)
  table.insert(Events, event)
  return #Events -- should be unique and work as an event ID
end

os.setAlarm = function(time) add_event({e_type = 'alarm', time = time}) end

os.pullEvent = function(e_type)
  local to_remove = nil
  local event = nil
  for i, e in ipairs(Events) do
    if e.e_type == e_type then to_remove = i; event = e; break end
  end

  if to_remove and event then table.remove(Events, to_remove) end
  return event, to_remove
end

-- END PASTEBIN EXCLUDE
local machine = require('statemachine')
local channel_map = require('channelmap')
local pretty = require('cc.pretty')

local input_cycle_time = 12 -- Enough time for all inputs to reach production and recoup buffer
local flush_time = 10 -- Enough time for items to go from output and recoup buffer to train
local output_cycle_time = 6 -- Should be a small amount of time to extract resources

-- We're injecting some functions to make the rs module emulate a redrouter.
rs.getName = function ()
  return "self"
end
rs.isSelf = true

-- When the computer loads up it will set all the corresponding channels into these values. States will each have a list of inputs to set to the opposite value.
local redstone_defaults = {
  recoup_output       = true,
  train_psi_output    = true,
  train_leave_output  = false,
  factory_output      = true
}

-- When we load into any state, we activate the corresponding channels.
-- Activation means switching into the opposite of the default state.
local state_output_map = {
  inactive = {},
  sig_wait = {},
  flush = {},
  input = {train_psi_output = true},
  input_with_recoup = {train_psi_output = true},
  recoup = {recoup_output = true},
  output = {factory_output = true},
  leave = {train_leave_output = true}
}

-- Map each input channel to an event.
-- On rising edge for each of these channels, we call the callback.
local rising_callbacks = {
  train_arrive_input              = function() FSM:train_arrive() end,
  buffer_stockpile_switch_input   = function() FSM:recoup_rising() end,
  collect_input                   = function() FSM:collect()      end
}

-- On falling edge for each of these channels, we call the callback.
local falling_callbacks = {
  buffer_stockpile_switch_input   = function () FSM:recoup_falling() end
}

-- When we pull a timeout event, we ignore it if its id is equal to this mask.
local timeout_mask = nil
local function timeout(time_sec)
  return os.startTimer(time_sec)
end

local function initialize_channels(map)
  local channels = {}
  for index, value in pairs(map) do
    for peripheral_id, side in string.gmatch(value, "([%w_]+)%.(%w+)") do
      local p = peripheral_id == "self" and rs or peripheral.wrap(peripheral_id) -- When peripheral_id = self we just set the peripheral context to rs.
      channels[index] = {peripheral = p, side = side}
    end
  end
  return channels
end

-- Generate the inverse of a 1:1 table
local function invert_map(map)
  local inverted = {}
  for key, value in pairs(map) do
    inverted[value] = key
  end
  return inverted
end

-- Get a table that has all 6 sides and whether they're on or off
local function router_get_state(router)
  local state = {}
  for _, side in ipairs(rs.getSides()) do
    state[side] = router.getInput(side)
  end
  return state
end

-- Get a table that has the state of all routers
local function get_io_state(routers)
  local state = {}
  for _, router in ipairs(routers) do
    if router.isSelf then
      state[router.getName()] = router_get_state(router) 
    else
      local router_id = peripheral.getName(router)
      state[router_id] = router_get_state(router)
    end
  end
  return state
end

-- Get an array of string formatted sides that changed from the previous state.
-- Sides are formatted as they are in the channelmap, eg "redrouter3.back" or "self.left" for easy back-searching.
local function get_state_changes(prev_state, cur_state)
  local rising_edge_sides = {}
  local falling_edge_sides = {}
  for router_id, state in pairs(cur_state) do
    for side, value in pairs(state) do
      if value and not prev_state[router_id][side] then
        local address = router_id .. '.' .. side
        table.insert(rising_edge_sides, address)
      end

      if not value and prev_state[router_id][side] then
        local address = router_id .. '.' .. side
        table.insert(falling_edge_sides, address)
      end
    end
  end
  return rising_edge_sides, falling_edge_sides
end

local function load_state()
  if #fs.find('recover.txt') > 0 then
    local lines = {}
    local i = 1
    for line in io.lines('recover.txt') do
      lines[i] = line
    end
    return lines[1] -- TODO: extend recover to include other parameters
  else
    return nil
  end
end

local function set_channel(channels, channel_name, activation)
  local channel_entry = channels[channel_name]
  local context = channel_entry.peripheral
  local side = channel_entry.side
  context.setOutput(side, activation)
end

-- Handle events and return the new redstone state.
local function eventloop(prev_state, routers, backsearch) -- routine
  local event, id = os.pullEvent()
  if event == 'timer' and id ~= timeout_mask then
    FSM:timeout()
  elseif event == 'redstone' then
    local new_state = get_io_state(routers)
    local rising_edges, falling_edges = get_state_changes(prev_state, new_state)
    
    -- Now go through all the rising and falling edges and call the callbacks.
    for _, side in ipairs(rising_edges) do
      local channel_name = backsearch[side]
      if channel_name then
        print("Rising edge signal received on channel " .. channel_name)
        local callback = rising_callbacks[channel_name]
        if callback then callback() end
      end
    end

    for _, side in ipairs(falling_edges) do
      local channel_name = backsearch[side]
      
      if channel_name then
        print("Falling edge signal received on channel " .. channel_name)
        local callback = falling_callbacks[channel_name]
        if callback then callback() end
      end
    end
    return new_state
  end
  return prev_state
end

local function main() -- routine
  local channels = initialize_channels(channel_map)
  local backsearch = invert_map(channel_map)
  local monitor = peripheral.find("monitor")

  local routers = { peripheral.find("redrouter") }
  table.insert(routers, rs) -- rs emulates the computer as a redrouter.
  local rs_state = get_io_state(routers)

  local first_state = 'inactive'
  local loaded_state = load_state()
  if loaded_state then first_state = loaded_state end -- If there was a previous state, we recover it.

  FSM = machine.create({
    initial = 'loading',
    events = {
      { name = 'train_arrive',  from = 'inactive',  to = 'sig_wait' },
      { name = 'timeout', from = 'sig_wait', to = 'input' },
      { name = 'timeout', from = 'input',    to = 'leave' },
      { name = 'timeout', from = 'output', to = 'leave' },
      { name = 'timeout', from = 'recoup_wait', to = 'leave'},
      { name = 'timeout', from = 'leave', to = 'inactive'},
      { name = 'collect', from = 'sig_wait', to = 'output'},
      { name = 'collect', from = 'inactive', to = 'output'}, -- Collect signal may arrive before train arrive signal
      { name = 'recoup_rising', from = 'input', to = 'recoup' },
      { name = 'recoup_falling', from = 'recoup', to = 'recoup_flush'},

      { name = 'load', from = 'loading', to = first_state}
  }})

  -- When in sig_wait, we timeout and put the id here. If we receive the collect signal, we mask over that timeout to avoid timing
  -- out of the output cycle early.
  local sig_ticket = nil

  FSM.ontrain_arrive = function(self, event, from, to) print("Choo choo") end
  FSM.onleave = function (self, event, from, to)
    timeout(0.5) -- Tell train to get out fast
  end
  FSM.onsig_wait = function (self, event, from, to)
    sig_ticket = timeout(0.5) -- Pulse comes quick
  end
  FSM.onoutput = function (self, event, from, to)
    timeout_mask = sig_ticket -- disregard the sig_wait timeout, we want to wait for the full cycle!
    timeout(output_cycle_time)
  end
  FSM.oninput = function (self, event, from, to)
    timeout(input_cycle_time) -- This timeout takes us out of input OR input with recoup.
  end
  FSM.onflush = function (self, event, from, to)
    timeout(flush_time)
  end
  FSM.onstatechange = function(self, event, from, to)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.setTextColor(colors.magenta)
    monitor.write("Station state: ")
    monitor.setTextColor(colors.white)
    monitor.write(to)

    for channel_name, default in pairs(redstone_defaults) do
      local activation = default
      if state_output_map[to][channel_name] then
        activation = not activation
      end
      set_channel(channels, channel_name, activation)
    end

    local f = io.open("./recover.txt", "w")
    if f then
      f:write(to)
      f:close()
    end
  end

  FSM:load()

  local event_count = 0
  while true do
    rs_state = eventloop(rs_state, routers, backsearch)
    event_count = event_count + 1
    print(event_count .. " events")
  end
end

main()