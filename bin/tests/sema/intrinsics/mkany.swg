#global fileprivate

#test
{
    var y: f32
    var p: *void = cast(*void) &y
    var a: any = @mkany(p, f32)
}

#test
{
    var y: f32
    var p: [*] void = cast([*] void) &y
    var a: any = @mkany(p, f32)
}
