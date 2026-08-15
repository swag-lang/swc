#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let index = expect ViewerPluginIndex.parse("image|image.dll|.png;.gif\ntext|text.dll|.txt", "plugins")
    @assert(index.specs.count == 2)
    @assert(index.find("PICTURE.PNG")!.id == "image")
    @assert(index.find("notes.txt")!.id == "text")
    @assert(index.find("README.unknown") == null)
    @assert(index.explicitlySupports("clip.gif"))
    @assert(!index.explicitlySupports("clip.bin"))
}

#test
{
    discard catch ViewerPluginIndex.parse("broken", "plugins") as firstError
    discard catch ViewerPluginIndex.parse("one|one.dll|", "plugins") as secondError
    @assert(firstError != null)
    @assert(secondError != null)
}
