package input

import ecs "../../src"

is_down :: ecs.is_down
is_pressed :: ecs.is_pressed
is_released :: ecs.is_released
mouse_position :: ecs.mouse_position
mouse_delta :: ecs.mouse_delta
mouse_down :: ecs.mouse_down
mouse_pressed :: ecs.mouse_pressed
mouse_released :: ecs.mouse_released
mouse_scroll :: ecs.mouse_scroll
any_key_down :: ecs.any_key_down

bind :: ecs.bind
unbind :: ecs.unbind
clear_bindings :: ecs.clear_bindings
action_down :: ecs.action_down
action_pressed :: ecs.action_pressed
action_released :: ecs.action_released
consume_buffered :: ecs.consume_buffered
consume_any_buffered :: ecs.consume_any_buffered
consume_key_buffered :: ecs.consume_key_buffered
clear_buffer :: ecs.clear_buffer

InputPlugin :: ecs.InputPlugin
