#global fileprivate

func semaTest001()
{
    if var x: s32 = 1 where x
    {
        var y = x
    }
}

func semaTest002()
{
    if var x = 0
    {
    }
    else
    {
        var y = x
    }
}

func semaTest003()
{
    if var x = 1 where false
    {
    }
    else
    {
        var y = x
    }
}

func semaTest004()
{
    if var x = 0 where x == 0
    {
        var y = x
    }
}

func semaTest005()
{
    var result = 0
    var base = 42
    if var x: #null *s32 = &base where x != null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

func semaTest006()
{
    var result = 0
    if var x: #null string = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}

func semaTest007()
{
    var result = 0
    if var x: #null [..] s32 = null where x == null
    {
        result = 1
    }
    else
    {
        result = -1
    }
    @assert(result == 1)
}
