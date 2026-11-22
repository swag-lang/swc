#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// PNG chunk lengths above the format limit fail before the writer reserves a payload.
#test
{
    var failed = false
    catch Png.validateChunkLength(0x80000000'u64)
    {
        failed = true
        Swag.require(Errors.message(Swag.err) == "PNG chunk exceeds the maximum supported size")
    }

    Swag.require(failed)
}
