// swc-option suite-test

#global fileprivate
#global skip
enum A
{
    AA
}

enum B
{
    BB
}

#test
{
    using A, B
    @assert(#typeof(A.AA) != #typeof(B.BB))
}
