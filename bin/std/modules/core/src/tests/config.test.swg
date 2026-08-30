#global if #command == Swag.CompilerCommand.Test

using Swag

#assert(BIG_ENDIAN == (#gettag("Swag.Endian", string, "little") == "big"))
#assert(WINDOWS == (#os == Swag.TargetOs.Windows))
#assert(ASSERT == (#cfg == "devmode" or #hastag("Std.Core.Assert")))

#test
{
    #static if #gettag("Swag.Endian", string, "little") == "big" do
        Swag.assert(BIG_ENDIAN)
    else do
        Swag.assert(!BIG_ENDIAN)

    #static if #os == Swag.TargetOs.Windows do
        Swag.assert(WINDOWS)
    else do
        Swag.assert(!WINDOWS)

    #static if #cfg == "devmode" or #hastag("Std.Core.Assert") do
        Swag.assert(ASSERT)
    else do
        Swag.assert(!ASSERT)
}
