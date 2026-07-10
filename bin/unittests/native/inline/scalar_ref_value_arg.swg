#global private

var table: [256] u8

#[Swag.Inline]
func inlineByteLookup(c: u8)->u8 => table[c]

#test
{
    table[3] = 37

    var x: u8 = 3
    let r: &u8 = &x

    @assert(inlineByteLookup(r) == 37)
    @assert(inlineByteLookup(cast(u8) r) == 37)
}
