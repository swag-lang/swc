#global private
#[Swag.EnumFlags]
enum A { R = 1, G = 2, B = 4 }

const B: A = .R
const C    = A.R | .G
#assert(C == 3)

const D = A.R & ~.G

enum AutoScopeMode { Alloc, Free, Realloc }

struct AutoScopeRequest
{
    mode = AutoScopeMode.Alloc
}

// Auto-scope enum in struct field assignment
#test
{
    var requestStorage: AutoScopeRequest
    let request = &requestStorage
    request.mode = .Realloc
    if request.mode == .Realloc {}
    @assert(request.mode == .Realloc)
}

func toto()->A { return .R }

// Auto-scope enum in return and comparison
#test
{
    if (toto() == .R) {}
    @assert(toto() == .R)
}

// Auto-scope enum flags with bitwise or
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

// Auto-scope enum through struct field comparison
#test
{
    var f: F
    f.x = .G
    let a = f.x == .G
    @assert(a)
}

const Recent = "Recent"

enum AutoScopeConflictSortMethod
{
    Recent
    FileSize
}

struct AutoScopeConflictLibrary
{
    sortMethod: AutoScopeConflictSortMethod
}

impl AutoScopeConflictLibrary
{
    mtd useConflictName()->bool
    {
        return .sortMethod == .Recent
    }
}

#test
{
    var lib: AutoScopeConflictLibrary
    lib.sortMethod = .Recent

    @assert(lib.sortMethod == .Recent)
    @assert(lib.useConflictName())
}
