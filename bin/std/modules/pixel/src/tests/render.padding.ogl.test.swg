#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows

using Core

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window  = expect Env.createWindow({identifier: "pixel-padding-test", title: "Pixel padding test", width: 64, height: 64})
    var ogl:      RenderOgl
    let renderer: IRenderer = &ogl
    var context = expect renderer.createContext(window.nativeRenderHandle(), 64, 64)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()
    assertFractionalSourceScene(renderFractionalSourceScene(renderer))
    for factor in [2, 3] do
        assertResolvePaddingScene(renderResolvePaddingScene(renderer, factor))
}
