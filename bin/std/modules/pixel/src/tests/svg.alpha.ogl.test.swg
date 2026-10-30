#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core

// The one-matte optimization must preserve the GPU overload's coverage as well.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window  = expect Env.createWindow({identifier: "svg-white-mask-test", title: "SVG white mask test", width: 96, height: 80})
    var ogl:      RenderOgl
    let renderer: IRenderer = &ogl
    var context = expect renderer.createContext(window.nativeRenderHandle(), 96, 80)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()
    assertSvgWhiteMaskRaster(renderer, 256)
}
