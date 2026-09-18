#global private

// A decimal float literal denotes the double nearest to its exact decimal value. Scaling the
// digits by a power of ten in floating point rounds twice and misses by an ulp on values as
// plain as 1.005.

#test
{
    Swag.assert(cast #bit (u64) 1.005 == 0x3FF0147AE147AE14)
    Swag.assert(cast #bit (u64) 0.00012 == 0x3F1F75104D551D69)
    Swag.assert(cast #bit (u64) 0.1 == 0x3FB999999999999A)
    Swag.assert(cast #bit (u64) 0.3 == 0x3FD3333333333333)
    Swag.assert(cast #bit (u64) 1e23 == 0x44B52D02C7E14AF6)
    Swag.assert(cast #bit (u64) 9007199254740993.0'f64 == 0x4340000000000000)
    Swag.assert(cast #bit (u64) 1.7976931348623157e308 == 0x7FEFFFFFFFFFFFFF)
    Swag.assert(cast #bit (u64) 2.2250738585072011e-308 == 0x000FFFFFFFFFFFFF)
    Swag.assert(cast #bit (u64) 4.9406564584124654e-324 == 1)
    Swag.assert(cast #bit (u64) 123_456.789_012 == 0x40FE240C9FCB0C02)
}

// The same values computed at run time agree with the folded ones.
#test
{
    var thousand = 1000.0
    Swag.assert(1.005 == 1005.0 / thousand)
}
