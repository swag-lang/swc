#global private

// A constant struct as a UFCS receiver: the pointer parameter must receive the address
// of the constant's STATIC payload - a segment address every backend relocates. Lowered
// to bytes instead, the pointer baked a compiler-memory address into the emitted code,
// which the JIT could follow and a native image could not.
struct Fmt
{
    name:       string
    extensions: string
}

impl Fmt
{
    #[Swag.NoInline]
    mtd const extensionCount()->u64
    {
        return (.extensions).count
    }

    #[Swag.NoInline]
    mtd const firstByte()->u8
    {
        return .extensions[0]
    }
}

#test
{
    // Literal-initialized let: the receiver keeps its constant.
    let png = Fmt{"PNG", ".png"}
    Swag.assert(png.extensionCount() == 4)
    Swag.assert(png.firstByte() == '.'u8)
}

const G_Png = Fmt{"PNG", ".png"}

#test
{
    // Global constant receiver.
    Swag.assert(G_Png.extensionCount() == 4)
    Swag.assert(G_Png.firstByte() == '.'u8)
}
