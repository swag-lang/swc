#global private

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
        return cast(u64, operand)

    case 4:
        return state.regA

    case 5:
        return state.regB

    case 6:
        return state.regC

    default:
        Swag.assert(false)
        return 0_u64
    }
}

func executeProgram(initial: VmState, program: const [..] u8)->VmReport
{
    var state = initial
    var ip:     u32
    var result: VmReport

    while ip + 1 < program.count
    {
        let opcode  = program[ip]
        let operand = program[ip + 1]
        var jumped  = false

        switch opcode
        {
        case 0:
            state.regA >>= cast(u32, comboOperand(state, operand))
            break

        case 1:
            state.regB ^= cast(u64, operand)
            break

        case 2:
            state.regB = comboOperand(state, operand) % 8_u64
            break

        case 3:
            if state.regA != 0_u64
            {
                ip     = cast(u32, operand)
                jumped = true
            }
            break

        case 4:
            state.regB ^= state.regC
            break

        case 5:
            result.outputChecksum = result.outputChecksum * 10_u64 + comboOperand(state, operand) % 8_u64
            result.outputCount    += 1
            break

        case 6:
            state.regB = state.regA >> cast(u32, comboOperand(state, operand))
            break

        case 7:
            state.regC = state.regA >> cast(u32, comboOperand(state, operand))
            break

        default:
            Swag.assert(false)
            break
        }

        if not jumped
        {
            ip += 2
        }
    }

    result.finalA = state.regA
    result.finalB = state.regB
    result.finalC = state.regC
    return result
}

#test
{
    const sampleProgram: [6] u8 = [0, 1, 5, 4, 3, 0]

    let sampleReport = executeProgram({regA: 729_u64, regB: 0_u64, regC: 0_u64}, sampleProgram)

    Swag.require(sampleReport.finalA == 0_u64)
    Swag.require(sampleReport.finalB == 0_u64)
    Swag.require(sampleReport.finalC == 0_u64)
    Swag.require(sampleReport.outputCount == 10_u32)
    Swag.require(sampleReport.outputChecksum == 4_635_635_210_u64)

    const outputProgram: [6] u8 = [5, 0, 5, 1, 5, 4]
    let outputReport = executeProgram({regA: 10_u64, regB: 0_u64, regC: 0_u64}, outputProgram)

    Swag.require(outputReport.outputCount == 3_u32)
    Swag.require(outputReport.outputChecksum == 12_u64)
    Swag.require(outputReport.finalA == 10_u64)

    const xorProgram: [2] u8 = [1, 7]
    let xorReport = executeProgram({regA: 0_u64, regB: 29_u64, regC: 0_u64}, xorProgram)

    Swag.require(xorReport.finalB == 26_u64)
    Swag.require(xorReport.outputCount == 0_u32)

    const mixedProgram: [2] u8 = [4, 0]
    let mixedReport = executeProgram({regA: 0_u64, regB: 2024_u64, regC: 43_690_u64}, mixedProgram)

    Swag.require(mixedReport.finalB == 44_354_u64)
    Swag.require(mixedReport.finalC == 43_690_u64)
}
