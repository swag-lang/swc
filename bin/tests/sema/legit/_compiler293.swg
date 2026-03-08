#global fileprivate
using Swag

//#[PrintBc]
#run
{
    let b = "XYZ"
    @assert(b[2] == cast(u8) 'Z''rune)
}
