#global fileprivate // swc-option sema-only
#global skip
#[Swag.Overload]
func isZeroEpsilon(x: f32) => false
#[Swag.Overload]
func isZeroEpsilon() => isZeroEpsilon(0)
