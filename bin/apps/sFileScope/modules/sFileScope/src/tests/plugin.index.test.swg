#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let index = expect ViewerPluginIndex.parse("image|Image|plugin.image.dll|.png;.gif\nhex|Hexadecimal|plugin.hex.dll|*", "plugins")
    @assert(index.specs.count == 2)
    let picture = index.choices("PICTURE.PNG")
    @assert(picture.count == 3)
    @assert(picture[0].name == "Image")
    @assert(picture[1].kind == .BasicText)
    @assert(picture[2].name == "Hexadecimal")

    let unknown = index.choices("README.unknown")
    @assert(unknown.count == 2)
    @assert(unknown[0].kind == .BasicText)
    @assert(unknown[1].name == "Hexadecimal")
    @assert(index.explicitlySupports("clip.gif"))
    @assert(!index.explicitlySupports("clip.bin"))
}

#test
{
    discard catch ViewerPluginIndex.parse("broken", "plugins") as firstError
    discard catch ViewerPluginIndex.parse("one|One|one.dll|", "plugins") as secondError
    @assert(firstError != null)
    @assert(secondError != null)
}
