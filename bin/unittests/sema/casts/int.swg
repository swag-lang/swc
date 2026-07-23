#global private

func takes_u32(v: u32) {}
func takes_u8(v: u8) {}
func takes_s32(v: s32) {}

func semaTest001()
{
    var a: u8 = 10
    var b: u16 = a
    var c: u32 = b
    var d: u64 = c
}

func semaTest002()
{
    var a: s8 = -10
    var b: s16 = a
    var c: s32 = b
    var d: s64 = c
}

func semaTest003()
{
    var a: u32 = 10
    var b: s32 = a
    var c: u32 = b
}

func semaTest004()
{
    const A: u64 = 255
    const B: u8  = A
    #assert(B == 255'u8)
}

func semaTest005()
{
    var a: u16 = 10
    var b: s32 = a
    var c: u32 = b
}

func semaTest006()
{
    const A: s32 = 42
    const B: u8  = A
    #assert(B == 42'u8)
}
