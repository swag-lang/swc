#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product64(a, b: u64)->u64 => a * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func product32(a, b: u32)->u32 => a * b

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func timesSeven(a: u64)->u64 => a * 7

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked64(a, b: u64)->u64 => a * b

#[Swag.NoInline, Swag.Safety(.Overflow, true)]
func checked32(a, b: u32)->u32 => a * b

#test
{
    Swag.assert(product64(0, 0xFFFFFFFFFFFFFFFF) == 0)
    Swag.assert(product64(0xFFFFFFFFFFFFFFFF, 3) == 0xFFFFFFFFFFFFFFFD)
    Swag.assert(product64(0x8000000000000000, 2) == 0)
    Swag.assert(product32(0xFFFFFFFF, 3) == 0xFFFFFFFD)
    Swag.assert(product32(0x80000000, 2) == 0)
    Swag.assert(timesSeven(123) == 861)
    Swag.assert(timesSeven(0xFFFFFFFFFFFFFFFF) == 0xFFFFFFFFFFFFFFF9)
    // These fit unsigned arithmetic but overflow the corresponding signed product.
    Swag.assert(checked64(0x7FFFFFFFFFFFFFFF, 2) == 0xFFFFFFFFFFFFFFFE)
    Swag.assert(checked32(0x7FFFFFFF, 2) == 0xFFFFFFFE)
}
