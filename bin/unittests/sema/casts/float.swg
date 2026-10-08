#global private

func takes_f32(_: f32) {}
func takes_f64(_: f64) {}

func semaTest001()
{
    var a: u8  = 10
    var b: f32 = a
    discard b
    var c: f64 = a
    discard c
}

func semaTest002()
{
    var a: s32 = -10
    takes_f32(a)
    takes_f64(a)
}

func semaTest003()
{
    var a: u16 = 10
    var b: f32 = a
    discard b
    var c: f64 = a
    discard c
}

func semaTest004()
{
    var a: u32 = 10
    takes_f32(a)
    takes_f64(a)
}

func semaTest005()
{
    var a: s16 = -10
    var b: f32 = a
    discard b
    var c: f64 = a
    discard c
}

func semaTest006()
{
    var a: f32 = 12.5
    var b: f64 = a
    discard b
}
