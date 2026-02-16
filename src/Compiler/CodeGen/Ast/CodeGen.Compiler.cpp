#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    auto&              ctx          = codeGen.ctx();
    const auto&        callConv     = CallConv::host();
    constexpr auto     callConvKind = CallConvKind::Host;
    MicroInstrBuilder& builder      = codeGen.builder();
    const auto         exprView     = codeGen.nodeView(nodeExprRef);
    SWC_ASSERT(exprView.type);

    const auto* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg payloadReg    = payload->reg;
    const bool     payloadLValue = codeGen.sema().isLValue(nodeExprRef);

    SWC_ASSERT(!callConv.intArgRegs.empty());
    const MicroReg outputStorageReg = callConv.intArgRegs[0];
    const auto     normalizedRet    = ABITypeNormalize::normalize(ctx, callConv, exprView.typeRef, ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(normalizedRet.indirectSize != 0);
        CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
    }
    else
    {
        ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);
    }
    builder.encodeRet();
    return Result::Continue;
}

SWC_END_NAMESPACE();
