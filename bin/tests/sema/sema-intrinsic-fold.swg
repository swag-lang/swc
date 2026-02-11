#global internal

#test
{
    // Constant folding of math intrinsics when all arguments are constant.
    const A: f64 = @sqrt(4.0'f32)
    const B: f64 = @sin(0.0'f32)
    const C: f64 = @pow(2.0, 8.0'f32)
    const D: f64 = @min(1.0, 2.0'f32)
    const E: f64 = @max(1.0, 2.0'f32)
}

#test
{
    // Not folded when argument is not constant -> cannot initialize a const.
    var x: f64 = 4.0
    const A: f64 = @sqrt(x) // swc-expected-error {{sema_err_expr_not_const}}
}

#test
{
    const A: f64 = @sqrt(-1.0'f32) // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const B: f64 = @log(0.0'f32)   // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}

#test
{
    const C: f64 = @asin(2.0'f32)  // swc-expected-error {{sema_err_intrinsic_invalid_argument}}
}
