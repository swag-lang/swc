//

#global fileprivate

using Swag

#[Compiler]
var G = 0

#[Compiler]
func toto()->s32
{
    for 10 do
        G += 1

    return G
}

#assert(#run toto() == 10)
