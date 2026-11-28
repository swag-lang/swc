#global if #command == Swag.CompilerCommand.Test and (#os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux)
#global private

using Core

// Execute the same recorded scenes on both backends, including the first GPU frame.
func assertPortableParity(scene: RenderParityScene, name: string)
{
    var window = expect Env.createWindow({identifier: name, title: "Pixel renderer parity", width: 360, height: 168})
    expect window.showOffScreen()
    var ogl: RenderOgl
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(window.nativeRenderHandle(), 360, 168)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()
    gpu.begin(context)

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()

    // These scenes have opaque backgrounds; overlap-safe strokes use target alpha as scratch.
    // Dedicated alpha/readback tests cover stored coverage independently of visible color.
    let expected = scene(reference).convertedTo(.RGB8)
    let actual   = scene(gpu).convertedTo(.RGB8)
    gpu.end()

    // CPU byte blending truncates while GPU framebuffer blending rounds. Multiple passes
    // may accumulate those channel steps; no pixels may exceed this four-level bound.
    Testing.assertImagesNear(&expected, &actual, name, {maxChannelDelta: 4})
}

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    // Avoid exact pixel-center ties: OpenGL leaves their ownership rule to the implementation.
    // Fractional positioning still exercises narrow strokes, every cap/join, curves and dashes.
    func scene(renderer: IRenderer)->Image => renderStrokeParityScene(renderer, 0.25)
    assertPortableParity(&scene, "render.parity.stroke.cpu-ogl")
}

#[Swag.TestTag("integration.renderer.opengl")]
#test { assertPortableParity(&renderTextParityScene, "render.parity.text.cpu-ogl") }

#[Swag.TestTag("integration.renderer.opengl")]
#test { assertPortableParity(&renderLayerParityScene, "render.parity.layer.cpu-ogl") }
