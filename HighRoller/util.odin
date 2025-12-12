package HighRoller

import "core:fmt"
import os "core:os/os2"
import NS "core:sys/darwin/Foundation"
import MTL "vendor:darwin/Metal"
import CA "vendor:darwin/QuartzCore"
// This file contains wrappers to add error handling to the game.

set_render_pipeline_state :: proc(name: string, rc: ^Render_Context)
{
        if !(name in rc.shaders) {
                fmt.eprintln("%s not found in shader map.", name)
                os.exit(RENDER_CONTEXT_STATE_ERROR)
        }
        rc.draw_stage.encoder->setRenderPipelineState(rc.shaders[name].pipeline_state)
}



// Exit Codes
RENDER_CONTEXT_STATE_ERROR :: 1
FILE_LOADING_ERROR :: 2
