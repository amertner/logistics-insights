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

  -- ─── Multi-chunk processing scenarios ─────────────────────────────
  -- All tests in this block use chunk_size=50 and cost=1 per entity,
  -- so each process_chunk() call consumes exactly 50 items.

  describe("multi-chunk processing (chunk_size=50)", function()
    before_each(function()
      storage.global.chunk_size = 50
      mock.unload("scripts.")
      chunker = require("scripts.chunker")
    end)

    --- Drive a chunker to completion, calling process_chunk in a loop.
    --- Returns { processed_ids, chunk_sizes, num_chunks }.
    local function run_to_completion(entity_list)
      local c = chunker.new()
      local processed_ids = {}
      local chunk_sizes = {}

      c:initialise_chunking(1, entity_list, nil, {},
        function(pd) pd.seen = {} end)

      while c:needs_processing() do
        local before = #processed_ids
        c:process_chunk(function(entity, pd)
          table.insert(processed_ids, entity.id)
          pd.seen[entity.id] = (pd.seen[entity.id] or 0) + 1
          return 1
        end)
        table.insert(chunk_sizes, #processed_ids - before)
      end

      return {
        c = c,
        processed_ids = processed_ids,
        chunk_sizes = chunk_sizes,
        partial_data = c.partial_data,
      }
    end

    -- ─── Boundary counts: 0, chunk*3-1, chunk*3, chunk*3+1 ─────────

    it("handles 0 entities (immediate finalising)", function()
      local c = chunker.new()
      c:initialise_chunking(1, {}, nil, {}, noop)
      assert.are.equal("finalising", c.state)
      assert.are.equal(0, c.processing_count)
      assert.is_false(c:needs_processing())
    end)

    it("processes 149 entities (chunk*3 - 1) across 3 chunks: 50+50+49", function()
      local result = run_to_completion(make_entities(149))
      assert.are.equal(149, #result.processed_ids)
      assert.are.same({50, 50, 49}, result.chunk_sizes)
      assert.is_true(result.c:needs_finalisation())
    end)

    it("processes 150 entities (chunk*3) across 3 chunks: 50+50+50", function()
      local result = run_to_completion(make_entities(150))
      assert.are.equal(150, #result.processed_ids)
      assert.are.same({50, 50, 50}, result.chunk_sizes)
      assert.is_true(result.c:needs_finalisation())
    end)

    it("processes 151 entities (chunk*3 + 1) across 4 chunks: 50+50+50+1", function()
      local result = run_to_completion(make_entities(151))
      assert.are.equal(151, #result.processed_ids)
      assert.are.same({50, 50, 50, 1}, result.chunk_sizes)
      assert.is_true(result.c:needs_finalisation())
    end)

    -- ─── Every entity processed exactly once ────────────────────────

    it("processes each entity exactly once (149 items)", function()
      local result = run_to_completion(make_entities(149))
      for id = 1, 149 do
        assert.are.equal(1, result.partial_data.seen[id],
          "entity " .. id .. " should be processed exactly once")
      end
    end)

    it("processes each entity exactly once (150 items)", function()
      local result = run_to_completion(make_entities(150))
      for id = 1, 150 do
        assert.are.equal(1, result.partial_data.seen[id],
          "entity " .. id .. " should be processed exactly once")
      end
    end)

    it("processes each entity exactly once (151 items)", function()
      local result = run_to_completion(make_entities(151))
      for id = 1, 151 do
        assert.are.equal(1, result.partial_data.seen[id],
          "entity " .. id .. " should be processed exactly once")
      end
    end)

    -- ─── Entities processed in order ────────────────────────────────

    it("processes entities in sequential order", function()
      local result = run_to_completion(make_entities(150))
      for i = 1, 150 do
        assert.are.equal(i, result.processed_ids[i],
          "entity at position " .. i .. " should be id " .. i)
      end
    end)

    -- ─── Progress tracking across chunks ────────────────────────────

    it("reports accurate progress after each chunk", function()
      local c = chunker.new()
      c:initialise_chunking(1, make_entities(150), nil, {}, noop)

      local prog = c:get_progress()
      assert.are.equal(1, prog.current)
      assert.are.equal(150, prog.total)

      c:process_chunk(function() return 1 end)
      prog = c:get_progress()
      assert.are.equal(51, prog.current) -- processed 50, now at index 51
      assert.are.equal(150, prog.total)

      c:process_chunk(function() return 1 end)
      prog = c:get_progress()
      assert.are.equal(101, prog.current)

      c:process_chunk(function() return 1 end)
      prog = c:get_progress()
      assert.are.equal(151, prog.current) -- past the end
      assert.is_true(c:needs_finalisation())
    end)

    -- ─── Change chunk size midway ───────────────────────────────────

    it("respects chunk size change mid-processing", function()
      local c = chunker.new()
      local processed_ids = {}
      local chunk_sizes = {}

      c:initialise_chunking(1, make_entities(200), nil, {}, noop)

      -- First chunk at size 50
      local before = #processed_ids
      c:process_chunk(function(entity)
        table.insert(processed_ids, entity.id)
        return 1
      end)
      table.insert(chunk_sizes, #processed_ids - before)
      assert.are.equal(50, chunk_sizes[1])

      -- Change global chunk size to 30 and force update
      storage.global.chunk_size = 30
      c:set_chunk_size()
      assert.are.equal(30, c.CHUNK_SIZE)

      -- Second chunk should now process 30
      before = #processed_ids
      c:process_chunk(function(entity)
        table.insert(processed_ids, entity.id)
        return 1
      end)
      table.insert(chunk_sizes, #processed_ids - before)
      assert.are.equal(30, chunk_sizes[2])

      -- Change to 80
      storage.global.chunk_size = 80
      c:set_chunk_size()

      -- Third chunk processes 80
      before = #processed_ids
      c:process_chunk(function(entity)
        table.insert(processed_ids, entity.id)
        return 1
      end)
      table.insert(chunk_sizes, #processed_ids - before)
      assert.are.equal(80, chunk_sizes[3])

      -- Remaining: 200 - 50 - 30 - 80 = 40
      before = #processed_ids
      c:process_chunk(function(entity)
        table.insert(processed_ids, entity.id)
        return 1
      end)
      table.insert(chunk_sizes, #processed_ids - before)
      assert.are.equal(40, chunk_sizes[4])

      assert.are.equal(200, #processed_ids)
      assert.is_true(c:needs_finalisation())

      -- Verify all processed exactly once in order
      for i = 1, 200 do
        assert.are.equal(i, processed_ids[i])
      end
    end)

    -- ─── Abort (reset) partway through ──────────────────────────────

    it("abort via reset completes current run and re-initialises", function()
      local c = chunker.new()
      local processed_ids = {}
      local completion_called = false
      local completed_network_id

      c:initialise_chunking(1, make_entities(200), nil, {},
        function(pd) pd.count = 0 end)

      -- Process 2 chunks (100 entities out of 200)
      for _ = 1, 2 do
        c:process_chunk(function(entity, pd)
          table.insert(processed_ids, entity.id)
          pd.count = pd.count + 1
          return 1
        end)
      end
      assert.are.equal(100, #processed_ids)
      assert.are.equal("processing", c.state)

      -- Abort via reset
      c:reset(2,
        function(pd) pd.count = 0 end,
        function(pd, gather, nid)
          completion_called = true
          completed_network_id = nid
        end
      )

      -- Completion callback should have been called for the old network
      assert.is_true(completion_called)
      assert.are.equal(1, completed_network_id)
      -- Chunker should be in finalising (re-initialised with nil)
      assert.are.equal("finalising", c.state)
      -- Only 100 entities were processed before abort
      assert.are.equal(100, #processed_ids)
    end)

    -- ─── Invalid entities mixed in across chunk boundaries ──────────

    it("skips invalid entities across chunk boundaries", function()
      local entities = make_entities(150)
      -- Invalidate entities at chunk boundaries
      entities[50].valid = false  -- last of chunk 1
      entities[51].valid = false  -- first of chunk 2
      entities[100].valid = false -- last of chunk 2

      local result = run_to_completion(entities)
      -- 150 entities iterated, 3 invalid, 147 processed
      assert.are.equal(147, #result.processed_ids)
      -- Verify the invalid ones were not processed
      for _, id in ipairs(result.processed_ids) do
        assert.is_true(id ~= 50 and id ~= 51 and id ~= 100,
          "invalid entity " .. id .. " should not have been processed")
      end
      -- Verify all valid ones were processed exactly once
      for id = 1, 150 do
        if id ~= 50 and id ~= 51 and id ~= 100 then
          assert.are.equal(1, result.partial_data.seen[id],
            "valid entity " .. id .. " should be processed exactly once")
        end
      end
    end)

    -- ─── Deferred fetcher with multi-chunk processing ───────────────

    it("handles fetcher + multi-chunk processing", function()
      local c = chunker.new()
      local processed_ids = {}

      c:initialise_chunking(1, function() return make_entities(120) end, nil, {}, noop)
      assert.are.equal("fetching", c.state)

      -- First call resolves the fetcher
      c:process_chunk(function() return 1 end)
      assert.are.equal("processing", c.state)
      assert.are.equal(120, c.processing_count)

      -- Now process all chunks
      while c:needs_processing() do
        c:process_chunk(function(entity)
          table.insert(processed_ids, entity.id)
          return 1
        end)
      end

      assert.are.equal(120, #processed_ids)
      assert.is_true(c:needs_finalisation())
    end)

    -- ─── Full lifecycle with finalise ───────────────────────────────

    it("full lifecycle: init → multi-chunk → finalise → idle", function()
      local c = chunker.new()
      local total_processed = 0

      c:initialise_chunking(1, make_entities(151), nil, {},
        function(pd) pd.total = 0 end)

      assert.are.equal("processing", c.state)
      assert.are.equal(4, c:num_chunks()) -- ceil(151/50)

      while c:needs_processing() do
        c:process_chunk(function(entity, pd)
          pd.total = pd.total + 1
          return 1
        end)
      end

      assert.are.equal(151, c.partial_data.total)
      assert.is_true(c:needs_finalisation())
      assert.is_false(c:is_done_processing())

      local final_total
      c:finalise_run(function(pd) final_total = pd.total end)
      assert.are.equal(151, final_total)
      assert.are.equal("idle", c.state)
      assert.is_true(c:is_done_processing())
      assert.is_true(c:needs_data())
    end)
  end)

  describe("gather_quality_data setting", function()
    it("sets gather.quality = true when setting is enabled", function()
      storage.global.gather_quality_data = true
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      assert.is_true(c.gather.quality)
    end)

    it("sets gather.quality = false when setting is disabled", function()
      storage.global.gather_quality_data = false
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      assert.is_false(c.gather.quality)
    end)

    it("updates gather.quality on initialise_chunking", function()
      storage.global.gather_quality_data = false
      mock.unload("scripts.")
      chunker = require("scripts.chunker")

      local c = chunker.new()
      assert.is_false(c.gather.quality)

      -- Change the setting and re-initialise
      storage.global.gather_quality_data = true
      c:initialise_chunking(1, nil, nil, {}, function() end)
      assert.is_true(c.gather.quality)
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
