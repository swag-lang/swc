SWC_MICRO_INSTR_DEF(End, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Label, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Debug, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(Push, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Pop, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Nop, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Ret, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CallIndirect, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1})

SWC_MICRO_INSTR_DEF(JumpTable, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCond, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCondImm, MicroInstrInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadRegReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegImm, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegPtrImm, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemImm, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadSignedExtRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadSignedExtRegReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAddrRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAmcRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemImm, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAddrAmcRegMem, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CmpRegReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpRegZero, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpRegImm, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemImm, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(SetCondReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(ClearReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpUnaryMem, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpUnaryReg, MicroInstrInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadCondRegReg, MicroInstrInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpBinaryRegReg, MicroInstrInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryRegReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegImm, MicroInstrInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegMem, MicroInstrInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemReg, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryMemReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemImm, MicroInstrInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpTernaryRegRegReg, MicroInstrInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::OpTernaryRegRegReg, 4, false, 0})
