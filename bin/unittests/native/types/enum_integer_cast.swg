#global private

enum Color: s32
{
    Red = 1
    Green = 4
}

enum Ratio: f32
{
    Normal = 1.0
    Fast   = 2.0
}

#[Swag.EnumFlags]
enum Access: u32
{
    Read
    Write
}

#[Swag.Incomplete]
enum OpenCode: u32
{
    Known = 1
}

#test
{
    const green: Color = cast(Color, 4's32)
    Swag.require(green == .Green)
    const fast: Ratio = cast(Ratio, 2.0'f32)
    Swag.require(fast == .Fast)

    var raw: u32 = 3
    var both: Access = cast(Access, raw)
    Swag.require(both == (Access.Read | Access.Write))

    var unknown: u32 = 99
    Swag.require(cast(u32, cast(OpenCode, unknown)) == 99)
}
