#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// A scaled embedded bitmap blends neighboring samples even when the surrounding painter uses
// pixel interpolation. Otherwise a manuscript's raster illustrations acquire jagged edges.
#test
{
    var source = Image.create(2, 1, .RGBA8)
    let samples: [8] u8 = [255, 0, 0, 255, 0, 0, 255, 255]
    Memory.copy(source.pixels.buffer, &samples, 8)
    let bytes   = expect source.encodeToBytes("embedded.png")
    let svg     = Format.toString("<svg width='32' height='16'><image width='32' height='16' href='data:image/png;base64,%'/></svg>", Base64.encode(bytes.toSlice()))
    let drawing = expect Svg.Drawing.parse(svg.toString())
    let image   = drawing.rasterize(32, 16, 1)
    let middle  = image.pixelColor(16, 8)
    Swag.assert(middle.r > 64 and middle.r < 192)
    Swag.assert(middle.b > 64 and middle.b < 192)
    Swag.assert(middle.a == 255)
}

// A mirroring transform flips the picture in place. Reduced to its axis scales, it would land the
// bitmap upright beside its slot, where the enclosing clip hides it; the rectangle beside it is
// the same law for a shape.
#test
{
    var source = Image.create(2, 1, .RGBA8)
    let samples: [8] u8 = [255, 0, 0, 255, 0, 0, 255, 255]
    Memory.copy(source.pixels.buffer, &samples, 8)
    let bytes   = expect source.encodeToBytes("embedded.png")
    let svg     = Format.toString("<svg width='64' height='16'><image width='32' height='16' transform='translate(32,0) scale(-1,1)' href='data:image/png;base64,%'/><rect x='32' width='8' height='16' fill='lime' transform='translate(96,0) scale(-1,1)'/></svg>", Base64.encode(bytes.toSlice()))
    let drawing = expect Svg.Drawing.parse(svg.toString())
    let image   = drawing.rasterize(64, 16, 1)

    let left  = image.pixelColor(2, 8)
    let right = image.pixelColor(29, 8)
    Swag.assert(left.b > 200 and left.r < 56)
    Swag.assert(right.r > 200 and right.b < 56)

    Swag.assert(image.pixelColor(60, 8).g > 200)
    Swag.assert(image.pixelColor(36, 8).a == 0)
}

// Relative raster references are decoded through Pixel only inside the configured resource root.
#test
{
    let imagePath = getTestDataPath("basi2c08.png")
    let dataRoot  = Path.directoryName(imagePath.toString())!
    var options: Svg.ParseOptions
    options.externalResourceRoot = dataRoot
    const Source = "<svg width='40' height='40'><image x='4' y='4' width='32' height='32' href='basi2c08.png'/></svg>"

    let drawing = expect Svg.Drawing.parse(Source, options)
    let image   = drawing.rasterize(40, 40, 1)
    Swag.assert(image.pixelColor(2, 2).a == 0)
    Swag.assert(image.pixelColor(20, 20).a > 0)
    Swag.assert(image.pixelColor(35, 35).a > 0)
}

// Data images need no filesystem authority, while a relative reference without a root is rejected.
#test
{
    const Embedded = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAQAAAABbAUdZAAAABGdBTUEAAYagMeiWXwAAAFtJREFUeJwtzLEJAzAMBdHr0gSySiALejRvkBU8gsGNCmFFB1Hx4IovqurSpIRszqklUwbnUzRXEuIRsiG/SyY9G0JzJSVei9qynm9qyjBpLp0pYW7pbzBl8L8fEIdJL9AvFMkAAAAASUVORK5CYII="
    const Source   = #stringof("<svg width='4' height='4'><image width='4' height='4' href='data:image/png;base64,", Embedded, "'/></svg>")
    let drawing = expect Svg.Drawing.parse(Source)
    let image   = drawing.rasterize(4, 4, 1)
    Swag.assert(image.pixelColor(2, 2).a > 0)

    const External = "<svg width='4' height='4'><image width='4' height='4' href='basi2c08.png'/></svg>"
    discard catch Svg.Drawing.parse(External) as err
    Swag.assert(err != null)

    var options: Svg.ParseOptions
    options.externalResourceRoot = Path.directoryName(getTestDataPath("basi2c08.png").toString())!
    const Escape = "<svg width='4' height='4'><image width='4' height='4' href='../basi2c08.png'/></svg>"
    discard catch Svg.Drawing.parse(Escape, options) as escapeErr
    Swag.assert(escapeErr != null)
}
