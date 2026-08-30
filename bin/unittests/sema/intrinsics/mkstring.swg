#global private

func semaTest001()
{
    var buf: [100] u8
    let str = Swag.makeString(&buf[0], 10)
    #assert(#typeof(str) == string)
    Swag.assert(str.count == 10)
}
