#global fileprivate
#global skip
struct A {}

impl A
{
    const A = 0
    #ast "const B = 1"
}
