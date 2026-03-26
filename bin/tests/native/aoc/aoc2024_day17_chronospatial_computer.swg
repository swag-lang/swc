#global fileprivate

// Advent of Code 2024 Day 17: 3-bit computer with 8 opcodes, 3 registers
// (A, B, C) and a combo-operand scheme. Run the program, collect outputs.
// Part 1: comma-separated output. Part 2: find initial A that makes the
// program output itself (solved by reverse-engineering the loop).
// Exercises: #[Swag.Inline] on mtd (the fix), impl with array indexing,
// nested inline mtd calls, bitwise XOR/shift on registers.

const SampleProg  = "0,1,5,4,3,0"
const SampleRegA  = 729'u64

const SmallProg   = "2,6"
const SmallRegA   = 0'u64
const SmallRegC   = 9'u64

const XorProg     = "1,7"
const XorRegB     = 29'u64

// ---------------------------------------------------------------------------
// CPU
// ---------------------------------------------------------------------------

const MaxMem = 32'u32
const MaxOut = 64'u32

struct Cpu
{
    mem:    [MaxMem] u8
    memLen: u32
    regs:   [3] u64       // A=0, B=1, C=2
    ip:     u32
    out:    [MaxOut] u8
    outLen: u32
}

impl Cpu
{
    // Inline mtd with array access — exercises the fix
    #[Swag.Inline]
    mtd fetch() -> u8
    {
        let v = me.mem[me.ip]
        me.ip += 1
        return v
    }

    // Nested inline mtd: combo reads regs through me
    #[Swag.Inline]
    mtd combo(operand: u8) -> u64
    {
        if operand <= 3 do return cast(u64) operand
        return me.regs[operand - 4]
    }

    mtd emit(val: u8)
    {
        me.out[me.outLen] = val
        me.outLen += 1
    }

    mtd reset(a: u64, b: u64, c: u64)
    {
        me.regs[0] = a
        me.regs[1] = b
        me.regs[2] = c
        me.ip     = 0
        me.outLen = 0
    }
}

// ---------------------------------------------------------------------------
// Execution
// ---------------------------------------------------------------------------

func run(cpu: *Cpu)
{
    for
    {
        if cpu.ip >= cpu.memLen do
            break

        let op  = cpu.fetch()
        let arg = cpu.fetch()

        if op == 0       // adv: A >>= combo
        {
            cpu.regs[0] = cpu.regs[0] >> cast(u8) cpu.combo(arg)
        }
        elif op == 1     // bxl: B ^= literal
        {
            cpu.regs[1] ^= cast(u64) arg
        }
        elif op == 2     // bst: B = combo % 8
        {
            cpu.regs[1] = cpu.combo(arg) % 8
        }
        elif op == 3     // jnz: jump if A != 0
        {
            if cpu.regs[0] != 0 do
                cpu.ip = cast(u32) arg
        }
        elif op == 4     // bxc: B ^= C
        {
            cpu.regs[1] = cpu.regs[1] ^ cpu.regs[2]
        }
        elif op == 5     // out: output combo % 8
        {
            cpu.emit(cast(u8) (cpu.combo(arg) % 8))
        }
        elif op == 6     // bdv: B = A >> combo
        {
            cpu.regs[1] = cpu.regs[0] >> cast(u8) cpu.combo(arg)
        }
        elif op == 7     // cdv: C = A >> combo
        {
            cpu.regs[2] = cpu.regs[0] >> cast(u8) cpu.combo(arg)
        }
    }
}

// ---------------------------------------------------------------------------
// Parsing
// ---------------------------------------------------------------------------

func parseProgram(text: string, cpu: *Cpu)
{
    let bytes = cast(const [..] u8) text
    cpu.memLen = 0
    var pos: u32
    for
    {
        if pos >= @countof(bytes) do break
        let ch = bytes[pos]
        if ch >= '0' and ch <= '9'
        {
            cpu.mem[cpu.memLen] = ch - '0'
            cpu.memLen += 1
        }
        pos += 1
    }
}

// ---------------------------------------------------------------------------
// Output comparison
// ---------------------------------------------------------------------------

func outputEquals(cpu: *Cpu, expected: [*] u8, len: u32) -> bool
{
    if cpu.outLen != len do return false
    for i in len
    {
        if cpu.out[i] != expected[i] do return false
    }
    return true
}

func outputMatchesProgram(cpu: *Cpu) -> bool
{
    return outputEquals(cpu, &cpu.mem[0], cpu.memLen)
}

// ---------------------------------------------------------------------------
// Part 2: reverse search for A that produces self-output
// ---------------------------------------------------------------------------

func findSelfOutputA(cpu: *Cpu, maxSearch: u64) -> u64
{
    for a in maxSearch
    {
        cpu.reset(cast(u64) a, 0, 0)
        run(cpu)
        if outputMatchesProgram(cpu) do
            return cast(u64) a
    }
    return 0
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

// Basic parsing
#test
{
    var cpu: Cpu
    parseProgram(SampleProg, &cpu)
    @assert(cpu.memLen == 6'u32)
    @assert(cpu.mem[0] == 0)
    @assert(cpu.mem[1] == 1)
    @assert(cpu.mem[5] == 0)
}

// Inline mtd: fetch advances ip
#test
{
    var cpu: Cpu
    parseProgram(SampleProg, &cpu)
    cpu.ip = 0
    let v0 = cpu.fetch()
    @assert(v0 == 0)
    @assert(cpu.ip == 1'u32)
    let v1 = cpu.fetch()
    @assert(v1 == 1)
    @assert(cpu.ip == 2'u32)
}

// Inline mtd: combo operand
#test
{
    var cpu: Cpu
    cpu.regs[0] = 100
    cpu.regs[1] = 200
    cpu.regs[2] = 300
    @assert(cpu.combo(0) == 0'u64)
    @assert(cpu.combo(3) == 3'u64)
    @assert(cpu.combo(4) == 100'u64)
    @assert(cpu.combo(5) == 200'u64)
    @assert(cpu.combo(6) == 300'u64)
}

// Small example: program 2,6 with C=9 → B = 9%8 = 1
#test
{
    var cpu: Cpu
    parseProgram(SmallProg, &cpu)
    cpu.reset(SmallRegA, 0, SmallRegC)
    run(&cpu)
    @assert(cpu.regs[1] == 1'u64)
}

// XOR example: program 1,7 with B=29 → B = 29^7 = 26
#test
{
    var cpu: Cpu
    parseProgram(XorProg, &cpu)
    cpu.reset(0, XorRegB, 0)
    run(&cpu)
    @assert(cpu.regs[1] == 26'u64)
}

// Sample: A=729, prog=0,1,5,4,3,0 → output 4,6,3,5,6,3,5,2,1,0
#test
{
    var cpu: Cpu
    parseProgram(SampleProg, &cpu)
    cpu.reset(SampleRegA, 0, 0)
    run(&cpu)
    var expected: [10] u8 = [4, 6, 3, 5, 6, 3, 5, 2, 1, 0]
    @assert(outputEquals(&cpu, &expected[0], 10))
}

// Emit test
#test
{
    var cpu: Cpu
    cpu.emit(7)
    cpu.emit(3)
    cpu.emit(1)
    @assert(cpu.outLen == 3'u32)
    @assert(cpu.out[0] == 7)
    @assert(cpu.out[1] == 3)
    @assert(cpu.out[2] == 1)
}

// Reset clears output and sets registers
#test
{
    var cpu: Cpu
    cpu.emit(1)
    cpu.emit(2)
    cpu.reset(10, 20, 30)
    @assert(cpu.outLen == 0'u32)
    @assert(cpu.regs[0] == 10'u64)
    @assert(cpu.regs[1] == 20'u64)
    @assert(cpu.regs[2] == 30'u64)
    @assert(cpu.ip == 0'u32)
}

// Self-output search: prog=0,3,5,4,3,0 with A=117440 outputs itself
#test
{
    var cpu: Cpu
    parseProgram("0,3,5,4,3,0", &cpu)
    cpu.reset(117440, 0, 0)
    run(&cpu)
    @assert(outputMatchesProgram(&cpu))
}

// Bitwise shift: A=1024, adv by 5 → A = 1024 >> 5 = 32
#test
{
    var cpu: Cpu
    parseProgram("0,5", &cpu)
    cpu.reset(1024, 0, 0)
    cpu.regs[1] = 5
    run(&cpu)
    @assert(cpu.regs[0] == 32'u64)
}
