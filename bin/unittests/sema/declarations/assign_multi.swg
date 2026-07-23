#global private

func semaTest001()
{
    var a: s32
    var b: s32
    a, b = 1
    a, b += 1
}

func semaTest002()
{
    var a: s32
    var b: s32
    a, ?, b = 1
}

func semaTest003()
{
    var a: f32
    var b: s32
    a, b = 1
}

func semaTest004()
{
    var x:     u16
    var ptr:   const [*] u16 = cast(const [*] u16) &x
    var count: u64
    ptr, count += 1
    ptr, count -= 1
}
