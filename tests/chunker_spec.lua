local mock = require("tests.mocks.factorio")

describe("chunker", function()
  local chunker

  before_each(function()
    mock.fresh()
    -- global-data reads from storage.global — initialise it
    storage.global = {
      chunk_size = 400,
      gather_quality_data = true,
    }
    chunker = require("scripts.chunker")
  end)

  local function noop() end
  local function make_entities(n)
    local list = {}
    for i = 1, n do
      list[i] = { valid = true, id = i }
    end
    return list
  end

  describe("new()", function()
    it("creates a chunker in idle state", function()
      local c = chunker.new()
      assert.are.equal("idle", c.state)
      assert.is_true(c:needs_data())
      assert.is_true(c:is_done_processing())
    end)

    it("sets default chunk size from global settings", function()
      local c = chunker.new()
      assert.are.equal(400, c.CHUNK_SIZE)
    end)
  end)

  describe("initialise_chunking()", function()
    it("transitions to processing with a non-empty list", function()
      local c = chunker.new()
      local entities = make_entities(5)
      c:initialise_chunking(1, entities, nil, {}, noop)
      assert.are.equal("processing", c.state)
      assert.are.equal(5, c.processing_count)
    end)

    it("transitions to finalising with nil list", function()
      local c = chunker.new()
      c:initialise_chunking(1, nil, nil, {}, noop)
      assert.are.equal("finalising", c.state)
    end)

    it("transitions to finalising with empty list", function()
      local c = chunker.new()
      c:initialise_chunking(1, {}, nil, {}, noop)
      assert.are.equal("finalising", c.state)
    end)

    it("transitions to fetching with a function", function()
      local c = chunker.new()
      c:initialise_chunking(1, function() return make_entities(3) end, nil, {}, noop)
      assert.are.equal("fetching", c.state)
    end)

    it("calls on_init with partial_data and initial_data", function()
      local c = chunker.new()
      local received_partial, received_init
      local init_fn = function(pd, id)
        received_partial = pd
        received_init = id
      end
      c:initialise_chunking(1, nil, "my_init_data", {}, init_fn)
      assert.are.equal(c.partial_data, received_partial)
      assert.are.equal("my_init_data", received_init)
    end)

    it("respects divisor parameter", function()
      local c = chunker.new()
      c:initialise_chunking(1, nil, nil, {}, noop, 4)
      assert.are.equal(100, c.CHUNK_SIZE) -- 400 / 4
    end)
  end)

  describe("process_chunk()", function()
    it("resolves fetcher on first call, processes on second", function()
      local c = chunker.new()
      local entities = make_entities(3)
      local processed = {}
      c:initialise_chunking(1, function() return entities end, nil, {}, noop)

      -- First call: resolve fetcher
      c:process_chunk(function() end)
      assert.are.equal("processing", c.state)

      -- Second call: process entities
      c:process_chunk(function(entity, pd)
        table.insert(processed, entity.id)
        return 1
      end)
      assert.are.equal(3, #processed)
      assert.are.equal("finalising", c.state)
    end)

    it("transitions to finalising when fetcher returns empty", function()
      local c = chunker.new()
      c:initialise_chunking(1, function() return {} end, nil, {}, noop)
      c:process_chunk(function() return 1 end)
      assert.are.equal("finalising", c.state)
    end)

    it("processes in chunks respecting CHUNK_SIZE", function()
      storage.global.chunk_size = 5
      -- Reload to pick up new chunk size
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      local entities = make_entities(12)
      local process_count = 0
      c:initialise_chunking(1, entities, nil, {}, noop)

      -- First chunk: 5 entities
      c:process_chunk(function(e, pd)
        process_count = process_count + 1
        return 1
      end)
      assert.are.equal(5, process_count)
      assert.are.equal("processing", c.state)

      -- Second chunk: 5 more
      c:process_chunk(function(e, pd)
        process_count = process_count + 1
        return 1
      end)
      assert.are.equal(10, process_count)
      assert.are.equal("processing", c.state)

      -- Third chunk: 2 remaining
      c:process_chunk(function(e, pd)
        process_count = process_count + 1
        return 1
      end)
      assert.are.equal(12, process_count)
      assert.are.equal("finalising", c.state)
    end)

    it("skips invalid entities", function()
      local c = chunker.new()
      local entities = {
        { valid = true, id = 1 },
        { valid = false, id = 2 },
        { valid = true, id = 3 },
      }
      local processed_ids = {}
      c:initialise_chunking(1, entities, nil, {}, noop)
      c:process_chunk(function(entity, pd)
        table.insert(processed_ids, entity.id)
        return 1
      end)
      assert.are.same({1, 3}, processed_ids)
    end)

    it("respects cost returned by callback", function()
      storage.global.chunk_size = 3
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      local entities = make_entities(10)
      local process_count = 0
      c:initialise_chunking(1, entities, nil, {}, noop)

      -- Each entity costs 2, so chunk of 3 budget processes ~1-2 entities
      c:process_chunk(function(e, pd)
        process_count = process_count + 1
        return 2
      end)
      -- With budget 3 and cost 2: first entity costs 2 (consumed=2 < 3), second costs 2 (consumed=4 >= 3, stop)
      assert.are.equal(2, process_count)
    end)

    it("does nothing in idle state", function()
      local c = chunker.new()
      local called = false
      c:process_chunk(function() called = true; return 1 end)
      assert.is_false(called)
    end)
  end)

  describe("finalise_run()", function()
    it("calls completion callback and transitions to idle", function()
      local c = chunker.new()
      c:initialise_chunking(1, nil, nil, {}, noop)
      assert.are.equal("finalising", c.state)

      local completed = false
      c:finalise_run(function(pd, gather, nid)
        completed = true
        assert.are.equal(1, nid)
      end)
      assert.is_true(completed)
      assert.are.equal("idle", c.state)
    end)

    it("does nothing if not in finalising state", function()
      local c = chunker.new()
      local called = false
      c:finalise_run(function() called = true end)
      assert.is_false(called)
    end)
  end)

  describe("full lifecycle", function()
    it("init -> process -> finalise -> idle", function()
      local c = chunker.new()
      local entities = make_entities(3)
      local total = 0

      c:initialise_chunking(1, entities, nil, {},
        function(pd) pd.count = 0 end)

      c:process_chunk(function(entity, pd)
        pd.count = pd.count + 1
        return 1
      end)
      assert.are.equal(3, c.partial_data.count)
      assert.is_true(c:needs_finalisation())

      local final_count
      c:finalise_run(function(pd) final_count = pd.count end)
      assert.are.equal(3, final_count)
      assert.is_true(c:is_done_processing())
    end)
  end)

  describe("state queries", function()
    it("num_chunks() calculates correctly", function()
      local c = chunker.new()
      c:initialise_chunking(1, make_entities(1000), nil, {}, noop)
      assert.are.equal(3, c:num_chunks()) -- 1000/400 = 2.5 -> ceil = 3
    end)

    it("num_chunks() returns 0 for empty list", function()
      local c = chunker.new()
      assert.are.equal(0, c:num_chunks())
    end)

    it("get_progress() tracks current and total", function()
      storage.global.chunk_size = 2
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      c:initialise_chunking(1, make_entities(5), nil, {}, noop)

      local prog = c:get_progress()
      assert.are.equal(1, prog.current)
      assert.are.equal(5, prog.total)

      c:process_chunk(function() return 1 end)
      prog = c:get_progress()
      assert.are.equal(3, prog.current) -- processed 2, now at index 3
    end)
  end)

  describe("reset()", function()
    it("completes current run and re-initialises", function()
      local c = chunker.new()
      local entities = make_entities(5)
      local completed_network_id

      c:initialise_chunking(1, entities, nil, {}, noop)
      c:process_chunk(function() return 1 end)

      c:reset(2,
        noop,
        function(pd, gather, nid) completed_network_id = nid end
      )
      -- Should have completed the old run (network_id = 1)
      assert.are.equal(1, completed_network_id)
      -- Should now be in finalising (re-initialised with nil list)
      assert.are.equal("finalising", c.state)
    end)
  end)
end)
