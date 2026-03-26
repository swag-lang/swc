#global fileprivate

// Real-life example: execute a tiny calibration controller program and verify
// the emitted digit stream after register transformations.

struct VmState
{
    regA: u64
    regB: u64
    regC: u64
}

struct VmReport
{
    finalA:         u64
    finalB:         u64
    finalC:         u64
    outputCount:    u32
    outputChecksum: u64
}

func comboOperand(state: VmState, operand: u8)->u64
{
    switch operand
    {
        case 0, 1, 2, 3:
            return cast(u64) operand

        case 4:
            return state.regA

        case 5:
            return state.regB

        case 6:
            return state.regC

        default:
            @assert(false)
            return 0'u64
    }
}

func executeProgram(initial: VmState, program: const [..] u8)->VmReport
{
    var state = initial
    var ip: u32
    var result: VmReport

    while ip + 1 < @countof(program)
    {
        let opcode = program[ip]
        let operand = program[ip + 1]
        var jumped = false

        switch opcode
        {
            case 0:
                state.regA >>= cast(u32) comboOperand(state, operand)
                break

            case 1:
                state.regB ^= cast(u64) operand
                break

            case 2:
                state.regB = comboOperand(state, operand) % 8'u64
                break

            case 3:
                if state.regA != 0'u64
                {
                    ip = cast(u32) operand
                    jumped = true
                }
                break

            case 4:
                state.regB ^= state.regC
                break

            case 5:
                result.outputChecksum = result.outputChecksum * 10'u64 + comboOperand(state, operand) % 8'u64
                result.outputCount += 1
                break

            case 6:
                state.regB = state.regA >> cast(u32) comboOperand(state, operand)
                break

            case 7:
                state.regC = state.regA >> cast(u32) comboOperand(state, operand)
                break

            default:
                @assert(false)
                break
        }

        if !jumped do
            ip += 2
    }

    result.finalA = state.regA
    result.finalB = state.regB
    result.finalC = state.regC
    return result
}

#test
{
    const sampleProgram: [6] u8 = [0, 1, 5, 4, 3, 0]

    let sampleReport = executeProgram({regA: 729'u64, regB: 0'u64, regC: 0'u64}, sampleProgram)

    @assert(sampleReport.finalA == 0'u64)
    @assert(sampleReport.finalB == 0'u64)
    @assert(sampleReport.finalC == 0'u64)
    @assert(sampleReport.outputCount == 10'u32)
    @assert(sampleReport.outputChecksum == 4_635_635_210'u64)

    const outputProgram: [6] u8 = [5, 0, 5, 1, 5, 4]
    let outputReport = executeProgram({regA: 10'u64, regB: 0'u64, regC: 0'u64}, outputProgram)

    @assert(outputReport.outputCount == 3'u32)
    @assert(outputReport.outputChecksum == 12'u64)
    @assert(outputReport.finalA == 10'u64)

    const xorProgram: [2] u8 = [1, 7]
    let xorReport = executeProgram({regA: 0'u64, regB: 29'u64, regC: 0'u64}, xorProgram)

    @assert(xorReport.finalB == 26'u64)
    @assert(xorReport.outputCount == 0'u32)

    const mixedProgram: [2] u8 = [4, 0]
    let mixedReport = executeProgram({regA: 0'u64, regB: 2024'u64, regC: 43_690'u64}, mixedProgram)

    @assert(mixedReport.finalB == 44_354'u64)
    @assert(mixedReport.finalC == 43_690'u64)
}
