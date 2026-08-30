#global private

enum A { R, G, B }

struct Holder
{
    value: A
}

func pickA(flag: bool)->A
{
    if flag
    {
        return .R
    }

    return .B
}

func isGreen(value: A)->bool
{
    return value == .G
}

// Auto-scope enum in vars, arrays, structs, calls
#test
{
    let value:  A        = .G
    let holder: Holder   = {value: A.B}
    let values: [3] A    = [.R, .G, .B]
    let matrix: [2, 2] A = [[.R, .G], [.B, .R]]

    Swag.assert(value == A.G)
    Swag.assert(isGreen(value))
    Swag.assert(holder.value == A.B)
    Swag.assert(values[0] == .R)
    Swag.assert(values[1] == .G)
    Swag.assert(values[2] == .B)
    Swag.assert(matrix[0][0] == .R)
    Swag.assert(matrix[0][1] == .G)
    Swag.assert(matrix[1][0] == .B)
    Swag.assert(matrix[1][1] == .R)
    Swag.assert(pickA(true) == .R)
    Swag.assert(pickA(false) == .B)
}

// Auto-scope enum in conditionals and reassignment
#test
{
    var value: A   = .R
    var total: s32 = 0

    if value == .R
    {
        total += 1
        value = .G
    }

    if value != .B
    {
        total += 10
    }

    value = .B
    if value == .B
    {
        total += 100
    }

    Swag.assert(total == 111)
    Swag.assert(value == .B)
}
