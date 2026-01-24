#global internal

#[Swag.EnumFlags]
enum A { R = 1, G = 2, B = 4 }

const B: A = .R
const C = A.R | .G
#assert(C == 3)

const D = A.R & ~.G

#test
{
    var request: *Swag.AllocatorRequest
    if request.mode == .Realloc {}
}

func toto()->A { return .R }
#test
{
    if(toto() == .R) {}
}

#test
{
    if !(@rtflags & .FromCompiler) {}

    var v = @getcontext()
    var v1 = v.flags
    var v2 = v1 & .ByteCode

}