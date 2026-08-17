#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let textFile   = Gui.Testing.tempFilePath("filescope-index-", ".unknown")
    let binaryFile = Gui.Testing.tempFilePath("filescope-index-", ".png")
    defer discard catch File.delete(textFile)
    defer discard catch File.delete(binaryFile)
    expect File.writeAllBytes(textFile, "plain UTF-8 text")
    expect File.writeAllBytes(binaryFile, [0x89'u8, 0x50'u8, 0x4E'u8, 0x47'u8, 0'u8, 0xFF'u8])

    let index = expect ViewerPluginIndex.parse("image|Image|plugin.image.dll|.png;.gif\nhex|Hexadecimal|plugin.hex.dll|*", "plugins")
    @assert(index.specs.count == 2)
    let picture = index.choices(binaryFile)
    @assert(picture.count == 2)
    @assert(picture[0].name == "Image")
    @assert(picture[1].name == "Hexadecimal")

    let unknown = index.choices(textFile)
    @assert(unknown.count == 2)
    @assert(unknown[0].kind == .BasicText)
    @assert(unknown[1].name == "Hexadecimal")
    @assert(index.explicitlySupports("clip.gif"))
    @assert(!index.explicitlySupports("clip.bin"))

    let named = expect ViewerPluginIndex.parse("code|Code|plugin.code.dll|.html;makefile;dockerfile\nhtml|HTML|plugin.html.dll|.html", "plugins")
    @assert(named.explicitlySupports("Makefile"))
    @assert(named.explicitlySupports("DOCKERFILE"))
    let html = named.choices("page.html")
    @assert(html.count == 2)
    @assert(html[0].name == "Code" and html[1].name == "HTML")

    let shipped     = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let shippedHtml = shipped.choices("page.html")
    @assert(shippedHtml[0].name == "HTML" and shippedHtml[1].name == "Code")
    @assert(shipped.choices("Makefile")[0].name == "Code")
    @assert(shipped.choices("Dockerfile")[0].name == "Code")
}

#test
{
    discard catch ViewerPluginIndex.parse("broken", "plugins") as firstError
    discard catch ViewerPluginIndex.parse("one|One|one.dll|", "plugins") as secondError
    @assert(firstError != null)
    @assert(secondError != null)
}
