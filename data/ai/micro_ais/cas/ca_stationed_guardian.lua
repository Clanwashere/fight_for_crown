local AH = wesnoth.require "ai/lua/ai_helper.lua"
local M = wesnoth.map

local function get_guardian(cfg)
    local filter = wml.get_child(cfg, "filter") or { id = cfg.id }
    local guardian = AH.get_units_with_moves {
        side = wesnoth.current.side,
        { "and", filter }
    }[1]
    return guardian
end

local ca_stationed_guardian = {}

function ca_stationed_guardian:evaluation(cfg)
    if get_guardian(cfg) then return cfg.ca_score end
    return 0
end

function ca_stationed_guardian:execution(cfg)
    -- (s_x, s_y): coordinates where guardian is stationed; tries to move here if there is nobody to attack
    -- (g_x, g_y): location that the guardian guards

    local guardian = get_guardian(cfg)

    local enemies = AH.get_attackable_enemies {
        { "filter_location", { x = guardian.x, y = guardian.y, radius = cfg.distance } }
    }

    -- If no enemies are within cfg.distance: keep guardian from doing anything and exit
    if not enemies[1] then
        AH.checked_stopunit_moves(ai, guardian)
        return
    end

    -- Otherwise, guardian will either attack or move toward station
    -- Enemies must be within cfg.distance of guardian, (s_x, s_y) *and* (g_x, g_y)
    -- simultaneously for guardian to attack
    local station_loc = AH.get_named_loc_xy('station', cfg)
    local guard_loc = AH.get_named_loc_xy('guard', cfg) or station_loc
    local min_dist1, target = math.huge, nil
    for _,enemy in ipairs(enemies) do
        local dist_s = M.distance_between(station_loc[1], station_loc[2], enemy.x, enemy.y)
        local dist_g = M.distance_between(guard_loc[1], guard_loc[2], enemy.x, enemy.y)

        -- If valid target found, save the one with the shortest distance from (g_x, g_y)
        if (dist_s <= cfg.distance) and (dist_g <= cfg.distance) and (dist_g < min_dist1) then
            target, min_dist1 = enemy, dist_g
        end
    end

    -- If a valid target was found, guardian attacks this target, or moves toward it
    if target then
        -- Find tiles adjacent to the target
        -- Save the one with the highest defense rating that guardian can reach
        local best_defense, attack_loc = - math.huge, nil
        for xa,ya in wesnoth.current.map:iter_adjacent(target) do
            -- Only consider unoccupied hexes
            local unit_in_way = wesnoth.units.get(xa, ya)
            if (not AH.is_visible_unit(wesnoth.current.side, unit_in_way))
                or (unit_in_way == guardian)
            then
                local defense = guardian:defense_on(wesnoth.current.map[{xa, ya}])
                local nh = AH.next_hop(guardian, xa, ya)
                if nh then
                    if (nh[1] == xa) and (nh[2] == ya) and (defense > best_defense) then
                        best_defense, attack_loc = defense, { xa, ya }
                    end
                end
            end
        end

        -- If a valid hex was found: move there and attack
        if attack_loc then
            AH.robust_move_and_attack(ai, guardian, attack_loc, target)
        else  -- Otherwise move toward that enemy
            local reach = wesnoth.paths.find_reach(guardian)

            -- Go through all hexes the guardian can reach, find closest to target
            -- Cannot use next_hop here since target hex is occupied by enemy
            local min_dist2, nh = math.huge, nil
            for _,hex in ipairs(reach) do
                -- Only consider unoccupied hexes
                local unit_in_way = wesnoth.units.get(hex[1], hex[2])
                if (not AH.is_visible_unit(wesnoth.current.side, unit_in_way))
                    or (unit_in_way == guardian)
                then
                    local dist = M.distance_between(hex[1], hex[2], target.x, target.y)
                    if (dist < min_dist2) then
                        min_dist2, nh = dist, { hex[1], hex[2] }
                    end
                end
            end

            AH.movefull_stopunit(ai, guardian, nh)
        end

    -- If no enemy is within the target zone, move toward station position
    else
        local nh = AH.next_hop(guardian, station_loc[1], station_loc[2])
        if not nh then
            nh = { guardian.x, guardian.y }
        end

        AH.movefull_stopunit(ai, guardian, nh)
    end

    if (not guardian) or (not guardian.valid) then return end

    AH.checked_stopunit_moves(ai, guardian)
    -- If there are attacks left and guardian ended up next to an enemy, we'll leave this to RCA AI
end

return ca_stationed_guardian
