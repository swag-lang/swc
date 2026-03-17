#global fileprivate // 

#test
{
    var countTo = 0
    for to 4 { countTo += 1 }
    var countUntil = 0
    for until 4 { countUntil += 1 }
    var countSingle = 0
    for 4 to 4 { countSingle += 1 }
    @assert(countTo == 5)
    @assert(countUntil == 4)
    @assert(countSingle == 1)
}

#test
{
    var a: f32
    var hit = 0
    switch(a)
    {
    case 1 to 2.0:
        hit = 1
        break
    case 1.0 to 2:
        hit = 2
        break
    }
    @assert(hit == 0)
}



