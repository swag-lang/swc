#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Ogl

// The one-matte optimization must preserve the GPU overload's coverage as well.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "svg-white-mask-test", title: "SVG white mask test", width: 96, height: 80})
    expect window.showOffScreen()
    var ogl:      RenderOgl
    let renderer: IRenderer = &ogl
    var context = expect renderer.createContext(window.nativeRenderHandle(), 96, 80)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()
    assertSvgWhiteMaskRaster(renderer, 256)

    // A rejected tile allocation must return an invalid image, never dereference empty pixels.
    let drawing = expect Svg.Drawing.parse("<svg width='8' height='8'><rect width='8' height='8' fill='white'/></svg>")
    glScissor(0, 0, 1, -1)
    let failed = drawing.rasterize(renderer, 8, 8)
    Swag.require(not failed.isValid() and glGetError() == GL_NO_ERROR)
    let recovered = drawing.rasterize(renderer, 8, 8)
    Swag.require(recovered.isValid())
}
