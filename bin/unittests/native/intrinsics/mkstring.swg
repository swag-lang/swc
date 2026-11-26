#global private

#test
{
    var buf: [100] u8
    let str = Swag.makeString(&buf[0], 10)
    #assert(#typeof(str) == string)
    Swag.require(str.count == 10)
}

#test
{
    var buf: [8] u8 = ['s'_u8, 'w'_u8, 'a'_u8, 'g'_u8, '-'_u8, '4'_u8, '2'_u8, '!'_u8]
    let head        = Swag.makeString(&buf[0], 4)
    let tail        = Swag.makeString(&buf[4], 4)
    let empty       = Swag.makeString(&buf[2], 0)

    #assert(#typeof(head) == string)
    #assert(#typeof(tail) == string)
    #assert(#typeof(empty) == string)
    Swag.require(head == "swag")
    Swag.require(tail == "-42!")
    Swag.require(head[1] == 'w'_u8)
    Swag.require(tail[3] == '!'_u8)
    Swag.require(empty.count == 0)
}

#test
{
    var buf: [5] u8 = ['h'_u8, 'e'_u8, 'l'_u8, 'l'_u8, 'o'_u8]
    let str         = Swag.makeString(&buf[1], 3)

    #assert(#typeof(str) == string)
    Swag.require(str == "ell")
    Swag.require(str.count == 3)
    Swag.require(str[0] == 'e'_u8)
    Swag.require(str[2] == 'l'_u8)
}

#test
{
    var buf: [4] u8 = ['a'_u8, 'b'_u8, 'c'_u8, 'd'_u8]
    let str         = Swag.makeString(&buf[2], 0)

    #assert(#typeof(str) == string)
    Swag.require(str.count == 0)
}

#test
{
    var buf: [6] u8 = ['s'_u8, 'w'_u8, 'a'_u8, 'g'_u8, '4'_u8, '2'_u8]
    let str         = Swag.makeString(&buf[0], 6)
    let bytes       = cast(const [..] u8, str)

    #assert(#typeof(bytes) == const [..] u8)
    Swag.require(bytes.count == 6)
    Swag.require(bytes[0] == 's'_u8)
    Swag.require(bytes[5] == '2'_u8)
    Swag.require(str == "swag42")
}

#test
{
    var buf: [4] u8    = ['t'_u8, 'e'_u8, 's'_u8, 't'_u8]
    let ptr: const *u8 = &buf[0]
    let str            = Swag.makeString(ptr, 4)

    #assert(#typeof(str) == string)
    Swag.require(str.count == 4)
    Swag.require(str == "test")
}
