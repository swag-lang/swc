#pragma once
#include "Backend/Micro/MicroReg.h"

SWC_BEGIN_NAMESPACE();

class CodeGen;
class SymbolVariable;

namespace CodeGenLoopHelpers
{
    MicroReg materializeLoopIndexStateAddress(CodeGen& codeGen, const SymbolVariable& symVar);
    void     emitInitializeLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar);
    MicroReg emitLoadLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar);
    void     emitAdvanceLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar);
}

SWC_END_NAMESPACE();
