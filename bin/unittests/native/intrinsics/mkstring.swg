#global private

#test
{
    var buf: [100] u8
    let str = Swag.makeString(&buf[0], 10)
    #assert(#typeof(str) == string)
    Swag.assert(str.count == 10)
}

#test
{
    var buf: [8] u8 = ['s'u8, 'w'u8, 'a'u8, 'g'u8, '-'u8, '4'u8, '2'u8, '!'u8]
    let head        = Swag.makeString(&buf[0], 4)
    let tail        = Swag.makeString(&buf[4], 4)
    let empty       = Swag.makeString(&buf[2], 0)

    #assert(#typeof(head) == string)
    #assert(#typeof(tail) == string)
    #assert(#typeof(empty) == string)
    Swag.assert(head == "swag")
    Swag.assert(tail == "-42!")
    Swag.assert(head[1] == 'w'u8)
    Swag.assert(tail[3] == '!'u8)
    Swag.assert(empty.count == 0)
}

#test
{
    var buf: [5] u8 = ['h'u8, 'e'u8, 'l'u8, 'l'u8, 'o'u8]
    let str         = Swag.makeString(&buf[1], 3)

    #assert(#typeof(str) == string)
    Swag.assert(str == "ell")
    Swag.assert(str.count == 3)
    Swag.assert(str[0] == 'e'u8)
    Swag.assert(str[2] == 'l'u8)
}

#test
{
    var buf: [4] u8 = ['a'u8, 'b'u8, 'c'u8, 'd'u8]
    let str         = Swag.makeString(&buf[2], 0)

    #assert(#typeof(str) == string)
    Swag.assert(str.count == 0)
}

#test
{
    var buf: [6] u8 = ['s'u8, 'w'u8, 'a'u8, 'g'u8, '4'u8, '2'u8]
    let str         = Swag.makeString(&buf[0], 6)
    let bytes       = cast(const [..] u8) str

    #assert(#typeof(bytes) == const [..] u8)
    Swag.assert(bytes.count == 6)
    Swag.assert(bytes[0] == 's'u8)
    Swag.assert(bytes[5] == '2'u8)
    Swag.assert(str == "swag42")
}

#test
{
    var buf: [4] u8    = ['t'u8, 'e'u8, 's'u8, 't'u8]
    let ptr: const *u8 = &buf[0]
    let str            = Swag.makeString(ptr, 4)

    #assert(#typeof(str) == string)
    Swag.assert(str.count == 4)
    Swag.assert(str == "test")
}
