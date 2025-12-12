package HighRoller

import glm "core:math/linalg/glsl"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "core:math/rand"



player_move :: proc(player: ^Player, direction: [3]f32, dist: f32)
{
	player.position.x += direction.x * dist
	player.position.z += direction.z * dist
	player.position.y += direction.y * dist
}



update_player :: proc(player: ^Player, key_state: ^Key_State, dt: f64, rc: ^Render_Context)
{
	direction: [3]f32
	if key_state.a {
		direction.x -= 1
	}
	if key_state.d {
		direction.x += 1
	}
	if key_state.w {
		direction.z -= 1
	}
	if key_state.s {
		direction.z += 1
	}
	direction = glm.normalize(direction)
	if glm.dot(direction, direction) > 0 {
		look_direction := direction
		look_direction.z = -look_direction.z
		player.rotation = glm.mat4LookAt({0, 0, 0}, look_direction, {0, 1, 0})
		player_move(player, direction, player.speed * f32(dt))
		switch_animation(player.animator, &player.animations[Player_State.WALKING])
	} else {
		switch_animation(player.animator, &player.animations[Player_State.STANDING])
	}
	player.transform =
		glm.mat4Translate(player.position) *
		glm.mat4Scale({player.scale, player.scale, player.scale}) *
		player.rotation
	update_animation(player.animator, dt)
	// Update model transform up front
        transform_data := player.model.transform_buffer->contentsAsType(matrix[4,4]f32)
        transform_data^ = player.transform
        player.model.transform_buffer->didModifyRange(NS.Range_Make(0, size_of(matrix[4,4]f32)))
        if player.model.bone_buffer != nil {
                player.model.bone_buffer->release()
        }
        player.model.bone_buffer = build_bone_buffer(rc.device, player.animator.bone_matrices)
}



init_player :: proc(
	model_path: string,
	animation_path: string,
	rc: ^Render_Context,
) -> Player
{
	model := load_model(model_path, rc)
	anims := load_animation(animation_path, model)
	animator := create_animator(&anims[0])
	player := Player {
		model      = model,
		animator   = animator,
		animations = anims,
		transform  = 1,
	}
	player.position = {0, -1, 0}
	player.scale = 0.01
	player.speed = 10
	player.rotation = 1
        player.model.color_id = Color_ID{u8(rand.int_max(255)), u8(rand.int_max(255)), u8(rand.int_max(255))}
	return player
}
