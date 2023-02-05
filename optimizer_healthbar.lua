-- local variables for API functions. any changes to the line below will be lost on re-generation
local client_set_event_callback, client_userid_to_entindex, entity_get_bounding_box, entity_get_esp_data, entity_get_local_player, entity_get_origin, entity_get_player_weapon, entity_get_players, entity_get_prop, entity_is_alive, entity_is_dormant, entity_is_enemy, globals_maxplayers, math_pow, renderer_gradient, renderer_rectangle, renderer_text, ui_get, ui_new_checkbox, ui_new_color_picker, ui_new_combobox, ui_reference, ui_set, ui_set_callback, ui_set_visible, pairs, error = client.set_event_callback, client.userid_to_entindex, entity.get_bounding_box, entity.get_esp_data, entity.get_local_player, entity.get_origin, entity.get_player_weapon, entity.get_players, entity.get_prop, entity.is_alive, entity.is_dormant, entity.is_enemy, globals.maxplayers, math.pow, renderer.gradient, renderer.rectangle, renderer.text, ui.get, ui.new_checkbox, ui.new_color_picker, ui.new_combobox, ui.reference, ui.set, ui.set_callback, ui.set_visible, pairs, error

local vector = require 'vector'
local csgo_weapons = require "gamesense/csgo_weapons" or error('gamesense/csgo_weapons library is required -> https://gamesense.pub/forums/viewtopic.php?id=18807')

local players_data = {}

local l_p = entity_get_local_player()
local l_p_o = entity_get_origin(l_p) and vector(entity_get_origin(l_p)) or vector()
local alive = false

local healthbar_ref = ui_reference('Visuals', 'Player ESP', 'Health bar')

local menu = {
	state = ui_new_checkbox('Visuals', 'Player ESP', 'Custom health bar'),
	color = ui_new_color_picker('Visuals', 'Player ESP', 'Health bar color', 57, 152, 255, 255),
	bar_type = ui_new_combobox('Visuals', 'Player ESP', '\n', {'Solid', 'Gradient', 'Health based'}),
	second_color = ui_new_color_picker('Visuals', 'Player ESP', 'Health bar second color', 11, 70, 255, 255)
}

local s_bar = ui_get(menu.bar_type)
local r1, g1, b1, a1 = ui_get(menu.color)
local r2, g2, b2, a2 = ui_get(menu.second_color)


local function show_items(show)
	for _, item in pairs(menu) do
		if (item ~= menu.state) and (item ~= menu.color) then
			ui_set_visible(item, show)
		end
	end
end

show_items(false)


local render_bar = {
	['Solid'] = function(args)
	local s = (args.data.health < 100) and 1 or 0
	renderer_rectangle((args.x - 4), (args.b_box[4] - (args.h * (args.data.health / 100) - s)), 2, (args.h * (args.data.health / 100)), args.r1, args.g1, args.b1, (args.b_box[5] * a1))
	end,
	['Gradient'] = function(args)
	local s = (args.data.health < 100) and 1 or 0
	renderer_gradient((args.x - 4), (args.b_box[4] - (args.h * (args.data.health / 100) - s)), 2, (args.h * (args.data.health / 100)), args.r1, args.g1, args.b1, (args.b_box[5] * a1), args.r2, args.g2, args.b2, (args.b_box[5] * a2), false)
	end,
	['Health based'] = function()
	ui_set(menu.bar_type, 'Solid')
	ui_set(menu.state, false)
end
}


local function init_player(entidx)
if not players_data[entidx] then
	local o = entity_get_origin(entidx)
	players_data[entidx] = {
		health = 100,
		armor_value = 0,
		origin = (o) and vector(o) or vector(),
		lethal = false
	}
end
end


local function are_enemies(ent1, ent2)
if (not players_data[ent1]) or (not players_data[ent2]) then return false end

local ent1_team = players_data[ent1].team or entity_get_prop(ent1, 'm_iTeamNum')
local ent2_team = players_data[ent2].team or entity_get_prop(ent2, 'm_iTeamNum')

if not ent1_team or not ent2_team then return false end

return (ent1_team ~= ent2_team)
end


local function scale_damage(entidx, current_damage, armor_ratio)
current_damage = current_damage * 1.25

if not (players_data[entidx].armor_value > 0) then return current_damage end

local armor_value = players_data[entidx].armor_value

if armor_value > 0 then
	current_damage = current_damage * (armor_ratio * 0.5)
end

return current_damage
end


local function is_player_lethal(entidx)
if (not entity_is_alive(l_p)) then return false end

local dist = l_p_o:dist(players_data[entidx].origin)

local l_w_i = entity_get_player_weapon(l_p)
local w_definition_idx = entity_get_prop(l_w_i, "m_iItemDefinitionIndex")

local weapon_data = csgo_weapons[w_definition_idx]
local damage = weapon_data.damage

damage = damage * math_pow(weapon_data.range_modifier, dist * 0.002)
damage = scale_damage(entidx, damage, weapon_data.armor_ratio)

return (w_definition_idx == 64) and (players_data[entidx].health <= damage) or ((w_definition_idx ~= 9) and (players_data[entidx].health <= damage) or (players_data[entidx].health <= 90))
end


local function paint()
if not alive then
	l_p = entity_get_local_player()
	l_p_o = vector(entity_get_origin(l_p))

	if (entity_get_prop(l_p, 'm_iTeamNum') < 2) then return end

	for _, entidx in pairs(entity_get_players(false)) do
		if entity_get_esp_data(entidx) then
			if not players_data[entidx] then init_player(entidx) end

			players_data[entidx].team = entity_get_prop(entidx, 'm_iTeamNum')
			players_data[entidx].health = entity_get_esp_data(entidx).health or players_data[entidx].health
		end
	end
end

for entidx, data in pairs(players_data) do
	local b_box = {entity_get_bounding_box(entidx)}
	local should_render_health = false

	if (b_box[5] > 0) then
		local dist = l_p_o:dist(data.origin)

		if not alive then
			local observer_target = entity_get_prop(l_p, 'm_hObserverTarget')
			local observer_mode = entity_get_prop(l_p, 'm_iObserverMode')

			if observer_mode == 5 and observer_target <= 64 then
				if not are_enemies(observer_target, entidx) then return end
			end
		end

		local h = (b_box[4] - b_box[2])
		local w = (b_box[3] - b_box[1])
		local x = (b_box[1] - (w / (dist * 0xFF)))
		local y = (b_box[4] - h)

		local r1, g1, b1 = r1, g1, b1
		local r2, g2, b2 = r2, g2, b2

		if entity_is_dormant(entidx) then
			r1, g1, b1 = 255, 255, 255
			r2, g2, b2 = 255, 255, 255
		end

		renderer_rectangle(x - 5, y - 1, 4, h + 2, 10, 10, 10, (b_box[5] * 200))
		render_bar[s_bar]({b_box = b_box, h = h, w = w, x = x, y = y, r1 = r1, g1 = g1, b1 = b1, r2 = r2, g2 = g2, b2 = b2, data = data})

		should_render_health = alive and (players_data[entidx].lethal) or (data.health <= 92)

		if should_render_health then
			renderer_text(x - 6, b_box[4] - (h * (data.health / 100)) + 2, 255, 255, 255, (b_box[5] * 255), '-cd', 0, data.health)
		end
	end
end
end


local function player_death(e)
local entidx = client_userid_to_entindex(e.userid)

if players_data[entidx] then players_data[entidx] = nil end

if entidx == l_p then alive = false end
end


local function player_hurt(e)
local entidx = client_userid_to_entindex(e.userid)
init_player(entidx)

players_data[entidx].health = e.health
players_data[entidx].armor_value = e.armor
end


local function player_spawned(e)
local entidx = client_userid_to_entindex(e.userid)

init_player(entidx)
end


local function round_start()
players_data = {}

for entidx = 0, globals_maxplayers() do
	local esp_data = entity_get_esp_data(entidx)

	if esp_data then
		init_player(entidx)

		if entity_is_enemy(entidx) ~= nil then
			players_data[entidx].team = entity_get_prop(entidx, 'm_iTeamNum')
		end
	end
end
end


local function player_footstep(e)
local entidx = client_userid_to_entindex(e.userid)

init_player(entidx)
end


local function item_purchase(e)
local entidx = client_userid_to_entindex(e.userid)

init_player(entidx)

local armors = {
	['item_assaultsuit'] = 1,
	['item_heavyassaultsuit'] = 2,
	['item_kevlar'] = 3
}

if (armors[e.weapon]) then
	players_data[entidx].armor_value = 100
end
end


local function run_command()
l_p = entity_get_local_player()
l_p_o = vector(entity_get_origin(l_p))
alive = true

for _, entidx in pairs(entity_get_players(false)) do
	if entidx ~= l_p then
		if not players_data[entidx] then init_player(entidx) end
		players_data[entidx].armor_value = entity_get_prop(entidx, 'm_ArmorValue')
		players_data[entidx].team = entity_get_prop(entidx, 'm_iTeamNum')
	end
end

for entidx in pairs(players_data) do
	if entity_get_origin(entidx) then
		players_data[entidx].origin = vector(entity_get_origin(entidx))
	end
	players_data[entidx].lethal = is_player_lethal(entidx)
	players_data[entidx].health = (entity_get_esp_data(entidx)) and entity_get_esp_data(entidx).health or players_data[entidx].health
end

end


function handle_callbacks(state)
local c = (state) and client_set_event_callback or client.unset_event_callback

c('run_command', run_command)
c('paint', paint)
c('player_death', player_death)
c('player_hurt', player_hurt)
c('player_spawned', player_spawned)
c('round_start', round_start)
c('player_footstep', player_footstep)
c('item_purchase', item_purchase)
end

ui_set_callback(menu.state, function()
local state = ui_get(menu.state)

handle_callbacks(state)

if not state then
show_items(false)
else
ui_set_visible(menu.bar_type, state)
ui_set_visible(menu.color, state)

local gradient = (ui_get(menu.bar_type) == 'Gradient')

ui_set_visible(menu.second_color, gradient)
end

ui_set(healthbar_ref, not(state))
ui_set_visible(healthbar_ref, not(state))
end)


ui_set_callback(menu.bar_type, function()
local gradient = (ui_get(menu.bar_type) == 'Gradient')

ui_set_visible(menu.second_color, gradient)

s_bar = ui_get(menu.bar_type)
end)


ui_set_callback(menu.color, function()
r1, g1, b1, a1 = ui_get(menu.color)
end)


ui_set_callback(menu.second_color, function()
r2, g2, b2, a2 = ui_get(menu.second_color)
end)


client_set_event_callback('shutdown', function()
players_data = nil

ui_set_visible(healthbar_ref, true)
ui_set(healthbar_ref, true)

handle_callbacks(false)
end)