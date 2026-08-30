#global public
using Swag

// Vectors crossing the module boundary: the generated export re-emits the
// '#simd' spelling and the consumer reaches these through the generated
// Swag-convention foreign declarations.
#[Swag.NoInline]
func depAddVectors(a, b: #simd [4] s32)->#simd [4] s32 => a + b

#[Swag.NoInline]
func depSatAddVectors(a, b: #simd [16] u8)->#simd [16] u8 => Swag.vecsatadd(a, b)
