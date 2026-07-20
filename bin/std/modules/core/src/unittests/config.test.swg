#global #if #command == Swag.CompilerCommand.Test
using Swag

#assert(BIG_ENDIAN == (#gettag("Swag.Endian", string, "little") == "big"))
#assert(WINDOWS == (#os == Swag.TargetOs.Windows))
#assert(ASSERT == (#cfg == "debug" or #cfg == "fast-debug" or #hastag("Std.Core.Assert")))

#test
{
    #if #gettag("Swag.Endian", string, "little") == "big" do
        @assert(BIG_ENDIAN)
    #else do
        @assert(!BIG_ENDIAN)

    #if #os == Swag.TargetOs.Windows do
        @assert(WINDOWS)
    #else do
        @assert(!WINDOWS)

    #if #cfg == "debug" or #cfg == "fast-debug" or #hastag("Std.Core.Assert") do
        @assert(ASSERT)
    #else do
        @assert(!ASSERT)
}
