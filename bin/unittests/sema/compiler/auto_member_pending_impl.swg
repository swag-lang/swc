#global private

// The contextual receiver and the with subject are both candidates. The subject's
// generated member arrives after its impl header has already completed the type.
struct LateMember { unused: s32 }
struct OtherMember { unused: s32 }

impl OtherMember
{
    mtd read()->s32
    {
        var result = 0's32
        with var target: LateMember
        {
            result = .Id
        }
        return result
    }
}

#[Swag.Mixin]
func declareId()
{
    #ast #run buildDeclaration()
}

impl LateMember
{
    declareId()
}

func buildDeclaration()->string => "const Id = 42"

#test
{
    var other: OtherMember
    Swag.assert(other.read() == 42)
}
