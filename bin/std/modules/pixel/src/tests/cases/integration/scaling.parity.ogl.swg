#global if #command == Swag.CompilerCommand.Test and (#os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux)
#global private

using Swag, Core

// Odd on both axes: a pixel centre then never maps exactly onto a texel boundary, whatever the
// size the picture is drawn at. OpenGL leaves that tie to the implementation, so a scene that
// contains one compares two arbitrary choices instead of two samplers.
const ScaledPictureWidth  = 47
const ScaledPictureHeight = 31
const ScaledTargetWidth   = 160
const ScaledTargetHeight  = 112

// The scales a viewer really draws a picture at: far and slightly below its own size, slightly
// and far above it, never a whole ratio. A whole ratio hides a sampler that rounds its
// footprint, because every destination pixel then lands on the same place of a texel.
const PictureScales: [5] f32 = [0.37, 0.75, 1.3, 2.7, 3.2]

// Returns the level of a picture made to expose a sampler: a one-pixel checker, a ramp, hard
// blocks and thin rules, so a wrong filter footprint or a shifted texel centre changes whole
// shapes rather than a rounding step.
func scaledPictureLevel(x, y: s32)->u8
{
    if x < 12 do
        return (x + y) & 1 ? 235'u8 : 20'u8
    if x < 24 do
        return cast(u8, 20 + y * 7)
    if x < 36 do
        return (x / 4 + y / 4) & 1 ? 200'u8 : 40'u8
    return y % 5 == 0 or x % 6 == 0 ? 245'u8 : 30'u8
}

func makeScaledPicture()->Image
{
    var result = Image.create(ScaledPictureWidth, ScaledPictureHeight, .BGRA8)
    for y in result.height
    {
        for x in result.width
        {
            let level = scaledPictureLevel(x, y)
            let pixel = result.pixels.storage() + cast(u64, ((result.height - y - 1) * result.rowStride + x * 4))
            pixel[0] = level
            pixel[1] = cast(u8, 255 - level)
            pixel[2] = cast(u8, (x * 5))
            pixel[3] = 255
        }
    }

    return result
}

// Draws one texture at `scale` of its size, the way an image view lays a picture out.
func drawScaledTexture(renderer: IRenderer, texture: Texture, scale: f32, mode: InterpolationMode)->Image
{
    var target = renderer.createRenderTarget(ScaledTargetWidth, ScaledTargetHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 18'u8, 22'u8, 30'u8))
    painter.setInterpolationMode(mode)
    painter.drawTexture({3, 2, ScaledPictureWidth * scale, ScaledPictureHeight * scale}, texture)
    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, ScaledTargetWidth, ScaledTargetHeight)
}

func renderScaledPicture(renderer: IRenderer, scale: f32, mode: InterpolationMode)->Image
{
    var texture = renderer.addImage(makeScaledPicture())
    defer renderer.removeTexture(&texture)
    return drawScaledTexture(renderer, texture, scale, mode)
}

// The same picture handed over as 4:2:0 planes, which is what every video frame is.
func renderScaledFrame(renderer: IRenderer, scale: f32, mode: InterpolationMode)->Image
{
    const Width        = cast(u64, ScaledPictureWidth)
    const Height       = cast(u64, ScaledPictureHeight)
    const ChromaWidth  = (Width + 1) / 2
    const ChromaHeight = (Height + 1) / 2

    var storage: Array'u8
    storage.resize(Width * Height + ChromaWidth * ChromaHeight * 2)
    let luma    = storage.storage()
    let chromaB = luma + Width * Height
    let chromaR = chromaB + ChromaWidth * ChromaHeight
    for y in Height
    {
        for x in Width do
            luma[y * Width + x] = scaledPictureLevel(cast(s32, x), cast(s32, y))
    }

    for y in ChromaHeight
    {
        for x in ChromaWidth
        {
            chromaB[y * ChromaWidth + x] = cast(u8, 64 + x * 5)
            chromaR[y * ChromaWidth + x] = cast(u8, 200 - y * 6)
        }
    }

    let picture = YuvPlanarView{
        luma: luma,
        chromaB: chromaB,
        chromaR: chromaR,
        lumaStride: Width,
        chromaStride: ChromaWidth,
        width: ScaledPictureWidth,
        height: ScaledPictureHeight,
        matrix: .Bt709}
    var texture = renderer.addImage(&picture)
    defer renderer.removeTexture(&texture)
    return drawScaledTexture(renderer, texture, scale, mode)
}

alias ScaledScene = func||(IRenderer, f32, InterpolationMode)->Image

// Draws `scene` with both renderers at every scale and sampling mode.
func assertScalingParity(scene: ScaledScene, name: string)
{
    var window = expect Env.createWindow({identifier: name, title: "Pixel scaling parity", width: ScaledTargetWidth, height: ScaledTargetHeight})
    expect window.showOffScreen()
    var ogl: RenderOgl
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(window.nativeRenderHandle(), ScaledTargetWidth, ScaledTargetHeight)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()

    for mode in [InterpolationMode.Linear, .Pixel]
    {
        for scale in PictureScales
        {
            let expected = scene(reference, scale, mode)
            let actual   = scene(gpu, scale, mode)
            let label    = Format.toString("%.%.%", name, mode == .Linear ? "linear" : "pixel", cast(s32, (scale * 100)))
            Testing.assertRenderersAgree(&expected, &actual, label.toString())
        }
    }
}

// A picture scaled by a ratio that is not whole keeps the same filter footprint on both renderers.
#[Swag.TestTag("integration.renderer.opengl")]
#test { assertScalingParity(&renderScaledPicture, "scaling.parity.picture") }

// A video frame is sampled plane by plane, and scales like the picture it carries.
#[Swag.TestTag("integration.renderer.opengl")]
#test { assertScalingParity(&renderScaledFrame, "scaling.parity.frame") }

const PhotoWidth  = 301
const PhotoHeight = 201

// A picture with detail at every frequency, the way a photograph has: a smooth ramp carrying
// fine grain. Reduced several times over, each destination pixel reads texels far apart, so a
// sampler that places its footprint differently shows over the whole surface.
func makePhoto()->Image
{
    var result = Image.create(PhotoWidth, PhotoHeight, .BGRA8)
    for y in result.height
    {
        for x in result.width
        {
            // Changes from one texel to the next on both axes, with no period a reduction hits.
            let grain = (x * 73 + y * 151 + (x * y) % 97) % 127 - 64
            let pixel = result.pixels.storage() + cast(u64, ((result.height - y - 1) * result.rowStride + x * 4))
            pixel[0] = cast(u8, Math.clamp(60 + x / 3 + grain, 0, 255))
            pixel[1] = cast(u8, Math.clamp(120 + y / 4 - grain, 0, 255))
            pixel[2] = cast(u8, Math.clamp(200 - x / 4 + grain / 2, 0, 255))
            pixel[3] = 255
        }
    }

    return result
}

func renderReducedPhoto(renderer: IRenderer, scale: f32)->Image
{
    var texture = renderer.addImage(makePhoto())
    defer renderer.removeTexture(&texture)

    var target = renderer.createRenderTarget(ScaledTargetWidth, ScaledTargetHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 18'u8, 22'u8, 30'u8))
    painter.setInterpolationMode(.Linear)
    painter.drawTexture({3, 2, PhotoWidth * scale, PhotoHeight * scale}, texture)
    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, ScaledTargetWidth, ScaledTargetHeight)
}

// A photograph reduced several times over is filtered from the same texels on both renderers.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    for scale in [0.47'f32, 0.31, 0.19]
    {
        let scene: RenderParityScene = func|scale|(renderer: IRenderer)->Image => renderReducedPhoto(renderer, scale)
        let label = Format.toString("scaling.parity.photo.%", cast(s32, (scale * 100)))
        assertSceneParity(scene, label.toString(), ScaledTargetWidth, ScaledTargetHeight)
    }
}
