SWC_MICRO_INSTR_DEF(End, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Label, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Debug, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(Push, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Pop, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Nop, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Ret, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CallIndirect, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1})

SWC_MICRO_INSTR_DEF(JumpTable, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCond, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCondImm, MicroInstrDef{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadRegReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegImm, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegPtrImm, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemImm, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadSignedExtRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadSignedExtRegReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAddrRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAmcRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemImm, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAddrAmcRegMem, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CmpRegReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpRegZero, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpRegImm, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemImm, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(SetCondReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(ClearReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpUnaryMem, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpUnaryReg, MicroInstrDef{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadCondRegReg, MicroInstrDef{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpBinaryRegReg, MicroInstrDef{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryRegReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegImm, MicroInstrDef{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegMem, MicroInstrDef{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemReg, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryMemReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemImm, MicroInstrDef{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpTernaryRegRegReg, MicroInstrDef{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::OpTernaryRegRegReg, 4, false, 0})
