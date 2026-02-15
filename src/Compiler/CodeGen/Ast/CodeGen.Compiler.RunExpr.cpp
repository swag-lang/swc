#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/MicroInstrHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx      = codeGen.ctx();
    const auto&        callConv = CallConv::host();
    MicroInstrBuilder& builder  = codeGen.builder();
    const auto         exprView = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);
    if (!exprView.type->isStruct())
        SWC_INTERNAL_ERROR();

    const uint32_t structSize = static_cast<uint32_t>(exprView.type->sizeOf(ctx));
    const auto     passing    = callConv.classifyStructReturnPassing(structSize);
    if (passing != StructArgPassingKind::ByReference)
        SWC_INTERNAL_ERROR();

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg hiddenRetPtrReg = callConv.intArgRegs[0];

    MicroReg srcReg = MicroReg::invalid();
    MicroReg tmpReg = MicroReg::invalid();
    SWC_ASSERT(callConv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&hiddenRetPtrReg, 1}));

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    if (payload->kind != CodeGenNodePayloadKind::DerefPointerStorageU64)
        SWC_INTERNAL_ERROR();

    builder.encodeLoadRegImm(srcReg, payload->valueU64, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeLoadRegMem(srcReg, srcReg, 0, MicroOpBits::B64, EncodeFlagsE::Zero);
    MicroInstrHelpers::emitMemCopy(builder, hiddenRetPtrReg, srcReg, tmpReg, structSize);

    builder.encodeRet(EncodeFlagsE::Zero);
    return Result::Continue;
}

SWC_END_NAMESPACE();
