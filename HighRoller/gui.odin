package HighRoller

import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
import "../include/imgui/imgui_impl_metal"
import "../include/imgui/imgui_impl_glfw"
import im "../include/imgui"
import "vendor:glfw"


// This needs to be rendered on a different window. If it isn't then everything will break.
// This can be changed, but the begining render stage will need to be modified.
init_gui :: proc(rc: ^Render_Context
) -> ^im.IO
{
        im.CHECKVERSION()
        im.CreateContext()
        io := im.GetIO()
        io.ConfigFlags += {.NavEnableKeyboard}
        when !DISABLE_DOCKING {
		io.ConfigFlags += {.DockingEnable}
		io.ConfigFlags += {.ViewportsEnable}
		style := im.GetStyle()
		style.WindowRounding = 0
		style.Colors[im.Col.WindowBg].w = 1
	}
	im.StyleColorsDark()
	imgui_impl_metal.Init(rc.device)
	imgui_impl_glfw.InitForOther(rc.glfw_window, true)
	return io
}



begin_gui_draw :: proc(rc: ^Render_Context
)
{
 //        depth_desc := MTL.DepthStencilDescriptor.alloc()->init()
 //        defer depth_desc->release()
	// depth_desc->setDepthCompareFunction(.Less)
	// depth_desc->setDepthWriteEnabled(true)
	// depth_stencil_state := MTL.Device_newDepthStencilState(rc.device, depth_desc)

        rps := MTL.RenderPassDescriptor.alloc()->init()
	rps->colorAttachments()->object(0)->setClearColor(MTL.ClearColor{ 0, 0, 0, 1 })
	rps->colorAttachments()->object(0)->setTexture(rc.draw_stage.drawable->texture())
	rps->colorAttachments()->object(0)->setLoadAction(.Load)
	rps->colorAttachments()->object(0)->setStoreAction(.Store)
	rc.draw_stage.encoder = rc.draw_stage.command_buffer->renderCommandEncoderWithDescriptor(rps)
	// rc.draw_stage.encoder ->setDepthStencilState(depth_stencil_state)
	imgui_impl_metal.NewFrame(rps)
	imgui_impl_glfw.NewFrame()
	im.NewFrame()
}

end_gui_draw :: proc(rc: ^Render_Context)
{

        im.End()
	im.Render()
	imgui_impl_metal.RenderDrawData(im.GetDrawData(), rc.draw_stage.command_buffer, rc.draw_stage.encoder)
	when !DISABLE_DOCKING {
		backup_current_window := glfw.GetCurrentContext()
		im.UpdatePlatformWindows()
		im.RenderPlatformWindowsDefault()
		glfw.MakeContextCurrent(backup_current_window)
	}
        rc.draw_stage.encoder->endEncoding()
        //rc.draw_stage.command_buffer->presentDrawable(rc.draw_stage.drawable)
        //rc.draw_stage.command_buffer->commit()
}
