#global internal

func appendDigits(lhs, rhs: u64)->u64
{
    var magnitude = 1_u64
    var value     = rhs
    for
    {
        magnitude *= 10
        value     /= 10
        if value == 0
        {
            break
        }
    }

    return lhs * magnitude + rhs
}

func canReachTarget(target: u64, first: u64, operands: [..] u64)->bool
{
    func search(target: u64, accumulator: u64, operands: [..] u64, op: u8)->bool
    {
        var next: u64
        if op == '+'
        {
            next = accumulator + operands[0]
        }
        else if op == '*'
        {
            next = accumulator * operands[0]
        }
        else
        {
            next = appendDigits(accumulator, operands[0])
        }

        if next > target
        {
            return false
        }
        if operands.count == 1
        {
            return next == target
        }

        return search(target, next, operands[1 to], '+') or
               search(target, next, operands[1 to], '*') or
               search(target, next, operands[1 to], '|')
    }

    return search(target, first, operands, '+') or
           search(target, first, operands, '*') or
           search(target, first, operands, '|')
}

#test
{
    let eq0: [4] u64 = [6, 8, 6, 15]
    Swag.require(canReachTarget(7290, eq0[0], eq0[1 to]))

    let eq1: [4] u64 = [9, 7, 18, 13]
    Swag.require(not canReachTarget(21037, eq1[0], eq1[1 to]))
}
