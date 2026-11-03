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
    Swag.require(product64(0, 0xFFFFFFFFFFFFFFFF) == 0)
    Swag.require(product64(0xFFFFFFFFFFFFFFFF, 3) == 0xFFFFFFFFFFFFFFFD)
    Swag.require(product64(0x8000000000000000, 2) == 0)
    Swag.require(product32(0xFFFFFFFF, 3) == 0xFFFFFFFD)
    Swag.require(product32(0x80000000, 2) == 0)
    Swag.require(timesSeven(123) == 861)
    Swag.require(timesSeven(0xFFFFFFFFFFFFFFFF) == 0xFFFFFFFFFFFFFFF9)
    // These fit unsigned arithmetic but overflow the corresponding signed product.
    Swag.require(checked64(0x7FFFFFFFFFFFFFFF, 2) == 0xFFFFFFFFFFFFFFFE)
    Swag.require(checked32(0x7FFFFFFF, 2) == 0xFFFFFFFE)
}
