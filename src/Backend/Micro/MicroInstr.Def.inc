SWC_MICRO_INSTR_DEF(
    End,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Label,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Debug,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    Push,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Pop,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Nop,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    Ret,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::TerminatorInstruction,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    CallIndirect,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 1,
        .flags = MicroInstrFlagsE::IsCallInstruction,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    JumpTable,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    JumpCond,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction | MicroInstrFlagsE::ConditionalJump | MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    JumpReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    JumpCondImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::TerminatorInstruction | MicroInstrFlagsE::JumpInstruction | MicroInstrFlagsE::ConditionalJump | MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegPtrImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 1,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    LoadMemReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    LoadMemImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 2,
    })

SWC_MICRO_INSTR_DEF(
    LoadSignedExtRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    LoadZeroExtRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    LoadSignedExtRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadZeroExtRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadAddrRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 1,
        .memOffsetOperandIndex = 3,
    })

SWC_MICRO_INSTR_DEF(
    LoadAmcRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAmcMemReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAmcMemImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    LoadAddrAmcRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    CmpRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CmpRegZero,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CmpRegImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    CmpMemReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    CmpMemImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 2,
    })

SWC_MICRO_INSTR_DEF(
    SetCondReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    ClearReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    OpUnaryMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 3,
    })
SWC_MICRO_INSTR_DEF(
    OpUnaryReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    LoadCondRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::UsesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })

SWC_MICRO_INSTR_DEF(
    OpBinaryRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::OpBinaryRegReg,
        .microOpIndex = 3,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryRegImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryRegMem,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 1,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryMemReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::OpBinaryMemReg,
        .microOpIndex = 3,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 4,
    })
SWC_MICRO_INSTR_DEF(
    OpBinaryMemImm,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None},
        .special = MicroInstrRegSpecial::None,
        .microOpIndex = 0,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::DefinesCpuFlags | MicroInstrFlagsE::HasMemBaseOffsetOperands,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 3,
    })

SWC_MICRO_INSTR_DEF(
    OpTernaryRegRegReg,
    MicroInstrDef{
        .regModes = {MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use},
        .special = MicroInstrRegSpecial::OpTernaryRegRegReg,
        .microOpIndex = 4,
        .callConvIndex = 0,
        .flags = MicroInstrFlagsE::Zero,
        .memBaseOperandIndex = 0,
        .memOffsetOperandIndex = 0,
    })
