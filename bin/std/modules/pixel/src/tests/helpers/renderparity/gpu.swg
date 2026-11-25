#global if #command == Swag.CompilerCommand.Test and (#os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux)
#global internal

using Swag, Core

// Draws `scene` with the CPU and the GPU renderer and requires the two images to agree.
//
// `width` and `height` size the offscreen drawable the GPU renders through; the scene owns its
// render target. This is the entry point of a renderer parity test: a divergence found in a real
// scene is reduced to one such scene, which then stays as its regression test.
func assertSceneParity(scene: RenderParityScene, name: string, width, height: s32, options: Testing.ImageGoldenOptions = {}, loc = #callerlocation)
{
    var window = expect Env.createWindow({identifier: name, title: "Pixel renderer parity", width: width, height: height})
    expect window.showOffScreen()
    var ogl: RenderOgl
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(window.nativeRenderHandle(), width, height)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()

    let expected = scene(reference)
    let actual   = scene(gpu)
    #static if #os == Swag.TargetOs.Windows
    {
        Swag.require(not expect ogl.recoverLostDevice(), "OpenGL device reset during renderer parity scene")
    }
    Testing.assertRenderersAgree(&expected, &actual, name, options, loc)
}
