SWC_MICRO_INSTR_DEF(
    End,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Label,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    Push,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Pop,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Nop,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Breakpoint,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
// Sanitizer marker: the storage at [op0.reg .. op0.reg+op1.valueU64) was abandoned by a
// '#move'/'#relocate' (moved-from, not reset). Consumed by the sanity pass; encodes to nothing.
SWC_MICRO_INSTR_DEF(
    SanityInvalidate,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
// Sanitizer marker: the storage at [op0.reg .. op0.reg+op1.valueU64) was declared with an
// explicit 'undefined' initializer (no initialization emitted). Consumed by the sanity
// pass; encodes to nothing.
SWC_MICRO_INSTR_DEF(
    SanityUndefined,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Ret,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::TerminatorInstruction,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    CallLocal,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::IsCallInstruction,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CallExtern,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::IsCallInstruction,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CallIndirect,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 1,
        .flags                 = MicroInstrFlagsE::IsCallInstruction,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    JumpCond,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction | MicroInstrFlagsE::ConditionalJump | MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    JumpReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    JumpCondImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction | MicroInstrFlagsE::ConditionalJump | MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegPtrImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegPtrReloc,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    LoadMemReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    LoadMemImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 2,
    })

SWC_MICRO_INSTR_DEF(
    LoadSignedExtRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    LoadZeroExtRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    LoadSignedExtRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadZeroExtRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadAddrRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 3,
    })

SWC_MICRO_INSTR_DEF(
    LoadAmcRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadSignedExtAmcRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAmcMemReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAmcMemImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAddrAmcRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    CmpRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CmpRegImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CmpMemReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    CmpMemImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 2,
    })

SWC_MICRO_INSTR_DEF(
    SetCondReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    ClearReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    OpUnaryMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    OpUnaryReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadCondRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    OpBinaryRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::OpBinaryRegReg,
        .microOpIndex          = 3,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
// Non-destructive three-operand arithmetic: dst = src1 op src2, with dst
// distinct from both. Legacy SSE has no such shape - it only writes back into
// one of its inputs - so building `c = a * b` means copying a into c first, and
// those copies survive to the hot loop. AVX's VEX encoding takes the three
// registers directly. Two producers: the post-RA peephole folds an existing
// copy into the operation, which is the first point where both are known to
// concern the same physical registers; and the vectorizer emits this form
// directly for its 128-bit packed operations, where letting the copy reach the
// register allocator at all was what made it spill.
SWC_MICRO_INSTR_DEF(
    OpBinaryRegRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 4,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryRegImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryMemReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::OpBinaryMemReg,
        .microOpIndex          = 3,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryMemImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 3,
    })

SWC_MICRO_INSTR_DEF(
    OpTernaryRegRegReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::OpTernaryRegRegReg,
        .microOpIndex          = 4,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadVecRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex   = 1,
        .memOffsetOperandIndex = 3,
    })

SWC_MICRO_INSTR_DEF(
    StoreVecMemReg,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::HasMemBaseOffsetOperands | MicroInstrFlagsE::WritesMemory,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 3,
    })

// Appended after the vector forms to keep prior opcode values stable.
// Indexed movzx: same operand layout as LoadSignedExtAmcRegMem
// [dst, base, index, dstBits, srcBits, mul, add].
SWC_MICRO_INSTR_DEF(
    LoadZeroExtAmcRegMem,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

// Indexed compare against an immediate:
// [base, index, cmpBits, addrBits, mul, add, imm].
SWC_MICRO_INSTR_DEF(
    CmpAmcImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

// Packed four-lane permute (pshufd): dst = shuffle(src, control), with dst
// distinct from src allowed. The only non-destructive reg/reg/imm shape in
// the instruction set, hence its own opcode: [dst, src, opBits, control].
// Does not touch the CPU flags.
SWC_MICRO_INSTR_DEF(
    VecShuffleRegRegImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 0,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })

// Non-destructive shift-by-immediate: dst = src <op> imm, with dst distinct
// from src. Legacy SSE shifts write back into their input, so a rotate - which
// needs its source twice - has to copy it first, and that copy is what the
// register allocator was spilling in vectorized ChaCha rounds. VEX names the
// destination separately. Layout [dst, src, opBits, microOp, imm]. Created
// after register allocation by the post-RA peephole, like the three-operand
// arithmetic form; nothing before then emits this opcode.
SWC_MICRO_INSTR_DEF(
    OpBinaryRegRegImm,
    MicroInstrDef{
        .regModes              = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special               = MicroInstrRegSpecial::None,
        .microOpIndex          = 3,
        .callConvIndex         = 0,
        .flags                 = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex   = 0,
        .memOffsetOperandIndex = 0,
    })
