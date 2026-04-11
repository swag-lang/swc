#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenLoopHelpers.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

MicroReg CodeGenLoopHelpers::materializeLoopIndexStateAddress(CodeGen& codeGen, const SymbolVariable& symVar)
{
    SWC_ASSERT(symVar.hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack));
    return codeGen.resolveLocalStackPayload(symVar).reg;
}

void CodeGenLoopHelpers::emitInitializeLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
{
    MicroBuilder&  builder      = codeGen.builder();
    const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
    const MicroReg zeroReg      = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegImm(zeroReg, ApInt(0, 64), MicroOpBits::B64);
    builder.emitLoadMemReg(stateAddrReg, 0, zeroReg, MicroOpBits::B64);
}

MicroReg CodeGenLoopHelpers::emitLoadLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
{
    MicroBuilder&  builder      = codeGen.builder();
    const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
    const MicroReg indexReg     = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegMem(indexReg, stateAddrReg, 0, MicroOpBits::B64);
    return indexReg;
}

void CodeGenLoopHelpers::emitAdvanceLoopIndexState(CodeGen& codeGen, const SymbolVariable& symVar)
{
    MicroBuilder&  builder      = codeGen.builder();
    const MicroReg stateAddrReg = materializeLoopIndexStateAddress(codeGen, symVar);
    const MicroReg indexReg     = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegMem(indexReg, stateAddrReg, 0, MicroOpBits::B64);
    builder.emitOpBinaryRegImm(indexReg, ApInt(1, 64), MicroOp::Add, MicroOpBits::B64);
    builder.emitLoadMemReg(stateAddrReg, 0, indexReg, MicroOpBits::B64);
}

SWC_END_NAMESPACE();
