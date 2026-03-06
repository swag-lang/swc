#global fileprivate
enum A
{
    Red   = cast(A) B.Red
    Green
    Blue
}

enum B
{
    Red   = 100
    Green
    Blue
}

#assert(A.Red == 100)
#assert(A.Blue == 102)
