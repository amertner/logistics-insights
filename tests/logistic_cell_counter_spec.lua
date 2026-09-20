local mock = require("tests.mocks.factorio")

describe("logistic_cell_counter", function()
  local cell_counter, chunker_mod

  before_each(function()
    mock.fresh()
    storage.global = { chunk_size = 400, gather_quality_data = true }
    storage.networks = {}
    chunker_mod = require("scripts.chunker")
    cell_counter = require("scripts.logistic-cell-counter")
  end)

  local function make_networkdata()
    local nwd = {
      id = 1,
      cell_chunker = chunker_mod.new(),
      bot_items = {},
      unpowered_roboport_list = {},
      idle_bot_qualities = {}, roboport_qualities = {},
      charging_bot_qualities = {}, waiting_bot_qualities = {},
      total_cells = 0,
      players_set = {},
    }
    storage.networks[1] = nwd
    return nwd
  end

  --- A cell whose roboport may or may not be powered, with no bots at it
  local function make_cell(unit_number, powered)
    local owner = {
      valid = true,
      unit_number = unit_number,
      quality = { name = "normal" },
      is_connected_to_electric_network = function() return powered end,
      get_inventory = function() return nil end,
      logistic_network = { network_id = 1 },
    }
    return {
      valid = true,
      owner = owner,
      charging_robot_count = 0,
      to_charge_robot_count = 0,
      charging_robots = {},
      to_charge_robots = {},
    }
  end

  local function make_network(cells)
    return { valid = true, cells = cells, all_logistic_robots = 0, available_logistic_robots = 0 }
  end

  local function scan(nwd, network)
    cell_counter.init_background_processing(nwd, network)
    while not cell_counter.is_scanning_done(nwd) do
      cell_counter.process_next_chunk(nwd)
    end
  end

  it("lists an unpowered roboport", function()
    local nwd = make_networkdata()
    scan(nwd, make_network({ make_cell(1, true), make_cell(2, false) }))
    assert.are.equal(1, #nwd.unpowered_roboport_list)
    assert.are.equal(2, nwd.unpowered_roboport_list[1].unit_number)
    assert.are.equal(2, nwd.total_cells)
  end)

  it("lists an unpowered roboport when quality data is not gathered", function()
    -- The check used to live inside the quality branch, so turning that setting off silently
    -- turned the unpowered roboport suggestion off as well
    storage.global.gather_quality_data = false
    local nwd = make_networkdata()
    scan(nwd, make_network({ make_cell(1, true), make_cell(2, false) }))
    assert.are.equal(1, #nwd.unpowered_roboport_list)
    assert.is_nil(next(nwd.roboport_qualities), "no quality data gathered")
  end)
end)
