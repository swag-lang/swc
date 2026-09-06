#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// Warm the embedded cache first, then open the same resource folder after two different edits.
// The live first theme keeps its art while the next theme reads the replacement.
#test
{
    var original: Testing.HeadlessHost
    original.setup(80, 60)
    defer original.shutdown()
    let originalWidth = original.theme.res.imgWidgets.width
    let originalAtlas = original.theme.res.icons.atlas

    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_theme_%", Guid64.random()).toString())
    let folder = Path.combine(root.toString(), "theme")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    expect Directory.create(folder)
    let widgetsPath = Path.combine(folder.toString(), "widgets.svg")
    let iconsPath   = Path.combine(folder.toString(), "icons.svg")

    const Red = #raw """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24"><rect width="24" height="24" fill="#ff0000"/></svg>"""
    const Blue = #raw """<svg xmlns="http://www.w3.org/2000/svg" width="48" height="24"><rect width="48" height="24" fill="#0000ff"/></svg>"""
    discard expect File.writeAllBytes(widgetsPath, cast(const [..] u8) Red)
    discard expect File.writeAllBytes(iconsPath, cast(const [..] u8) Red)
    var first: Testing.HeadlessHost
    first.app.resources.addFolder(root.toString())
    first.setup(80, 60)
    defer first.shutdown()
    Swag.assert(first.theme.res.imgWidgets.width == 24)
    let firstIcon = first.theme.res.icons.icon(0, 24, 1)
    Swag.assert(firstIcon.imageList!.frameCount == 1)
    let firstPixels = first.theme.res.icons.atlas!.image(&first.renderer, 24)
    Swag.assert(firstPixels.pixelColor(12, 12).argb == 0xFFFF0000)

    discard expect File.writeAllBytes(widgetsPath, cast(const [..] u8) Blue)
    discard expect File.writeAllBytes(iconsPath, cast(const [..] u8) Blue)
    var second: Testing.HeadlessHost
    second.app.resources.addFolder(root.toString())
    second.setup(80, 60)
    defer second.shutdown()
    Swag.assert(second.theme.res.imgWidgets.width == 48)
    Swag.assert(second.theme.res.icons.icon(0, 24, 1).imageList!.frameCount == 2)
    let secondPixels = second.theme.res.icons.atlas!.image(&second.renderer, 24)
    Swag.assert(secondPixels.pixelColor(12, 12).argb == 0xFF0000FF)
    first.theme.ensureAtlasScale(&first.renderer, 2)
    Swag.assert(first.theme.res.imgWidgets.width == 48)
    Swag.assert(firstPixels.pixelColor(12, 12).argb == 0xFFFF0000)
    Swag.assert(original.theme.res.imgWidgets.width == originalWidth)
    Swag.assert(original.theme.res.icons.atlas == originalAtlas)

    // Empty and malformed files both fall back, even after an override was cached elsewhere.
    discard expect File.writeAllBytes(widgetsPath, cast(const [..] u8) "")
    discard expect File.writeAllBytes(iconsPath, cast(const [..] u8) "<svg")
    var fallback: Testing.HeadlessHost
    fallback.app.resources.addFolder(root.toString())
    fallback.setup(80, 60)
    defer fallback.shutdown()
    Swag.assert(fallback.theme.res.imgWidgets.width == originalWidth)
    Swag.assert(fallback.theme.res.icons.atlas!.drawing.width == originalAtlas!.drawing.width)
}

// A logical font name cannot alias different disk payloads in the process typeface cache.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_theme_font_%", Guid64.random()).toString())
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let folder = Path.combine(root.toString(), "theme")
    expect Directory.create(folder)
    let path = Path.combine(folder.toString(), "inter-regular.ttf")
    const Regular = #include("../theme/inter-regular.ttf")
    const Bold    = #include("../theme/inter-bold.ttf")
    discard expect File.writeAllBytes(path, Regular)
    var first: Testing.HeadlessHost
    first.app.resources.addFolder(root.toString())
    first.setup(80, 60)
    defer first.shutdown()
    let regular = first.theme.res.defaultTypeFaceR
    discard expect File.writeAllBytes(path, Bold)
    var second: Testing.HeadlessHost
    second.app.resources.addFolder(root.toString())
    second.setup(80, 60)
    defer second.shutdown()
    let bold = second.theme.res.defaultTypeFaceR
    Swag.assert(regular != bold)
    discard expect File.writeAllBytes(path, Regular)
    var third: Testing.HeadlessHost
    third.app.resources.addFolder(root.toString())
    third.setup(80, 60)
    defer third.shutdown()
    Swag.assert(third.theme.res.defaultTypeFaceR == regular)
}
