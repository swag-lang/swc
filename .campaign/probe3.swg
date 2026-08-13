#global private

var g_Root: Sy

struct Sy
{
    x: u64
}

impl Sy
{
    mtd const opEquals(other: #null string)->bool
    {
        return other != null and .x == @countof(other!)
    }

    mtd const opCast()->string => "ab"

    mtd const isEmpty()->bool => .x == 0
}

func makeSy()->Sy
{
    var result: retval
    result.x = 2
    return result
}

#test
{
    let normalized = makeSy()
    if !g_Root.isEmpty()
    {
        if normalized == g_Root
        {
        }
    }
}
