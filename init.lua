--- Qemistry, Queue Manager for Mudlet
--- @module Qemistry

local error = error
local ipairs = ipairs
local pairs = pairs
local string = string
local table = table
local type = type

--- Primary Qemistry interface.
--- @table Qemistry
local Qemistry = {}

local master_list = {}
local function verify_queue (queue, func)
  local chk = true
  local msg
  if type( queue ) ~= "string" then
    msg = string.format("Qemistry: Must pass a string value to Qemistry.%s",
        func)
    chk = false
  end
  if not master_list[queue] then
    msg = string.format("Qemistry: Queue '%s' does not exist.", queue)
    chk = false
  end
  return chk, msg
end

--- Executes a single queue or all queues
-- When called with an argument, it calls that Queue's Do function.
--
-- When called without an argument, it calls all Queues' Do functions.
-- @string queue The name of the Queue to be executed.
function Qemistry.Do (queue)
  if not queue then
    for _, queue in pairs( master_list ) do
      queue:Do()
    end
  else
    ok, err = verify_queue( queue, "Do" )
    if ok then
      master_list[queue]:Do()
    else
      error( err, 2 )
    end
  end
end

--- Removes a Queue from the master list.
-- @string queue The name of the Queue to be deleted.
function Qemistry.Delete (queue)
  local ok, err = verify_queue( queue, "Delete" )
  if ok then
    master_list[queue] = nil
  else
    error( err, 2 )
  end
end

--- A list of valid Queue options.
-- @table valid_options
-- @field strict_order
-- @field single_step
local valid_options = {
  "strict_order",
  "single_step",
}
local function verify_option (option)
  local chk = true
  local msg
  if not valid_options[option] then
    chk = false
    msg = "Qemistry: Invalid Option passed to Queue constructor."
  end
  return chk, msg
end

--- Queue constructor.
-- @function Queue
-- @string name The name of the new Queue.
-- @tparam table|string|bool|function conditions The conditions upon which this
--  Queue operates (ex. Balance, Equilibrium).
--  This may be a table of strings or functions.
--  This may be a string, a function, or true.
--  Functions must ultimately return a boolean value.
--  Strings must be the "address" of a boolean value ("my_system.balance").
-- @tparam[opt] table options A table of strings or a string. Values must be one
--  of the @{valid_options}.
-- @treturn Queue
-- @usage
--  local queue = Qemistry.Queue("my_queue", "my_system.balance_variables.balance")
--  local queue = Qemistry.Queue("my_queue", "balance_variable")
--  local queue = Qemistry.Queue("my_queue", {"balance", "equilibrium"})
--  local queue = Qemistry.Queue("my_queue", {"my_system.balance", "my_system.equilibrium"})
--  local queue = Qemistry.Queue("my_queue", function () return my_system.balance end)
--  local queue = Qemistry.Queue("my_queue", {"my_system.balance", function () return my_system.equilibrium end})
--  local queue = Qemistry.Queue("my_queue", somePredefinedFunction())
--  local queue = Qemistry.Queue("my_queue", true)
--  local queue = Qemistry.Queue("my_queue", "balance", "strict_order")
--  local queue = Qemistry.Queue("my_queue", "balance", {"strict_order", "single_step"})
local function new (name, conditions, options)
  -- A scoped block of sanity checks.
  -- Makes sure all values passed are valid.
  do
    if not name then
      error("Qemistry: Must pass a Name as the first argument of Queue constructor.", 2)
    else
      if type( name ) ~= "string" then
        error("Qemistry: Name passed to Queue constructor must be a string.", 2)
      end
    end
    if master_list[name] then
      error("Qemistry: A Queue with this name already exists.", 2)
    end
    if not conditions then
      error("Qemistry: Must pass Condition(s) as second argument of Queue constructor.", 2)
    else
      if type( conditions ) == "table" then
        for _,cond in ipairs( conditions ) do
          local bad_types = {["table"] = true, ["number"] = true, ["boolean"] = true}
          if bad_types[type( cond )] then
            error("Qemistry: Members of Conditional table may not be tables, numbers, or booleans.", 2)
          end
        end
      elseif type( conditions ) == "number" then
        error("Qemistry: Conditional passed to Queue constructor may not be a number.", 2)
      end
    end

    if options then
      if type( options ) == "table" then
        for _,opt in ipairs( options ) do
          local ok, err = verify_option( opt )
          if not ok then
            error( err, 2 )
          end
        end
      elseif type( options ) == "string" then
        local ok, err = verify_option( options )
        if not ok then
          error( err, 2 )
        end

        -- We translate this into a table, as that is the format
        -- preferred by Do().
        options = {options}
      else
        error("Qemistry: May only pass a table or string as third argument of Queue constructor.", 2)
      end
    else
      options = {}
    end
  end

  --- @type Queue
  local queue = {}

  local actions = {}
  local action_count = 0

  --- Properties
  --- @section
  local properties = {
    Name = {
      --- Returns the name of the Queue.
      -- @function self.Name.get
      -- @treturn string
      get = function ()
        return name
      end
    },
    Conditions = {
      --- Returns the Queue's conditions. This is either a string, a function, a
      -- boolean, or a table of strings or functions.
      -- @function self.Conditions.get
      -- @treturn table
      get = function ()
        if type( conditions ) == "table" then
          local copy = {}
          for i,cond in ipairs( conditions ) do
            copy[i] = cond
          end
          return copy
        else
          return conditions
        end
      end
    },
    Options = {
      --- Returns a table containing the Queue's options.
      -- @function self.Options.get
      -- @treturn table
      get = function ()
        if options then
          if type( options ) == "table" then
            local copy = {}
            for i,opt in ipairs( options ) do
              copy[i] = opt
            end
            return copy
          else
            return options
          end
        end
      end
    },
    Actions = {
      --- Returns a copy of the Queue's actions table.
      -- @function self.Actions.get
      -- @treturn table
      get = function ()
        if action_count > 0 then
          local copy = {}
          for i,act in ipairs( actions ) do
            copy[i] = act
          end
          return copy
        end
      end
    }
  }
  --- @section end

  local function get_field (f)
    local v = _G
    for k in f:gfind("[%w_]+") do
      v = v[k]
    end
    return v
  end

  local function check_conditions (condition)
    local chk = true
    local function do_check ( cond )
      local cond_type = type( cond )
      if cond_type == "table" then
        for _, c in ipairs( cond ) do
          do_check( c )
        end
      else
        if cond_type == "string" then
          chk = get_field( cond )
        elseif cond_type == "function" then
          chk = cond()
        elseif cond_type == "boolean" then
          chk = cond
        end
      end
    end

    do_check( condition )
    return chk
  end

  local function exec_code (code)
    local c_type = type( code )
    if c_type == "table" then
      for _, c in ipairs( code ) do
        exec_code( c )
      end
    else
      if c_type == "string" then
        send( code )
      elseif c_type == "function" then
        code()
      end
    end
  end

  --- Iterates through a Queue's Actions, executing them sequentially.
  -- Unless otherwise specified by an Option, it will execute all Actions that
  -- do not consume a Condition.

  -- It will then step through each Action that consumes a Condition; it will
  -- then verify (after .5 seconds) that the Condition was set to false. If the
  -- Condition is still true, it attempt to redo the last Action ad infinitum.
  function queue:Do ()
    -- Don't bother if there's nothing to do.
    if action_count > 0 then
      -- Check the Queue's Conditions.
      if check_conditions( conditions ) then
        local action = actions[1]
        local action_index = 1

        -- Find our first Action, respecting required,
        -- consumed, and our Options.
        if not options["strict_order"] then
          for i, act in ipairs( actions ) do
            if not act.consumed then
              action = act
              action_index = i
              break
            end
          end
        end

        -- If the Action has its own Conditions, we check
        -- them here. If it doesn't, we're assuming the Queue's
        -- Conditions, so we just proceed.
        local do_action = true
        for _,cond in ipairs( {"required", "consumed"} ) do
          if action[cond] then
            do_action = check_conditions( action[cond] )
          end
        end

        if do_action then
          exec_code( action.code )

          table.remove( actions, action_index )
          action_count = action_count - 1

          -- If it consumes a Condition, we have to pause
          -- our iteration and wait for verification.
          -- If the Condition is still true in .5 seconds,
          -- then we assume the Action did not properly execute.
          -- This is somewhat reliant on the end-user to
          -- prepare their system properly.
          if action.consumed then
            local consumed = action.consumed
            local c_type = type( consumed )

            if c_type == "table" then
              tempTimer( 0.5, function ()
                local redo = 0
                for _, condition in ipairs( consumed ) do
                  local co_type = type( condition )
                  if co_type == "string" then
                    if get_field( condition ) then
                      redo = redo + 1
                    end
                  elseif co_type == "function" then
                    if condition() then
                      redo = redo + 1
                    end
                  end
                end

                if redo == #consumed then
                  table.insert( actions, 1, action )
                  action_count = action_count + 1
                  queue:Do()
                end
              end )
            else
              tempTimer( 0.5, function ()
                if c_type == "string" then
                  if get_field( consumed ) then
                    table.insert( actions, 1, action )
                    action_count = action_count + 1
                    queue:Do()
                  end
                elseif c_type == "function" then
                  if consumed() then
                    table.insert( actions, 1, action )
                    action_count = action_count + 1
                    queue:Do()
                  end
                end
              end )
            end
          -- This Action did not consume a Condition, so we want
          -- to continue iterating.
          elseif action_count > 0 then
            if not options["single_step"] then
              queue:Do()
            end
          end
        end
      end
    end
  end

  --- Adds an Action to the Queue.
  -- @tparam string|function|table action If it is a string, it assumes the
  --  Queue's Conditions. That string will be passed to the MuD via send().
  --
  --  If it is a function, it assumes the Queue's Conditions. That function will
  --  be called directly.
  --
  --  If it is a table, that must be a list of strings or functions, or a
  --  formatted Action table. The strings and functions behave as above. The
  --  formatted table must contain the field "code", and optionally one or both
  --  of "required" and "consumed". "required" and "consumed" function as do
  --  Queue Conditions. The "code" functions as a non-formatted action above.
  -- @usage
  --  queue:Add(function () echo( "Do stuff!") end)
  --  queue:Add("Do stuff!")
  --  queue:Add({code = {"Do stuff!", "Do more stuff!"}})
  --  queue:Add({function () echo( "Do stuff!") end, function () echo( "Do more stuff!") end})
  --  queue:Add({"Do stuff!", function () echo( "Do more stuff!") end})
  --  queue:Add({code = "code", required = "my_system.balance"})
  --  queue:Add({code = "code", consumed = "my_system.balance"})
  --  queue:Add({code = "code", required = "my_system.balance", consumed = "my_system.equilibrium"})
  --  queue:Add({code = "code", required = "my_system.balance", consumed = function () return my_system.equilibrium end})
  --  queue:Add({code = "code", required = {"my_system.balance", "my_system.equilibrium"})
  --  queue:Add({code = "code", required = {function () return my_system.balance end, somePredefinedFunction()}})
  function queue:Add (action)
    if not action then
      error("Qemistry: Cannot add an empty Action to the Queue.", 2)
    end

    local code_types = {["string"] = true, ["function"] = true}
    if type( action ) == "table" then
      if not action.code then
        for _,code in ipairs( action ) do
          if not code_types[type( code )] then
            error("Qemistry: Value in Action table must be a table, string, or function.", 2)
          end
        end

        actions[#actions+1] = {code = action}
        action_count = action_count + 1
      else
        for _,field in ipairs( {"code", "required", "consumed"} ) do
          if action[field] then
            local f_type = type( field )
            if f_type == "table" then
              for _, v in ipairs( action[bhvr] ) do
                if not code_types[type( v )] then
                  error(string.format("Qemistry: Value in Action table '%s' must be a string or function.", field), 2)
                end
              end
            elseif not code_types[f_type] then
              error(string.format("Qemistry: Action field '%s' must be a table, string, or function.", field), 2)
            end
          end
        end

      -- If it passes all of those validation checks, then it's already
      -- formatted properly. We just append it to the actions table.
      actions[#actions+1] = action
      action_count = action_count + 1
      end

    elseif code_types[type( action )] then
      -- We translate it to the format expected by Do().
      actions[#actions+1] = {code = action}
      action_count = action_count + 1
    else
      error("Qemistry: Invalid Action passed to Add. Must be table, string, or function.", 2)
    end
  end

  --- Empties the Queue's Action list.
  function queue:Reset ()
    actions = {}
    action_count = 0
  end

  setmetatable( queue, {
    __index = function (_, key)
      if properties[key] then
        return properties[key].get()
      end
    end,
    __newindex = function (_, key, value)
      if properties[key] and properties[key].set then
        if properties[key].set then
          properties[key].set( value )
        end
      else
        error(string.format("Qemistry: Attempt to modify unknown Queue Property '%s'.", key), 2)
      end
    end
    }
  )
  master_list[name] = queue
  return queue
end

Qemistry.Queue = new
setmetatable( Qemistry, {
  __index = function (_, key)
    if key == "Queues" then
      local copy = {}
      for name, queue in pairs( master_list ) do
        copy[name] = queue
      end
      return copy
    end
  end,
  __newindex = function ()
    error("Qemistry: May not modify Qemistry object.", 2)
  end,
  }
)
return Qemistry
