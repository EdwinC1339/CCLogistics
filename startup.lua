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
  inactive = {}, -- We need to pulse the train_leave_output signal, so we'll do that manually in the onenterinactive callback.
  sig_wait = {},
  input = {"train_psi_output"},
  recoup_wait = {"recoup_output"},
  output = {"factory_output"}
}

-- Map each input channel to an event. On rising edge for each of these channels, we call the callback.
local redstone_callbacks = {
  train_arrive_input  = function() FSM:train_arrive() end,
  buffer_empty_input  = function() FSM:recoup_empty() end,
  collect_input       = function() FSM:collect()      end
}

local function timeout(time_sec)
  os.setAlarm(os.time() + time_sec)
end

local function eventloop() -- routine
  local event, id = os.pullEvent('alarm')
  if id then
    FSM:timeout()
  end
end

local function initialize_channels(map)
  local channels = {}
  for index, value in pairs(map) do
    for peripheral_id, side in string.gmatch(value, "([%w_]+)%.(%w+)") do
      channels[index] = {peripheral = peripheral.wrap(peripheral_id), side = side}
    end 
  end
  return channels
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

local function main() -- routine
  local first_state = 'inactive'
  local loaded_state = load_state()
  if loaded_state then first_state = loaded_state end -- If there was a previous state, we recover it.

  FSM = machine.create({
    initial = 'loading',
    events = {
      { name = 'train_arrive',  from = 'inactive',  to = 'sig_wait' },
      { name = 'timeout', from = 'sig_wait', to = 'input' },
      { name = 'timeout', from = 'input',    to = 'recoup' },
      { name = 'timeout', from = 'output', to = 'inactive' },
      { name = 'timeout', from = 'recoup_wait', to = 'inactive'},
      { name = 'collect', from = 'sig_wait', to = 'output'},
      { name = 'recoup_empty', from = 'recoup', to = 'recoup_wait'},

      { name = 'load', from = 'loading', to = first_state}
  }})

  FSM:load()

  local channels = initialize_channels(channel_map)
  pretty.pretty_print(channels)
  local monitor = peripheral.find("monitor")
  
  FSM.ontrain_arrive = function(self, event, from, to) print("Choo choo") end
  FSM.onstatechange = function(self, event, from, to)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.setTextColor(colors.white)
    monitor.write("Station state: ")
    monitor.setTextColor(colors.lime)
    monitor.write(to)

    local f = io.open("./recover.txt", "w")
    if f then
      f:write(to)
      f:close()
    end
  end
  FSM:train_arrive()
  FSM:collect()
  FSM:timeout()
end

main()