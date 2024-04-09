-- PASTEBIN EXCLUDE

local function sleep(time_sec)
  print("Sleeping " .. time_sec)
end

local fs = {
  find = function(filename) return {"yeah"} end
}

local peripheral = {
  find = function(e) return {"something"} end
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


local function timeout(time_sec)
  os.setAlarm(os.time() + time_sec)
end

local function eventloop() -- routine
  local event, id = os.pullEvent('alarm')
  if id then
    FSM:timeout()
  end
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

  local monitor = peripheral.find("monitor")

  repeat
    eventloop()
  until false -- TODO: failure states
  
  FSM.ontrain_arrive = function(self, event, from, to) print("Choo choo") end
  FSM.onstatechange = function(self, event, from, to)
    monitor.clear()
    monitor.setCursorPos(1,1)
    monitor.write("Station state: " .. FSM.current)

    local f = fs.open("./recover.txt", "w")
    f.write(to)
  end
  FSM:train_arrive()
  FSM:collect()
  FSM:timeout()
end

main()