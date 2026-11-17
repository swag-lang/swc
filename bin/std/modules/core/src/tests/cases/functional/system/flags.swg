#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#[Swag.EnumFlags]
enum CoreFlagHelpers: u32
{
    Read  = 1
    Write = 2
    Exec  = 4
}

#test
{
    var flags = CoreFlagHelpers.Read | CoreFlagHelpers.Write
    Swag.require(has(flags, .Read))
    Swag.require(not has(flags, .Exec))
    Swag.require(equals(flags, .Read | .Write))
    Swag.require(not equals(flags, .Read))

    add(&flags, .Exec)
    Swag.require(equals(flags, .Read | .Write | .Exec))

    remove(&flags, .Write)
    Swag.require(has(flags, .Read | .Exec))
    Swag.require(not has(flags, .Write))

    toggle(&flags, .Read)
    Swag.require(equals(flags, .Exec))
    Swag.require(has(flags, .Read | .Exec))
    toggle(&flags, .Exec)
    Swag.require(equals(flags, cast(CoreFlagHelpers, 0)))
    toggle(&flags, .Read)
    Swag.require(equals(flags, .Read))

    set(&flags, .Write)
    Swag.require(equals(flags, .Write))
}
