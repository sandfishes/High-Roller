package HighRoller

import "base:sanitizer"
import "vendor:directx/d3d12"
import "vendor:glfw"
import glm "core:math/linalg/glsl"
import "base:runtime"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "core:fmt"
foreign import "objc_runtime"
import im "../include/imgui"
import "../include/imgui/imgui_impl_metal"
import "../include/imgui/imgui_impl_glfw"
import "core:strings"
import os "core:os/os2"
import "core:math"
import "core:math/rand"
import "core:slice"
// MAIN GAME LOOP //////////////////////////////////////
run_game :: proc() {
	rc := init_render_context(800, 600, "High Roller")
        // TODO setup gui function
	io := init_gui(rc)
        gui := GUI{}
        gui.texture_files = make([dynamic]cstring)
        dirs, _ := os.read_all_directory_by_path("../resources/textures/DEBUG", runtime.default_allocator())
        for dir in dirs {
                files, err := os.read_directory_by_path(dir.fullpath, 0, runtime.default_allocator())
                if err == nil {
                        for file in files {
                                append(&gui.texture_files, strings.clone_to_cstring(file.fullpath))
                        }
                }
        }
        gui.selected_texture = gui.texture_files[0]
	defer im.DestroyContext()

	load_shaders(rc)
	camera := init_camera(800, 600)
	key_state := init_key_state(rc)
	player := init_player("../resources/models/voxel/Voxel character.fbx", "../resources/models/voxel/Voxel character.fbx", rc)
	scene := init_scene(&camera, &player, rc)


	t: f64 = 0
	for !glfw.WindowShouldClose(rc.glfw_window) {
		t2 := glfw.GetTime()
		dt := t2 - t
		t = t2
		// fmt.println(dt)
		glfw.PollEvents()

		auto_pool := NS.AutoreleasePool_alloc()->init()
		update_scene(scene, key_state, dt, rc)
	        pre_process(scene, rc)

		begin_render_pass(rc)
		render_scene(scene, rc, options = default_render_pass_options)
		update_gui(rc, io, scene, &gui)
		end_render_pass(rc, true)

		post_process(scene, rc)
		auto_pool->release()
	}
}
///////////////////////////////////////////////////////

init_camera :: proc(width, height: f32
) -> Camera
{
	camera := Camera{}
	camera.pos = {-1, 15, 1}
	camera.view_transform = glm.mat4LookAt(camera.pos, {0,0,0}, {0,1,0})
        camera.perspective_transform = glm.mat4Perspective(glm.radians_f32(60), 800/600, 0.03, 2000)
	return camera
}



init_key_state :: proc(rc: ^Render_Context
) -> ^Key_State
{
	key_state := new(Key_State)
        glfw.SetWindowUserPointer(rc.glfw_window, rawptr(key_state))
        glfw.SetKeyCallback(rc.glfw_window, key_callback)
        glfw.SetCursorPosCallback(rc.glfw_window, cursor_pos_callback)
        glfw.SetMouseButtonCallback(rc.glfw_window, mouse_button_callback)
	return key_state
}



init_scene :: proc(camera: ^Camera, player: ^Player, rc: ^Render_Context
) -> ^Scene
{
        scene := new(Scene)
        // TODO figure out the hidden specifics of assigning these arrays
        scene.objects = make([dynamic]^Object)
        scene.lights = make(#soa[dynamic]Light, 1)
        scene.color_id_map = make(map[Color_ID]Selectable)

        scene.player = player
        scene.color_id_map[player.model.color_id] = player
        scene.camera = camera

        // create the ground
        rc.textures["ground_d"] = new(Texture)
        rc.textures["ground_d"].value = load_texture(rc.device, "../resources/textures/DEBUG/Purple/texture_02.png")
        rc.textures["ground_d"].type = .DIFFUSE
        ground_textures: [1]^Texture = {rc.textures["ground_d"]}
        plane := load_plane(ground_textures[:], {0,-1,0}, 0, 10, rc)
        append(&scene.objects, plane)
        scene.color_id_map[plane.color_id] = plane
        scene_clear_lights(scene, rc)
        vert := CUBE_VERTICES
        scene_add_light(scene, Light{
                pos={0.1, 70, -0.1},
                col={1, 1, 1},
                vertices=vert[:]
        }, rc)
        // This needs to be done every time a light is added.
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)

        desc := MTL.TextureDescriptor.alloc()->init()
        // Make this match the dimensions of the screen. Can lower resolution but must have same aspect ratio
	tex_desc := MTL.TextureDescriptor.texture2DDescriptorWithPixelFormat(
		pixelFormat = .RGBA8Unorm,
		width = NS.UInteger(800),
		height = NS.UInteger(600),
		mipmapped = false,
	)
	defer tex_desc->release()
	tex_desc->setUsage({.RenderTarget})
	tex_desc->setStorageMode(.Managed)
        scene.color_id_texture = rc.device->newTextureWithDescriptor(tex_desc)

        return scene
}



load_shaders :: proc(rc: ^Render_Context)
{
        rc.shaders[MESH_SHADER] = build_shader(rc.device, "../shaders/mesh.metal")
        rc.shaders[MESH_SHADOW_SHADER] = build_shader(rc.device, "../shaders/mesh_shadow.metal", shadow_shader_options)
        rc.shaders[MESH_COLOR_ID_SHADER] = build_shader(rc.device, "../shaders/mesh_color_id.metal")

        rc.shaders[MODEL_SHADER] = build_shader(rc.device, "../shaders/model.metal")
        rc.shaders[MODEL_SHADOW_SHADER] = build_shader(rc.device, "../shaders/model_shadow.metal", shadow_shader_options)
        rc.shaders[MODEL_COLOR_ID_SHADER] = build_shader(rc.device, "../shaders/model_color_id.metal")
}



update_gui :: proc(rc: ^Render_Context, io: ^im.IO, scene: ^Scene, gui: ^GUI)
{
        begin_gui_draw(rc)
        //im.ShowDemoWindow()
	if im.Begin("Editor") {
	        if im.Button("Add Light") {
                        vert := CUBE_VERTICES
                        scene_add_light(scene, Light{pos={-1, 20, 1},
                                col={1, 1, 1},
                                vertices=vert[:]}, rc)
		}
                if im.Button("Remove Light") {
                        scene_clear_lights(scene, rc)
                }
                if im.Button("Add Plane") {
                        scene_add_plane(scene, rc, "DEBUG/Orange/texture_02.png")
                }

                if im.BeginCombo("Texture", gui.selected_texture) {
                        for texture in gui.texture_files {
                                is_selected := gui.selected_texture == texture
                                if im.Selectable(texture, is_selected) {
                                        gui.selected_texture = texture
                                        scene_update_texture(scene, texture, rc)
                                }
                        }
                        im.EndCombo()
                }

                im.Text("Object rotation")
                if im.SliderAngle("roll", &gui.roll) {
                        scene_update_rotation(scene, gui)
                }
                if im.SliderAngle("pitch", &gui.pitch) {
                        scene_update_rotation(scene, gui)
                }
                if im.SliderAngle("yaw", &gui.yaw){
                        scene_update_rotation(scene, gui)
                }
	}
        end_gui_draw(rc)
}

update_scene :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64, rc: ^Render_Context)
{
        update_player(scene.player, key_state, dt, rc)
        scene_read_input(scene, key_state, dt)
        update_camera(scene, key_state, dt)
}



update_camera :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64)
{
        MOUSE_SENSITIVITY :: 0.5
        // TODO optimise
        if key_state.right_mouse_down {
                scene.camera.yaw += key_state.x_offset * MOUSE_SENSITIVITY
                scene.camera.pitch -= key_state.y_offset * MOUSE_SENSITIVITY
                key_state.x_offset = 0
                key_state.y_offset = 0
                scene.camera.pitch = clamp(scene.camera.pitch, -89.9, 89.9)
                scene.camera.front = glm.normalize([3]f32{
                        math.cos(math.to_radians(scene.camera.yaw)) * math.cos(math.to_radians(scene.camera.pitch)),
                        math.sin(math.to_radians(scene.camera.pitch)),
                        math.sin(math.to_radians(scene.camera.yaw)) * math.cos(math.to_radians(scene.camera.pitch))
                })
                scene.camera.right = glm.normalize(glm.cross(scene.camera.front, [3]f32{0, 1, 0}))
                scene.camera.up = glm.normalize(glm.cross(scene.camera.right, scene.camera.front))
                scene.camera.view_transform = glm.mat4LookAt(scene.camera.pos, scene.camera.pos + scene.camera.front, {0, 1, 0})
        }
        CAMERA_SPEED :: 10
        if key_state.d {
                scene.camera.pos = scene.camera.pos + scene.camera.right * CAMERA_SPEED * f32(dt)
        }
        if key_state.a {
                scene.camera.pos = scene.camera.pos - scene.camera.right * CAMERA_SPEED * f32(dt)
        }
        if key_state.w {
                scene.camera.pos = scene.camera.pos + scene.camera.front * CAMERA_SPEED * f32(dt)
        }
        if key_state.s {
                scene.camera.pos = scene.camera.pos - scene.camera.front * CAMERA_SPEED * f32(dt)
        }
        // scene.camera.view_transform = glm.mat4LookAt(scene.camera.pos, scene.player.position, {0,1,0})
}



pre_process :: proc(scene: ^Scene, rc: ^Render_Context)
{
        // Generate shadow map
        begin_render_pass(rc, depth_texture = rc.shadow_map.texture, options = shadow_render_pass_options)
        new_encoder(rc, shadow_render_pass_options)
        set_render_pipeline_state(MODEL_SHADOW_SHADER, rc)
        write_model_to_shadow_map(scene.player.model, rc, scene.player.model.transform_buffer, rc.shadow_map)
        set_render_pipeline_state(MESH_SHADOW_SHADER, rc)
        for object in scene.objects {
                write_object_to_shadow_map(object, rc, rc.shadow_map)
        }
        rc.draw_stage.encoder->endEncoding()
        end_render_pass(rc, present=false)
        
        // I don't know why this needs it's own auto-release pool. But it does...
        auto_pool := NS.AutoreleasePool_alloc()->init()
        /// Generate colour id texture
        camera_buffer := rc.device->newBuffer(size_of(Camera), {.StorageModeManaged})
	defer camera_buffer->release()
        camera_data := camera_buffer->contentsAsType(Camera)
        camera_data.view_transform = scene.camera.view_transform
        camera_data.perspective_transform = scene.camera.perspective_transform
        camera_data.pos = scene.camera.pos

        begin_render_pass(rc, nil, color_texture = scene.color_id_texture, options = default_render_pass_options)
        new_encoder(rc, default_render_pass_options)
        set_render_pipeline_state(MODEL_COLOR_ID_SHADER, rc)
        write_model_to_color_id(scene.player.model, scene.player.model.transform_buffer, camera_buffer, rc)
        set_render_pipeline_state(MESH_COLOR_ID_SHADER, rc)
        for object in scene.objects {
                write_object_to_color_id(object, camera_buffer, rc)
        }
        rc.draw_stage.encoder->endEncoding()
        end_render_pass(rc, present=false)
        auto_pool->release()
}



render_scene :: proc(scene: ^Scene, rc: ^Render_Context, options: Render_Pass_Options)
{
        new_encoder(rc, default_render_pass_options)
        //Build the camera buffer
        camera_buffer := rc.device->newBuffer(size_of(Camera), {.StorageModeManaged})
	defer camera_buffer->release()
        camera_data := camera_buffer->contentsAsType(Camera)
        camera_data.view_transform = scene.camera.view_transform
        camera_data.perspective_transform = scene.camera.perspective_transform
        camera_data.pos = scene.camera.pos

        // Render Player
        set_render_pipeline_state(MODEL_SHADER, rc)
	// TODO fix this so it's not in the camera buffer
	camera_data.world_transform = scene.player.transform
	camera_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(scene.player.transform))
        camera_buffer->didModifyRange(NS.Range_Make(0, size_of(Camera)))

	rc.draw_stage.encoder->setVertexBuffer(buffer=camera_buffer, offset=0, index=6)
	rc.draw_stage.encoder->setFragmentBuffer(buffer=camera_buffer, offset=0, index=0)
	rc.draw_stage.encoder->setFragmentBuffer(buffer=scene.light_buffer, offset=0, index=1)

        // Is the player selected?
        options_buffer := rc.device->newBufferWithLength(size_of(Render_Arguments), {.StorageModeManaged})
        defer options_buffer->release()
        options := options_buffer->contentsAsType(Render_Arguments)
        options.selected = scene.selected == scene.player ? 1 : 0
        options_buffer->didModifyRange(NS.Range_Make(0, size_of(Render_Arguments)))
        rc.draw_stage.encoder->setFragmentBuffer(buffer=options_buffer, offset=0, index=8)
        render_model(camera_buffer, scene.light_buffer, scene.player.model, rc)

        set_render_pipeline_state(MESH_SHADER, rc)
        // Set up the shadow map
        rc.draw_stage.encoder->setFragmentTexture(rc.shadow_map.texture, 2)
        rc.draw_stage.encoder->setFragmentBuffer(buffer=rc.shadow_map.transform, offset=0, index=3)
        for object in scene.objects {
                // is this object selected? TODO find a way to do this without creating a new buffer each object
                options_buffer := rc.device->newBufferWithLength(size_of(Render_Arguments), {.StorageModeManaged})
                defer options_buffer->release()
                options := options_buffer->contentsAsType(Render_Arguments)
                options.selected = scene.selected == object ? 1 : 0
                options_buffer->didModifyRange(NS.Range_Make(0, size_of(Render_Arguments)))
                rc.draw_stage.encoder->setFragmentBuffer(buffer=options_buffer, offset=0, index=8)

                transforms := rc.device->newBuffer(size_of(Vertex_Transforms), {.StorageModeManaged})
        	defer transforms->release()
                transform_data := transforms->contentsAsType(Vertex_Transforms)
                transform_data.transform = object.transform
                transform_data.normal_transform = glm.transpose(glm.inverse_matrix4x4(object.transform))
                rc.draw_stage.encoder->setVertexBuffer(buffer=transforms, offset=0, index=7)
                render_mesh(camera_buffer, scene.light_buffer, object.mesh, rc.draw_stage.encoder)
        }
        rc.draw_stage.encoder->endEncoding()
}



post_process :: proc(scene: ^Scene, rc: ^Render_Context)
{

}



scene_add_light :: proc(scene: ^Scene, light: Light, rc: ^Render_Context)
{
        append(&scene.lights, light)
        scene.light_buffer->release()
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)
        if len(scene.lights) == 1 {
                if (rc.shadow_map.texture != nil) {
                        rc.shadow_map.texture->release()
                }
                rc.shadow_map = init_shadow_map(rc, scene.lights[0].pos)
        }
}



scene_clear_lights :: proc(scene: ^Scene, rc: ^Render_Context)
{
        clear(&scene.lights)
        scene.light_buffer->release()
        scene.light_buffer = build_light_buffers(scene.lights[:], rc)
        clear_shadow_map(rc)
}


scene_add_plane :: proc(scene: ^Scene, rc: ^Render_Context, texture: string)
{
        // TODO loading and storing of both diffuse and specular textures
        if !(texture in rc.textures) {
                texture_path := strings.concatenate({"../resources/textures/", texture})
                defer delete(texture_path)
                rc.textures[texture] = new(Texture)
                rc.textures[texture].value = load_texture(rc.device, texture_path)
                rc.textures[texture].type = .DIFFUSE
        }

        plane_textures: [1]^Texture = {rc.textures[texture]}
        rotation: quaternion128 = quaternion(real=0, imag=0, kmag=1, jmag=0)
        plane := load_plane(plane_textures[:], {0,0,0}, rotation, 10, rc)
        append(&scene.objects, plane)
        scene.color_id_map[plane.color_id] = scene.objects[len(scene.objects)]
        scene.selected = plane
}



scene_read_input :: proc(scene: ^Scene, key_state: ^Key_State, dt: f64)
{
        direction: [3]f32
	if key_state.left {
		direction.x -= 1
	}
	if key_state.right {
		direction.x += 1
	}
	if key_state.up {
		direction.z -= 1
	}
	if key_state.down {
		direction.z += 1
	}
	direction = glm.normalize(direction)
	if glm.dot(direction, direction) > 0 {
                switch thing in scene.selected {
                case ^Object: {
                        pos := thing.pos + direction * f32(dt) * 7
                        rot := thing.rot
                        scale := thing.scale
                        thing.pos = pos
                        thing.transform = glm.mat4Translate(pos) * glm.mat4FromQuat(rot) * glm.mat4Scale(scale)
                }
                case ^Player: {
                        pos := thing.position + direction * f32(dt) * 7
                        rot := thing.rotation
                        scale := thing.scale
                        thing.position = pos
                        thing.transform = glm.mat4Translate(pos) * rot * glm.mat4Scale(scale)
                }
                }
        }
        if key_state.left_mouse_down {
                scene.selected = find_object_under_mouse(scene, key_state)
        }
}

find_object_under_mouse :: proc(scene: ^Scene, key_state: ^Key_State
) -> Selectable
{
        color_bytes: [3]byte = {} // 3 f32 values should be 12 bytes
        region_origin := MTL.Origin{NS.Integer(key_state.mouse_pos.x), NS.Integer(key_state.mouse_pos.y), 0}
        //region_origin := MTL.Origin{0, 0, 0}
        region_size := MTL.Size{1,1,1}
        region := MTL.Region{region_origin, region_size}
        scene.color_id_texture->getBytes(rawptr(&color_bytes), scene.color_id_texture->width()*4, region, 0)
        
        // find the color value at that position in the texture
        // Match ColorID to an object via the map (this may or may not work)
        color := slice.reinterpret([]u8, color_bytes[:])
        color_id := Color_ID{color[0], color[1], color[2]}
        if color_id in scene.color_id_map {
                return scene.color_id_map[color_id]
        }
        return nil
}


scene_update_transform :: proc(scene: ^Scene)
{
        switch thing in scene.selected {
        case ^Object: {
                thing.transform =
                        glm.mat4Translate(thing.pos) *
                        glm.mat4FromQuat(thing.rot) *
                        glm.mat4Scale(thing.scale)
        }
        case ^Player: {
                thing.transform =
                        glm.mat4Translate(thing.position) *
                        thing.rotation *
                        glm.mat4Scale(thing.scale)
        }
        }
}



scene_update_rotation :: proc(scene: ^Scene, gui: ^GUI)
{
        fmt.println("rotating", scene.selected)
        switch thing in scene.selected {
        case ^Object: {
                thing.rot = glm.quatAxisAngle({0, 0, 1}, gui.roll) *
                                glm.quatAxisAngle({0, 1, 0}, gui.pitch) *
                                glm.quatAxisAngle({1, 0, 0}, gui.yaw)

                thing.transform =
                glm.mat4Translate(thing.pos) *
                glm.mat4FromQuat(thing.rot) *
                glm.mat4Scale(thing.scale)
        }
        case ^Player: {
                unimplemented("Add handling for rotatin models")
        }
        }
        
}



// TODO error handling
scene_update_texture :: proc(scene: ^Scene, texture_path: cstring, rc: ^Render_Context)
{
        switch thing in scene.selected {
        case ^Object: {
                if string(texture_path) in rc.textures {
                        clear(&thing.mesh.textures)
                        append(&thing.mesh.textures, rc.textures[string(texture_path)])
                } else {
                        texture := new(Texture)
                        texture.value = load_texture(rc.device, string(texture_path))
                        texture .type = .DIFFUSE
                        rc.textures[string(texture_path)] = texture
                        append(&thing.mesh.textures, texture)
                }
        }
        case ^Player: {
                unimplemented("Implement texture loading for models")
        }
        }

}
