require "__factorissimo-2-notnotmelon__.script.electricity"

-- Some legacy saves could end up with recursive (inside another factory) factories
-- missing their power monitor / inside power pole wiring. To fix this deterministically,
-- we rebuild power connections in "outermost factory first" order.

local STORAGE_FACTORIES = storage.factories or {}

local GRID_SIZE = 16 * 32 -- must match remote_api + placement math

local function cell_from_pos(pos)
    return math.floor(0.5 + (pos or 0) / GRID_SIZE)
end

-- Returns the parent/surrounding factory if `factory` is placed inside it.
-- We detect parent by matching the grid cell of the child's outside position
-- to the parent factory's inside cell, on the same "outside surface" (the child building surface).
local function find_parent_factory(factory)
    if not (factory and factory.outside_surface and factory.outside_surface.valid) then
        return nil
    end

    local child_surface = factory.outside_surface
    local cx = cell_from_pos(factory.outside_x)
    local cy = cell_from_pos(factory.outside_y)

    for _, candidate in pairs(STORAGE_FACTORIES) do
        if
            candidate
            and candidate ~= factory
            and candidate.outside_surface
            and candidate.outside_surface.valid
            and candidate.outside_surface.index == child_surface.index
        then
            local px = cell_from_pos(candidate.inside_x)
            local py = cell_from_pos(candidate.inside_y)
            if px == cx and py == cy then
                return candidate
            end
        end
    end

    return nil
end

local depth_memo = {}
local visiting = {}

local function compute_depth(factory)
    if not factory or not factory.id then return 0 end
    if depth_memo[factory.id] ~= nil then return depth_memo[factory.id] end
    if visiting[factory.id] then
        -- Cycle safeguard (shouldn't happen, but prevents infinite recursion).
        return 0
    end

    visiting[factory.id] = true
    local parent = find_parent_factory(factory)
    local depth = 0
    if parent then
        depth = compute_depth(parent) + 1
    end
    visiting[factory.id] = nil

    depth_memo[factory.id] = depth
    return depth
end

local factories = {}
for _, factory in pairs(STORAGE_FACTORIES) do
    if factory and factory.built then
        factories[#factories + 1] = factory
    end
end

for _, factory in pairs(factories) do
    compute_depth(factory)
end

table.sort(factories, function(a, b)
    local da = depth_memo[a.id] or 0
    local db = depth_memo[b.id] or 0
    if da == db then
        return (a.id or 0) < (b.id or 0)
    end
    return da < db
end)

local function connect_inside_poles(child_factory, parent_factory)
    if not (child_factory and parent_factory) then return false end
    local child_pole = factorissimo.get_or_create_inside_power_pole(child_factory)
    local parent_pole = factorissimo.get_or_create_inside_power_pole(parent_factory)
    if not (child_pole and child_pole.valid and parent_pole and parent_pole.valid) then
        return false
    end

    local child_connector = child_pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    local parent_connector = parent_pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    if not (child_connector and parent_connector) then return false end

    child_connector.connect_to(parent_connector, false, defines.wire_origin.script)
    return true
end

-- Phase 1: explicitly wire recursive children to their parent factory monitor.
for _, factory in pairs(factories) do
    local parent = find_parent_factory(factory)
    if parent then
        connect_inside_poles(factory, parent)
    end
end

-- Phase 2: run regular reconnect logic in a few deterministic passes.
-- Migrations run only once, so we do multiple passes immediately to emulate
-- the old "delayed reconnect" behavior from runtime.
for _, factory in pairs(factories) do
    factorissimo.get_or_create_inside_power_pole(factory)
end

for _ = 1, 6 do
    for _, factory in pairs(factories) do
        factorissimo.update_power_connection(factory)
    end
end
