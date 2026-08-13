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

const G_Extent = Extent{width: 4, height: 2}

#assert(G_Extent.area() == 8)
#assert(G_Extent.isWide())

#test
{
    let local = Extent{width: 3, height: 5}
    @assert(local.area() == 15)
    @assert(!local.isWide())
}
