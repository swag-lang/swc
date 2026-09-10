#global if #command == Swag.CompilerCommand.Test

using Swag

#assert(BIG_ENDIAN == (#gettag("Swag.Endian", string, "little") == "big"))
#assert(WINDOWS == (#os == Swag.TargetOs.Windows))
#assert(#safety(Swag.SafetyWhat.Assert))

#test
{
    #static if #gettag("Swag.Endian", string, "little") == "big" do
        Swag.assert(BIG_ENDIAN)
    else do
        Swag.assert(not BIG_ENDIAN)

    #static if #os == Swag.TargetOs.Windows do
        Swag.assert(WINDOWS)
    else do
        Swag.assert(not WINDOWS)
}
