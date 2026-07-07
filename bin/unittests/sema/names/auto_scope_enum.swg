#global private

#[Swag.EnumFlags]
enum A { R = 1, G = 2, B = 4 }

const B: A = .R
const C = A.R | .G
#assert(C == 3)

const D = A.R & ~.G

enum AutoScopeMode { Alloc, Free, Realloc }

struct AutoScopeRequest
{
    mode = AutoScopeMode.Alloc
}

func semaTest001()
{
    var request: *AutoScopeRequest
    if request.mode == .Realloc {}
}

func toto()->A { return .R }
func semaTest002()
{
    if(toto() == .R) {}
}

func semaTest003()
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

func semaTest004()
{
    var f: F
    f.x = .G
    let a = f.x == .G
}

enum BindingDirection { North, South }
alias BindingDirectionAlias = BindingDirection

func reverseDirection(dir: BindingDirectionAlias)->BindingDirection
{
    switch dir
    {
        case North: return South
        case South: return North
    }
}

func semaTest005()
{
    let dir: BindingDirectionAlias = .North
    #assert(#typeof(reverseDirection(dir)) == BindingDirection)
}

#[Swag.EnumFlags]
enum ConflictingFlagName
{
    Name
    Other
}

func(T) has(flags, value: T)->bool
{
    return flags & value != 0
}

func(T) add(flags: &T, value: T)
{
    flags |= value
}

struct ConflictingFlagOwner
{
}

impl ConflictingFlagOwner
{
    attr Name(text: string)

    mtd checkFlags()
    {
        var flags = ConflictingFlagName.Name
        let hasName = flags.has(.Name)
        flags.add(.Other)
        let hasOther = flags.has(.Other)
    }
}

func semaTest006()
{
    var owner: ConflictingFlagOwner
    owner.checkFlags()
}
