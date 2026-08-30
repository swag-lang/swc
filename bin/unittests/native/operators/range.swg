#global private

#test
{
    var countSingle = 0
    for 4 to 4 { countSingle += 1 }
    Swag.assert(countSingle == 1)
}

#test
{
    var a: f32
    var hit = 0
    switch (a)
    {
    case 1 to 2.0:
        hit = 1
        break
    case 1.0 to 2:
        hit = 2
        break
    }
    Swag.assert(hit == 0)
}
