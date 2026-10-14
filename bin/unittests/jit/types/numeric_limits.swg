#global private

// 'Min' and 'Max' are the ends of the finite range for every numeric type, floating point
// included. The smallest positive normal value has its own name.

#assert(Swag.S8.Min == -128 and Swag.S8.Max == 127)
#assert(Swag.S64.Min < 0 and Swag.U64.Min == 0)

#assert(Swag.F32.Min == -Swag.F32.Max)
#assert(Swag.F64.Min == -Swag.F64.Max)
#assert(Swag.F32.Min < -1e38 and Swag.F64.Min < -1e308)

#assert(Swag.F32.MinNormal > 0 and Swag.F32.MinNormal < 1.2e-38)
#assert(Swag.F64.MinNormal > 0 and Swag.F64.MinNormal < 2.3e-308)
#assert(cast #bit (u32, Swag.F32.MinNormal) == 0x0080_0000)
#assert(cast #bit (u64, Swag.F64.MinNormal) == 0x0010_0000_0000_0000)

// A maximum search can start from 'Min' and still see a negative sample.
#test
{
    var highest = Swag.F32.Min
    for value in [-5.0'f32, -2.5, -9.0] do
        highest = Swag.max(highest, value)
    Swag.assert(highest == -2.5)
}
