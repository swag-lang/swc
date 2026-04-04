#global fileprivate

const I: [5] string = [
    "Game 1: 3 blue, 4 red; 1 red, 2 green, 6 blue; 2 green",
    "Game 2: 1 blue, 2 green; 3 green, 4 blue, 1 red; 1 green, 1 blue",
    "Game 3: 8 green, 6 blue, 20 red; 5 blue, 4 red, 13 green; 5 green, 1 red",
    "Game 4: 1 green, 3 red, 6 blue; 3 green, 6 red; 3 green, 15 blue, 14 red",
    "Game 5: 6 red, 1 blue, 3 green; 2 blue, 1 red, 2 green",
]

func s()->[2] u32
{
    var r: [2] u32 = [0, 0]

    foreach l, g in I
    {
        var i: u32
        while i < @countof(l) and l[i] != ':''u8 do
            i += 1
        i += 1

        var x: u32 = 0
        var y: u32 = 0
        var z: u32 = 0

        while i < @countof(l)
        {
            if l[i] < '0''u8 or l[i] > '9''u8
            {
                i += 1
                continue
            }

            var n: u32 = 0
            while i < @countof(l) and l[i] >= '0' and l[i] <= '9'
            {
                n = n * 10 + (l[i] & 15)
                i += 1
            }

            i += 1
            switch l[i]
            {
                case 'r' where n > x: x = n
                case 'g' where n > y: y = n
                case 'b' where n > z: z = n
            }

            while i < @countof(l) and l[i] != ',' and l[i] != ';'
            {
                i += 1
            }
        }

        if x <= 12 and y <= 13 and z <= 14 do
            r[0] += cast(u32) g + 1
        r[1] += x * y * z
    }

    return r
}

#test
{
    let r = s()
    @assert(r[0] == 8 and r[1] == 2286)
}
