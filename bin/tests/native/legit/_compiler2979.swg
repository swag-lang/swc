//

#global fileprivate

#[Swag.Compiler]
const X: [2] s32 = [10, 20]

#[Swag.Optimize(false), Swag.Compiler]
func test()->bool
{
    let val = X[1]
    return val == 20 and X[1] == 20
}

#assert(#run test())
