#global fileprivate
#global #[Swag.Safety(.All, false)]

#[Swag.Inline]
func inlineLeF32(a: f32, b: f32)->bool
{
    return a <= b
}

#[Swag.Inline]
func inlineLeF64(a: f64, b: f64)->bool
{
    return a <= b
}

#[Swag.Inline]
func inlineGeF32(a: f32, b: f32)->bool
{
    return a >= b
}

#[Swag.Inline]
func inlineGeF64(a: f64, b: f64)->bool
{
    return a >= b
}

#test
{
    const A = Swag.F32.NaN
    const B = Swag.F32.NaN
    #assert(!#run inlineLeF32(A, B))
    #assert(!#run inlineGeF32(A, B))
}

#test
{
    const A = Swag.F64.NaN
    const B = Swag.F64.NaN
    #assert(!#run inlineLeF64(A, B))
    #assert(!#run inlineGeF64(A, B))
}
