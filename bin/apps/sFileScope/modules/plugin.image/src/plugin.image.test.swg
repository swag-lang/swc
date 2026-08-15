#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("filescope_image_%.svg", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    let source = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 64 32\"><rect width=\"64\" height=\"32\" fill=\"#f7f900\"/></svg>"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source)

    let image = expect loadViewerImage(fileName)
    @assert(image.width == 64 and image.height == 32)
}
