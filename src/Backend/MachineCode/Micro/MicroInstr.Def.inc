SWC_MICRO_INSTR_DEF(End, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Enter, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Leave, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Ignore, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Label, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Debug, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(Push, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Pop, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Nop, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(Ret, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(SymbolRelocAddr, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(SymbolRelocValue, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadCallParam, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadCallAddrParam, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadCallZeroExtParam, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(StoreCallParam, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CallLocal, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1})
SWC_MICRO_INSTR_DEF(CallExtern, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1})
SWC_MICRO_INSTR_DEF(CallIndirect, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1})

SWC_MICRO_INSTR_DEF(JumpTable, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCond, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(JumpCondImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(PatchJump, MicroInstrOpcodeInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadMemImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadSignedExtRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadSignedExtRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAddrRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadAmcRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAmcMemImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(LoadAddrAmcRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(CmpRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpRegImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(CmpMemImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(SetCondReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(ClearReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpUnaryMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpUnaryReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(LoadCondRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpBinaryRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryRegReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryRegMem, MicroInstrOpcodeInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryMemReg, 3, false, 0})
SWC_MICRO_INSTR_DEF(OpBinaryMemImm, MicroInstrOpcodeInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0})

SWC_MICRO_INSTR_DEF(OpTernaryRegRegReg, MicroInstrOpcodeInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::OpTernaryRegRegReg, 4, false, 0})
