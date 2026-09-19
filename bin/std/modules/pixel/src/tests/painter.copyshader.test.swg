#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Plain texture copies choose the cheap program centrally, then restore vector coverage.
#test
{
    var painter: Painter
    var texture: Texture
    texture.attach(cast(TextureHandle) 7, .BGRA8, 64, 32)
    painter.begin()
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 64, 32}, texture)
    painter.setBlendingMode(.Alpha)
    painter.fillRoundRect({0, 40, 64, 32}, 4, 4, Color.fromArgb(Argb.Red))
    painter.end()

    var program = DefaultShaderId.Default
    var draws   = 0'u32
    for cmd in painter.commandBuffer
    {
        if cmd.id == .SetDefaultShader do
            program = cmd.defaultShader.id
        if cmd.id == .DrawTriangles
        {
            Swag.assert(program == (draws == 0 ? DefaultShaderId.Simple : DefaultShaderId.Default))
            draws += 1
        }
    }

    Swag.assert(draws >= 2)
}

// Rotation, blending, and explicit effect programs are not ordinary copies.
#test
{
    var custom: ShaderBase
    for mode in 6
    {
        var painter: Painter
        var texture: Texture
        texture.attach(cast(TextureHandle) 7, .BGRA8, 64, 32)
        painter.begin()
        painter.setBlendingMode(.Copy)
        switch mode
        {
        case 0: painter.rotateTransform(15.0'deg)
        case 1: painter.setBlendingMode(.Add)
        case 2: painter.setBlurShader(0, 3)
        case 3: painter.setResolveShader(2)
        case 4: painter.setBlendingMode(.Alpha)
        case 5: painter.setShader(&custom)
        }

        painter.drawTexture({0, 0, 64, 32}, texture)
        painter.end()
        for cmd in painter.commandBuffer where cmd.id == .SetDefaultShader do
            Swag.assert(cmd.defaultShader.id != .Simple)
    }
}

// Explicit simple programs survive a copy, but a fresh recording starts from the default.
#test
{
    var painter: Painter
    var texture: Texture
    texture.attach(cast(TextureHandle) 7, .BGRA8, 64, 32)
    painter.begin()
    painter.setDefaultShader(.Simple)
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 64, 32}, texture)
    painter.end()
    var programs = 0'u32
    for cmd in painter.commandBuffer where cmd.id == .SetDefaultShader
    {
        Swag.assert(cmd.defaultShader.id == .Simple)
        programs += 1
    }

    Swag.assert(programs == 1)
    painter.begin()
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 64, 32}, texture)
    painter.end()
    programs = 0
    for cmd in painter.commandBuffer where cmd.id == .SetDefaultShader do
        programs += 1
    Swag.assert(programs == 2)
}

// Brush uniforms belong to a program: a program change must rebind even a solid brush.
#test
{
    var painter: Painter
    painter.begin()
    painter.fillRect({0, 0, 8, 8}, Color.fromArgb(Argb.Red))
    painter.setDefaultShader(.Simple)
    painter.fillRect({8, 0, 8, 8}, Color.fromArgb(Argb.Red))
    painter.end()
    var changed, rebound: bool
    for cmd in painter.commandBuffer
    {
        if cmd.id == .SetDefaultShader do
            changed = true
        if changed and cmd.id == .ResetTexture0 do
            rebound = true
        if changed and cmd.id == .DrawTriangles do
            Swag.assert(rebound)
    }

    Swag.assert(changed and rebound)
}

// Copy must replace the destination even when every source texel is transparent.
#test
{
    const pixels: [16] u8 = [255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0, 255, 0, 0, 0]
    let source = Image.create(2, 2, .RGBA8, pixels)
    var cpu: RenderCpu
    cpu.begin(8, 8)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Blue))
    painter.setBlendingMode(.Copy)
    painter.drawTexture({2, 2, 4, 4}, texture)
    painter.end()
    renderer.draw(&painter)
    let image = cpu.surfaceImage()
    Swag.assert(image.pixelColor(3, 3) == Color.fromArgb(0'u8, 255'u8, 0'u8, 0'u8))
    Swag.assert(image.pixelColor(1, 3) == Color.fromArgb(Argb.Blue))
}
