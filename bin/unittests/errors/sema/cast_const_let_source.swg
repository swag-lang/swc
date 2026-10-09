#global private

// A 'let' binding is read-only without its type saying so: a cast that would let the target
// change it shows the source as the 'const' type it is read as. The wording is what is checked.

interface ILetArea
{
    mtd area()->f32
}

struct LetRect
{
    w, h: f32
}

impl ILetArea for LetRect
{
    mtd impl area()->f32 => .w * .h
}

func letSourceInterface()->f32
{
    let rect  = LetRect{2, 5}
    let shape = cast(ILetArea, rect)     // swc-expected-error {{cannot cast from 'const LetRect' to 'ILetArea', because it would remove the 'const' qualifier}}
    return shape.area()
}
