#global fileprivate

func semaTest001()
{
    var y: f32
    var p: *void = cast(*void) &y
    var a: any = @mkany(p, f32)
}

func semaTest002()
{
    var y: f32
    var p: [*] void = cast([*] void) &y
    var a: any = @mkany(p, f32)
}
