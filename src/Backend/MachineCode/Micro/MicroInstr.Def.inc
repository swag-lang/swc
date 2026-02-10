SWC_MICRO_INSTR_DEF(End, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Enter, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Leave, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Ignore, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Label, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Debug, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(Push, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Pop, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Nop, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(Ret, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(SymbolRelocAddr, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(SymbolRelocValue, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadCallParam, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadCallAddrParam, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadCallZeroExtParam, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(StoreCallParam, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(CallLocal, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1}})
SWC_MICRO_INSTR_DEF(CallExtern, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1}})
SWC_MICRO_INSTR_DEF(CallIndirect, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, true, 1}})

SWC_MICRO_INSTR_DEF(JumpTable, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(JumpCond, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(JumpReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(JumpCondImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(PatchJump, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::None, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadRegImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadMemReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadMemImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadSignedExtRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadSignedExtRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadZeroExtRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadAddrRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadAmcRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadAmcMemReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadAmcMemImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(LoadAddrAmcRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(CmpRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(CmpRegImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(CmpMemReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(CmpMemImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(SetCondReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(ClearReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(OpUnaryMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(OpUnaryReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(LoadCondRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Def, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(OpBinaryRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryRegReg, 3, false, 0}})
SWC_MICRO_INSTR_DEF(OpBinaryRegImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(OpBinaryRegMem, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})
SWC_MICRO_INSTR_DEF(OpBinaryMemReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::Use, MicroInstrRegMode::None}, MicroInstrRegSpecial::OpBinaryMemReg, 3, false, 0}})
SWC_MICRO_INSTR_DEF(OpBinaryMemImm, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::Use, MicroInstrRegMode::None, MicroInstrRegMode::None}, MicroInstrRegSpecial::None, 0, false, 0}})

SWC_MICRO_INSTR_DEF(OpTernaryRegRegReg, MicroInstrOpcodeInfo{MicroInstrRegInfo{{MicroInstrRegMode::UseDef, MicroInstrRegMode::Use, MicroInstrRegMode::Use}, MicroInstrRegSpecial::OpTernaryRegRegReg, 4, false, 0}})
