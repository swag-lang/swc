#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows

using Swag, Core

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window         = expect Env.createWindow({identifier: "pixel-backdrop-test", title: "Pixel backdrop test", width: 144, height: 96})
    var ogl: RenderOgl
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(window.nativeRenderHandle(), 144, 96)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()
    for algorithm in [BackdropBlur.Gaussian, .DualKawase]
    {
        for scale in [1.0'f32, 1.5]
        {
            let expected = renderBackdropScene(reference, algorithm, scale)
            let actual   = renderBackdropScene(gpu, algorithm, scale)
            Testing.assertImagesNear(&expected, &actual, "backdrop.ogl", {maxChannelDelta: 4})
        }
    }
}
