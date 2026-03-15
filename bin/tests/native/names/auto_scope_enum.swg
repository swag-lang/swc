#global fileprivate // swc-option suite-test

#[Swag.EnumFlags]
enum A { R = 1, G = 2, B = 4 }

const B: A = .R
const C = A.R | .G
#assert(C == 3)

const D = A.R & ~.G

#test
{
    var requestStorage: Swag.AllocatorRequest
    let request = &requestStorage
    request.mode = .Realloc
    if request.mode == .Realloc {}
    @assert(request.mode == .Realloc)
}

func toto()->A { return .R }
#test
{
    if(toto() == .R) {}
    @assert(toto() == .R)
}

#test
{
    let x: A = .B
    let y = x | .R
    @assert(y == 5)
}

enum AA { R = 1, G = 2, B = 4 }
struct E {}
struct F
{
    x: AA
}

impl E
{
    mtd foo(f: *F)
    {
        let a = f.x == .R
    }
}

#test
{
    var f: F
    f.x = .G
    let a = f.x == .G
    @assert(a)
}
