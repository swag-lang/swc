#global private

// Compile-time evaluation of a method called on a constant receiver: the
// receiver parameter is a non-null value pointer, so lowering the constant
// argument must materialize the struct and pass its address, exactly as a
// reference receiver did.
struct Extent
{
    width:  f32
    height: f32
}

impl Extent
{
    mtd const area()->f32
    {
        return .width * .height
    }

    mtd const isWide()->bool
    {
        return .width > .height
    }
}

struct Channels
{
    red:   u8
    green: u8
    blue:  u8
}

impl Channels
{
    #[Swag.ConstExpr]
    mtd const packed()->u32
    {
        return (cast(u32) .red << 16) | (cast(u32) .green << 8) | .blue
    }
}

const G_Extent = Extent{width: 4, height: 2}

#assert(G_Extent.area() == 8)
#assert(G_Extent.isWide())

#test
{
    let local = Extent{width: 3, height: 5}
    Swag.assert(local.area() == 15)
    Swag.assert(!local.isWide())
}

#test
{
    // Method receivers use compiler-owned pointer storage while folding. A
    // recycled storage address must not turn these distinct values into one
    // cached const call.
    let first  = Channels{red: 0x7F, green: 0xFF, blue: 0xFF}.packed()
    let second = Channels{red: 0xFF, green: 0x7F, blue: 0xFF}.packed()
    let third  = Channels{red: 0xFF, green: 0xFF, blue: 0x7F}.packed()
    Swag.assert(first == 0x007FFFFF)
    Swag.assert(second == 0x00FF7FFF)
    Swag.assert(third == 0x00FFFF7F)
}
