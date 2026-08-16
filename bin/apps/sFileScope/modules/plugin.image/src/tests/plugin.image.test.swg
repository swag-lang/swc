#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "files/sample.svg")

    let image = expect loadViewerImage(fileName)
    @assert(image.width == 128 and image.height == 64)
}
