#global fileprivate
#global #[Swag.Safety(.All, .All, false)]

func eqF32(a: f32, b: f32)->bool { return a == b }
func neF32(a: f32, b: f32)->bool { return a != b }
func ltF32(a: f32, b: f32)->bool { return a < b }
func leF32(a: f32, b: f32)->bool { return a <= b }
func gtF32(a: f32, b: f32)->bool { return a > b }
func geF32(a: f32, b: f32)->bool { return a >= b }
func cmpF32(a: f32, b: f32)->s32 { return a <=> b }

#test
{
    const A = Swag.F32.NaN
    const B = Swag.F32.NaN
    #assert(!#run eqF32(A, B))
    #assert(#run neF32(A, B))
    #assert(!#run ltF32(A, B))
    #assert(!#run leF32(A, B))
    #assert(!#run gtF32(A, B))
    #assert(!#run geF32(A, B))
    #assert(#run cmpF32(A, B) == 0)
}

func eqF64(a: f64, b: f64)->bool { return a == b }
func neF64(a: f64, b: f64)->bool { return a != b }
func ltF64(a: f64, b: f64)->bool { return a < b }
func leF64(a: f64, b: f64)->bool { return a <= b }
func gtF64(a: f64, b: f64)->bool { return a > b }
func geF64(a: f64, b: f64)->bool { return a >= b }
func cmpF64(a: f64, b: f64)->s32 { return a <=> b }

#test
{
    const A = Swag.F64.NaN
    const B = Swag.F64.NaN
    #assert(!#run eqF64(A, B))
    #assert(#run neF64(A, B))
    #assert(!#run ltF64(A, B))
    #assert(!#run leF64(A, B))
    #assert(!#run gtF64(A, B))
    #assert(!#run geF64(A, B))
    #assert(#run cmpF64(A, B) == 0)
}

#test
{
    func switchNaNEquality()->bool
    {
        let value = Swag.F32.NaN
        switch value
        {
            case Swag.F32.NaN:
                return false
            default:
                return true
        }
    }

    const V = #run switchNaNEquality()
    #assert(V)
}

#test
{
    func switchNaNRange()->bool
    {
        let value = Swag.F64.NaN
        switch value
        {
            case to 10.0'f64:
                return false
            default:
                return true
        }
    }

    const V = #run switchNaNRange()
    #assert(V)
}
