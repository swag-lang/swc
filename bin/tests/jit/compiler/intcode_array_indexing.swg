#global fileprivate

func(T) swapValues(a, b: *T)
{
    let tmp = dref a
    dref a = dref b
    dref b = tmp
}

func maxS32(a, b: s32)->s32
{
    if a >= b do
        return a
    return b
}

func nextPermutation5(values: &[5] s32)->bool
{
    var pivot = 3
    while pivot >= 0 and values[pivot] >= values[pivot + 1] do
        pivot -= 1
    if pivot < 0 do
        return false

    var successor = 4
    while values[successor] <= values[pivot] do
        successor -= 1

    swapValues(&values[pivot], &values[successor])

    var left  = pivot + 1
    var right = 4
    while left < right
    {
        swapValues(&values[left], &values[right])
        left += 1
        right -= 1
    }

    return true
}

moduleprivate func(N: s32) runIntcodeProgram(prg: [N] s32, input: const [2] s32)->s32
{
    var op = prg
    var ip, output, inputIndex = 0
    while op[ip] != 99
    {
        let imm0 = (op[ip] / 100) % 10
        let imm1 = (op[ip] / 1000) % 10
        let inst = op[ip] % 10

        var param0, param1 = 0
        if inst != 3 do
            param0 = imm0 ? op[ip + 1] : op[op[ip + 1]]
        if inst != 3 and inst != 4 do
            param1 = imm1 ? op[ip + 2] : op[op[ip + 2]]

        switch inst
        {
        case 1:
            op[op[ip + 3]] = param0 + param1
            ip += 4
        case 2:
            op[op[ip + 3]] = param0 * param1
            ip += 4
        case 3:
            op[op[ip + 1]] = input[inputIndex]
            ip += 2
            inputIndex += 1
        case 4:
            output = param0
            ip += 2
        case 5:
            ip = param0 ? param1 : ip + 3
        case 6:
            ip = !param0 ? param1 : ip + 3
        case 7:
            op[op[ip + 3]] = param0 < param1 ? 1 : 0
            ip += 4
        case 8:
            op[op[ip + 3]] = param0 == param1 ? 1 : 0
            ip += 4
        }
    }

    return output
}

func(N: s32) maxThrusterSignal(prg: [N] s32)->s32
{
    var phase = [0, 1, 2, 3, 4]
    var total = 0
    for
    {
        var input, phaseIndex = 0
        for amp in 5
        {
            input = runIntcodeProgram(prg, [phase[phaseIndex], input])
            phaseIndex += 1
        }

        total = maxS32(total, input)
        if !nextPermutation5(&phase) do
            break
    }

    return total
}

#test
{
    let program: [11] s32 = [3, 0, 3, 1, 1, 0, 1, 0, 4, 0, 99]
    @assert(runIntcodeProgram(program, [17, 25]) == 42)
}

#test
{
    let program: [17] s32 = [3, 15, 3, 16, 1002, 16, 10, 16, 1, 16, 15, 15, 4, 15, 99, 0, 0]
    @assert(maxThrusterSignal(program) == 43210)
}

#test
{
    let program: [25] s32 = [3, 23, 3, 24, 1002, 24, 10, 24, 1002, 23, -1, 23, 101, 5, 23, 23, 1, 24, 23, 23, 4, 23, 99, 0, 0]
    @assert(maxThrusterSignal(program) == 54321)
}
