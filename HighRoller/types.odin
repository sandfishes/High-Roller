package HighRoller

import "core:path/filepath"
import ai "../include/assimp"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:image/jpeg"
import "core:image/png"
import glm "core:math/linalg/glsl"
import "core:math/rand"
import os "core:os/os2"
import "core:strings"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "vendor:glfw"
import hm "handle_map"

Render_Context :: struct {
	device:        ^MTL.Device,
	native_window: ^NS.Window,
	glfw_window:   glfw.WindowHandle,
	swapchain:     ^CA.MetalLayer,
	command_queue: ^MTL.CommandQueue,
	depth_texture: ^MTL.Texture,
	shaders:       map[string]Shader,
	textures:      map[string]^Texture,
	draw_stage:    Draw_Stage,
	shadow_map:    Shadow_Map,
        width:         i32,
        height:        i32,
}

Draw_Stage :: struct {
	pass:           ^MTL.RenderPassDescriptor,
	drawable:       ^CA.MetalDrawable,
	command_buffer: ^MTL.CommandBuffer,
	encoder:        ^MTL.RenderCommandEncoder,
}

Shader :: struct {
	pipeline_state: ^MTL.RenderPipelineState,
	library:        ^MTL.Library,
}

Texture :: struct {
	value: ^MTL.Texture,
	type:  Texture_Type,
}

Mesh_Buffers :: struct {
	pos:          ^MTL.Buffer,
	norm:         ^MTL.Buffer,
	uv:           ^MTL.Buffer,
	bone_ids:     ^MTL.Buffer,
	bone_weights: ^MTL.Buffer,
	index:        ^MTL.Buffer,
}

Key_State :: struct {
	keys:                  map[rune]bool,
	left, right, up, down: bool,
        a, d, w, s:            bool,
        space:                 bool,
        shift:                 bool,
        escape:                bool,
	left_mouse_down:       bool,
	left_mouse_drag:       bool,
        right_mouse_down:      bool,
	right_mouse_drag:      bool,
	mouse_pos:             [2]f32,
	delete:                bool,
        x_offset:              f32,
        y_offset:              f32,
        mouse_moved:           bool,
        can_select:            bool,
}

Camera :: struct #align (16) {
        world_transform:       matrix[4, 4]f32,
	view_transform:        matrix[4, 4]f32,
	perspective_transform: matrix[4, 4]f32,
	normal_transform:      matrix[4, 4]f32,
	pos:                   [3]f32,
        yaw:                   f32,
        pitch:                 f32,
        front:                 [3]f32,
        right:                 [3]f32,
        up:                    [3]f32,
        free:                  bool,
}

MAX_BONE_INFLUENCE :: 4
Mesh_Vertex :: struct {
	pos:          [3]f32,
	norm:         [3]f32,
	uv:           [2]f32,
	bone_ids:     [MAX_BONE_INFLUENCE]i32,
	bone_weights: [MAX_BONE_INFLUENCE]f32,
}

Mesh :: struct {
	textures:  [dynamic]^Texture,
	buffers:   ^Mesh_Buffers,
	vertices:  #soa[dynamic]Mesh_Vertex, // TODO is this required?
	indices:   [dynamic]i32, // TODO is this required?
}

// A model is just an object that has animation
Model :: struct {
	meshes:                 [dynamic]Mesh, // TODO doesn't need to be dynamic
	directory:              string,
	bone_infos:             map[string]Bone_Info,
	bone_counter:           i32,
	bone_buffer:            ^MTL.Buffer,
	transform_buffer:       ^MTL.Buffer,
        color_id:               Color_ID
}

Bone_Info :: struct {
	id:     i32,
	offset: matrix[4, 4]f32,
}

Bone :: struct {
	key_pos:         []Key_Position,
	key_rot:         []Key_Rotation,
	key_scale:       []Key_Scale,
	local_transform: matrix[4, 4]f32,
	name:            string,
	id:              int,
}

Key_Position :: struct {
	value: [3]f32,
	time:  f64,
}

Key_Rotation :: struct {
	value: quaternion128,
	time:  f64,
}

Key_Scale :: struct {
	value: [3]f32,
	time:  f64,
}

AI_Node_Data :: struct {
	transformation: matrix[4, 4]f32,
	name:           string,
	child_count:    int,
	children:       []^AI_Node_Data,
}

Animation :: struct {
	duration:   f64,
	tick_rate:  f64,
	bones:      [dynamic]^Bone,
	root_node:  ^AI_Node_Data,
	bone_infos: map[string]Bone_Info,
}

Animator :: struct {
	bone_matrices:     []matrix[4, 4]f32,
	current_animation: ^Animation,
	time:              f64,
	dt:                f64,
	blending:          bool,
	blend_duration:    f64,
	blend_matrices:    []matrix[4, 4]f32,
}

Light :: struct {
	pos:      [3]f32,
	col:      [3]f32,
	vertices: [][3]f32,
}

Scene :: struct {
        camera:   ^Camera,
	player:   hm.Handle,
	enemies:  [dynamic]hm.Handle,
	objects:  [dynamic]hm.Handle,
	lights:   #soa[dynamic]Light,
	light_buffer: ^MTL.Buffer,
        selected: hm.Handle,
        color_id_texture: ^MTL.Texture,
        color_id_map: map[Color_ID]hm.Handle,
	entities: hm.Handle_Map(Entity, hm.Handle, 1000),
        edit: bool,
	hud: HUD,
}

Collider :: union {
        Capsule_Collider,
        Sphere_Collider,
        Box_Collider,
        Plane_Collider,
}

Capsule_Collider :: struct {}
Sphere_Collider :: struct {
        radius: f32,
        mesh: Mesh
}
Plane_Collider :: struct {
        normal: [3]f32,
        binormal: [3]f32,
        x: f32, // Along binormal
        z: f32, // not along binormal
}

Box_Collider :: struct {}


Shader_Options :: struct {
        pixel_format:                           MTL.PixelFormat,
        blending_enabled:                       bool,
        rgb_blend_operation:                    MTL.BlendOperation,
        alpha_blend_operation:                  MTL.BlendOperation,
        source_rgb_blend_operation:             MTL.BlendFactor,
        source_alpha_blend_operation:           MTL.BlendFactor,
        destination_rgb_blend_operation:        MTL.BlendFactor,
        destination_alpha_blend_operation:      MTL.BlendFactor,
        depth_attachment_pixel_format:          MTL.PixelFormat
}

Render_Pass_Options :: struct {
        color_attachment_load_action:           MTL.LoadAction,
        color_attachment_store_action:          MTL.StoreAction,
        depth_attachment_clear_depth:           f64,
        depth_attachment_load_action:           MTL.LoadAction,
        depth_attachment_store_action:          MTL.StoreAction,
        depth_descriptor_compare_function:      MTL.CompareFunction,
        depth_descriptor_write_enabled:         bool,
        cull_mode:                              MTL.CullMode,
        front_facing_winding:                   MTL.Winding,
        with_color_attachment:                  bool,
        depth_bias:                             f32,
        slope_scaled_depth_bias:                f32,
        depth_bias_clamp:                       f32,
}

Shadow_Map :: struct {
        texture: ^MTL.Texture,
        transform: ^MTL.Buffer,
}

Vertex_Transforms :: struct {
        transform: matrix[4,4]f32,
        normal_transform: matrix[4,4]f32,
}

GUI :: struct {
        roll: f32,
        pitch: f32,
        yaw: f32,
        scale: ^f64,
        texture_files: [dynamic]cstring,
        selected_texture: cstring,
}

Color_ID :: [3]u8

Render_Arguments :: struct {
        selected: i32,
}

World_Pos ::struct {
        pos: [3]f32,
        rot: quaternion128,
        scale: f32,
}

User_Pointer :: struct {
        key_state: ^Key_State,
        rc:        ^Render_Context,
        scene:     ^Scene,
}

HUD :: struct {
	active: bool,
	health: int,
	crosshair_scale: f32,
}

Entity_State :: union {
	Player_State,
}

Entity_Type :: enum {
	Enemy,
	Player,
	Object,
	Collider,
}

Entity :: struct {
	type: 	    Entity_Type,
	model:      ^Model,
	animator:   ^Animator,
	animations: []Animation,
	state:      Entity_State,
	transform:  matrix[4, 4]f32,
        using world_pos: World_Pos,
	speed:      f32,
        collider:   Collider,
        velocity:   [3]f32,
        on_ground:  bool,
	handle:     hm.Handle,
}

