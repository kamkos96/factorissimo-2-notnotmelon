-- Fixes legacy (1.x/2.0) saved factories where connection direction metadata and/or
-- hidden helper entities (factory-linked-*, pumps, heat/circuit dummies, indicators)
-- can become inconsistent after prototype changes.

local function starts_with(str, prefix)
    return str and prefix and str:sub(1, #prefix) == prefix
end

local defines_direction = defines.direction
local opposite = {
    [defines_direction.north] = defines_direction.south,
    [defines_direction.east] = defines_direction.west,
    [defines_direction.south] = defines_direction.north,
    [defines_direction.west] = defines_direction.east,
}

local DX = {
    [defines_direction.north] = 0,
    [defines_direction.east] = 1,
    [defines_direction.south] = 0,
    [defines_direction.west] = -1,
}

local DY = {
    [defines_direction.north] = -1,
    [defines_direction.east] = 0,
    [defines_direction.south] = 1,
    [defines_direction.west] = 0,
}

local function guess_direction_out_from_position(outside_x, outside_y)
    -- Connection tiles are always on the factory outer perimeter, so one axis dominates.
    -- This heuristic fixes cases where legacy saves stored swapped direction metadata.
    if math.abs(outside_x) > math.abs(outside_y) then
        return (outside_x < 0) and defines_direction.west or defines_direction.east
    end
    return (outside_y < 0) and defines_direction.north or defines_direction.south
end

local function destroy_factory_helpers(surface, area)
    if not (surface and surface.valid and area) then return end

    for _, e in pairs(surface.find_entities_filtered {area = area}) do
        local name = e.name
        if starts_with(name, "factory-linked-") then
            e.destroy()
        elseif starts_with(name, "factory-inside-pump-") then
            e.destroy()
        elseif starts_with(name, "factory-outside-pump-") then
            e.destroy()
        elseif name == "factory-heat-dummy-connector" then
            e.destroy()
        elseif name == "factory-circuit-connector-invisible" then
            e.destroy()
        elseif starts_with(name, "factory-connection-indicator-") then
            e.destroy()
        end
    end
end

if not storage.factories then return end

for _, factory in pairs(storage.factories) do
    if factory and factory.layout and factory.layout.connections and factory.built then
        -- Normalize layout connection metadata so connection slot math is consistent
        for _, cpos in pairs(factory.layout.connections) do
            local direction_out = guess_direction_out_from_position(cpos.outside_x, cpos.outside_y)
            cpos.direction_out = direction_out
            cpos.direction_in = opposite[direction_out]
            cpos.indicator_dx = DX[direction_out]
            cpos.indicator_dy = DY[direction_out]
        end

        -- Destroy helper entities so they won't block re-creation / keep old wiring
        if factory.inside_surface and factory.inside_surface.valid and factory.outside_surface and factory.outside_surface.valid then
            local inside_x, inside_y = factory.inside_x or 0, factory.inside_y or 0
            local outside_x, outside_y = factory.outside_x or 0, factory.outside_y or 0

            local inside_size = factory.layout.inside_size or 0
            local outside_size = factory.layout.outside_size or 0

            local D_in = math.floor((inside_size + 8) / 2) + 6
            local D_out = math.floor((outside_size / 2)) + 6

            destroy_factory_helpers(factory.inside_surface, {
                {inside_x - D_in, inside_y - D_in},
                {inside_x + D_in, inside_y + D_in},
            })

            destroy_factory_helpers(factory.outside_surface, {
                {outside_x - D_out, outside_y - D_out},
                {outside_x + D_out, outside_y + D_out},
            })
        end

        -- Clear runtime connection state so on_init can rebuild from current belt/pipe entities.
        -- Important: keep factory.connection_settings so per-connection mode (e.g. fluid input/output)
        -- survives migration. Wiping it would reset transfer directions.
        factory.connections = {}
        factory.connection_indicators = {}
        if type(factory.connection_settings) ~= "table" then
            factory.connection_settings = {}
        end
    end
end
