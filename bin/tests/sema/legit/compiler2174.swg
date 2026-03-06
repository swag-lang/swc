#global fileprivate
#global skip
#[Swag.EnumFlags]
enum A
{
    R
    G
    B
}

#assert(A.R == 1)
