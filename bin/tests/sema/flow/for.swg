#global fileprivate

func semaTest001()
{
    for 3
    {
        var x = 0
    }
}

func semaTest002()
{
    for i in 3
    {
        var x = i
    }
}

func semaTest003()
{
    for #reverse 5
    {
        var x = 0
    }
}

func semaTest004()
{
    for #reverse i in 5
    {
        var x = i
    }
}

func semaTest005()
{
    for
    {
        break
    }
}

func semaTest006()
{
    for
    {
        break
    }
}

func semaTest007()
{
    for i in 1 to 5
    {
        var x = i
    }
}

func semaTest008()
{
    for i in 1 until 5
    {
        var x = i
    }
}

func semaTest009()
{
    for #reverse i in 1 to 5
    {
        var x = i
    }
}

func semaTest010()
{
    for #reverse i in 1 until 5
    {
        var x = i
    }
}

func semaTest011()
{
    for i in 10 where i > 3
    {
        var x = i
    }
}

func semaTest012()
{
    for i in 0 to 10 where i % 2 == 0
    {
        var x = i
    }
}

func semaTest013()
{
    for i in 0 until 10 where i > 5
    {
        var x = i
    }
}

func semaTest014()
{
    for #reverse i in 10 where i < 5
    {
        var x = i
    }
}

func semaTest015()
{
    for i in 3
    {
        for j in 3
        {
            var x = i
            var y = j
        }
    }
}

func semaTest016()
{
    for 10
    {
        var x = 0
        break
    }
}

func semaTest017()
{
    for i in 10
    {
        var x = i
        continue
        var y = 0 // Unreachable code is allowed
    }
}

func semaTest018()
{
    for 2
    {
        for 2
        {
            break
        }
        var x = 0
    }
}

func semaTest019()
{
    var arr: [5]s32 = [1, 2, 3, 4, 5]
    for arr
    {
        var x = 0
    }
}

func semaTest020()
{
    var arr: [3]s32 = [1, 2, 3]
    for i in arr
    {
        var x = i
    }
}

func semaTest021()
{
    for 3
    {
    }
}

func semaTest022()
{
    for i in 0 to 3
    {
    }
}

func semaTest023()
{
    for 3 do
        var x = 0
}

func semaTest024()
{
    for i in 3 do
        var x = i
}

func semaTest025()
{
    for i in 1
    {
    }

    for i in 1
    {
    }
}

func semaTest026()
{
    var i = 5
    for i in 3
    {
        var x = i // shadows outer i
    }
}

func semaTest027()
{
    for i in 5 where i > 0
    {
        var x = i
    }
}

func semaTest028()
{
    var str: string
    for it in @countof(str) {}
    var v: u32
    for it in v {}
    var v1: s32 = 4
    for it in v1
    {
        #assert(#typeof(it) == s32)
    }
}

func semaTest029()
{
    #[Swag.EnumFlags]
    enum Bits: u32 { A, B, C }

    for idx in Bits
    {
        #assert(#typeof(idx) == u64)
        var x = idx
    }
}

func semaTest030()
{
    switch
    {
    case true:
        for x in 1 do
            var y = x

    case false:
        let x = 0
        var y = x
    }
}
