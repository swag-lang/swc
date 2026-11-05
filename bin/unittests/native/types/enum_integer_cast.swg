#global private

enum Color: s32
{
    Red = 1
    Green = 4
}

#[Swag.EnumFlags]
enum Access: u32
{
    Read
    Write
}

#test
{
    const green: Color = cast(Color, 4's32)
    Swag.require(green == .Green)

    const both: Access = cast(Access, 3'u32)
    Swag.require(both == (Access.Read | Access.Write))
}
