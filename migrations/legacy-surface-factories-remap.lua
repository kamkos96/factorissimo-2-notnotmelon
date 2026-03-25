-- Factorissimo 1.x keyed storage.surface_factories by interior surface name; 3.x uses surface.index.
-- After a 1.1 -> 2.0 save upgrade, string keys must be remapped or find_surrounding_factory breaks.
-- factories_by_entity is also rebuilt so unit_number keys match buildings after map migration.

local old = storage.surface_factories or {}
local merged = {}

for key, factories in pairs(old) do
    if type(key) == "string" then
        local surf = game.get_surface(key)
        if surf then merged[surf.index] = factories end
    end
end

for key, factories in pairs(old) do
    if type(key) == "number" then
        merged[key] = factories
    end
end

storage.surface_factories = merged

local by_entity = {}
for _, factory in pairs(storage.factories or {}) do
    local b = factory.building
    if b and b.valid then
        by_entity[b.unit_number] = factory
    end
end
storage.factories_by_entity = by_entity
