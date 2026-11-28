#global if #command == Swag.CompilerCommand.Test

using Swag

#assert(BIG_ENDIAN == (#gettag("Swag.Endian", string, "little") == "big"))
#assert(WINDOWS == (#os == Swag.TargetOs.Windows))
#assert(#safety(Swag.SafetyWhat.Assert))

#test
{
    #static if #gettag("Swag.Endian", string, "little") == "big"
    {
        Swag.require(BIG_ENDIAN)
    }
    else
    {
        Swag.require(not BIG_ENDIAN)
    }

    #static if #os == Swag.TargetOs.Windows
    {
        Swag.require(WINDOWS)
    }
    else
    {
        Swag.require(not WINDOWS)
    }
}
