#global fileprivate

func takes_f32(v: f32) {}
func takes_f64(v: f64) {}

func semaTest001()
{
    var a: u8 = 10
    var b: f32 = a
    var c: f64 = a
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
    var c: f64 = a
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
    var c: f64 = a
}

func semaTest006()
{
    var a: f32 = 12.5
    var b: f64 = a
}
