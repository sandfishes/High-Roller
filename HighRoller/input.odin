package HighRoller

import "base:runtime"
import "core:os"
import "vendor:glfw"
import "core:fmt"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import glm "core:math/linalg/glsl"

key_callback :: proc "c" (
	window: glfw.WindowHandle,
	key: i32,
	scancode: i32,
	action: i32,
	mods: i32,
) {
	// Key state must be set as the window pointer
	user_pointer: ^User_Pointer = cast(^User_Pointer)glfw.GetWindowUserPointer(window)
        key_state := user_pointer.key_state
	context = runtime.default_context()
	if action == glfw.PRESS || action == glfw.REPEAT {
		switch key {
		case glfw.KEY_ESCAPE:
			{
				key_state.escape = true
			}
		case glfw.KEY_LEFT:
			{
				key_state.left = true
			}
		case glfw.KEY_RIGHT:
			{
				key_state.right = true
			}
		case glfw.KEY_UP:
			{
				key_state.up = true
			}
		case glfw.KEY_DOWN:
			{
				key_state.down = true
			}
                case glfw.KEY_A: 
                        {
                                key_state.a = true
                        }
                case glfw.KEY_D: 
                        {
                                key_state.d = true
                        }
                case glfw.KEY_W: 
                        {
                                key_state.w = true
                        }
                case glfw.KEY_S: 
                        {
                                key_state.s = true
                        }
                case glfw.KEY_SPACE:
                        {
                                key_state.space = true
                        }
                case glfw.KEY_LEFT_SHIFT:
                        {
                                key_state.shift = true
                        }
                } 
	}
	if action == glfw.RELEASE {
		switch key {
                case glfw.KEY_ESCAPE:
                        {
                                key_state.escape = false
                        }
		case glfw.KEY_LEFT:
			{
				key_state.left = false
			}
		case glfw.KEY_RIGHT:
			{
				key_state.right = false
			}
		case glfw.KEY_UP:
			{
				key_state.up = false
			}
		case glfw.KEY_DOWN:
			{
				key_state.down = false
			}
                case glfw.KEY_A: 
                        {
                                key_state.a = false
                        }
                case glfw.KEY_D: 
                        {
                                key_state.d = false
                        }
                case glfw.KEY_W: 
                        {
                                key_state.w = false
                        }
                case glfw.KEY_S: 
                        {
                                key_state.s = false
                        }
                case glfw.KEY_SPACE:
                        {
                                key_state.space = false
                        }
                case glfw.KEY_LEFT_SHIFT:
                        {
                                key_state.shift = false
                        }
		}
	}
}



cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, x_pos: f64, y_pos: f64)
{
	user_pointer: ^User_Pointer = cast(^User_Pointer)glfw.GetWindowUserPointer(window)
        key_state := user_pointer.key_state
        x_pos := f32(x_pos)
        y_pos := f32(y_pos)
        key_state.x_offset = x_pos - key_state.mouse_pos.x
        key_state.y_offset = y_pos - key_state.mouse_pos.y
        key_state.mouse_pos.x = x_pos
        key_state.mouse_pos.y = y_pos
        key_state.mouse_moved = true
}



mouse_button_callback :: proc "c" (window: glfw.WindowHandle, button: i32, action: i32, mods: i32)
{
	user_pointer: ^User_Pointer = cast(^User_Pointer)glfw.GetWindowUserPointer(window)
        key_state := user_pointer.key_state
	context = runtime.default_context()
	if action == glfw.PRESS || action == glfw.REPEAT {
		switch button {
		case glfw.MOUSE_BUTTON_LEFT: 
                        {
                                key_state.left_mouse_down = true
                        }
                case glfw.MOUSE_BUTTON_RIGHT: 
                        {
                                key_state.right_mouse_down = true
                        }
                } 
	}
	if action == glfw.RELEASE {
		switch button {
		case glfw.MOUSE_BUTTON_LEFT: 
                        {
                                key_state.left_mouse_down = false
                                key_state.can_select = true
                                fmt.println("RELEASE")
                        }
                case glfw.MOUSE_BUTTON_RIGHT: 
                        {
                                key_state.right_mouse_down = false
                        }
		}
	}
}

window_size_callback :: proc "c" (window: glfw.WindowHandle, width: i32, height: i32)
{
                context = runtime.default_context()

        fmt.println(width, height)
	user_pointer: ^User_Pointer = cast(^User_Pointer)glfw.GetWindowUserPointer(window)
        rc := user_pointer.rc
        scene := user_pointer.scene
        rc.width = width
        rc.height = height
        rc.swapchain->setDrawableSize(NS.Size{NS.Float(width), NS.Float(height)})
        glfw.SetWindowSize(rc.glfw_window, width, height)
        scene.camera.perspective_transform = glm.mat4Perspective(glm.radians_f32(90), f32(rc.width)/f32(rc.height), CAMERA_NEAR, 2000)
        rc.swapchain->setFrame(NS.Window_frame(rc.native_window))
        main_screen := NS.Screen_mainScreen()
        frame := main_screen->frame()
        frame.width = NS.Float(width)
        frame.height = NS.Float(height)
        fmt.println(height)
        rc.native_window->setFrame(frame, true)
}