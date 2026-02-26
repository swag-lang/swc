#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool canUseDirectCallReturnWriteBack(const AstNode& exprNode, const CodeGenNodePayload& payload, const ABITypeNormalize::NormalizedType& normalizedRet)
    {
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;

        if (exprNode.isNot(AstNodeId::CallExpr))
            return false;

        return payload.isValue();
    }
}

Result AstCompilerRunExpr::codeGenPreNode(CodeGen& codeGen)
{
    const CallConvKind callConvKind = codeGen.function().callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    SWC_ASSERT(!callConv.intArgRegs.empty());

    const MicroReg            outputStorageReg = callConv.intArgRegs[0];
    const CodeGenNodePayload& nodePayload      = codeGen.setPayloadAddress(codeGen.curNodeRef());
    codeGen.builder().emitLoadRegReg(nodePayload.reg, outputStorageReg, MicroOpBits::B64);
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CallConvKind callConvKind = codeGen.function().callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    MicroBuilder&      builder      = codeGen.builder();
    const SemaNodeView exprView     = codeGen.viewType(nodeExprRef);
    SWC_ASSERT(exprView.type());

    const CodeGenNodePayload& exprPayload      = codeGen.payload(nodeExprRef);
    const MicroReg            payloadReg       = exprPayload.reg;
    const bool                payloadLValue    = exprPayload.isAddress();
    const CodeGenNodePayload& runExprPayload   = codeGen.payload(codeGen.curNodeRef());
    const MicroReg            outputStorageReg = runExprPayload.reg;
    const AstNode&            exprNode         = codeGen.node(nodeExprRef);

    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, exprView.typeRef(), ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(normalizedRet.indirectSize != 0);
        if (exprPayload.isAddress())
        {
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
        }
        else
        {
            const uint32_t spillSize = normalizedRet.indirectSize;
            auto*          spillData = codeGen.compiler().allocateArray<std::byte>(spillSize);
            std::memset(spillData, 0, spillSize);

            const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();

            builder.emitLoadRegPtrImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData));
            builder.emitLoadMemReg(spillAddrReg, 0, payloadReg, MicroOpBits::B64);
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, spillAddrReg, spillSize);
        }
    }
    else
    {
        if (canUseDirectCallReturnWriteBack(exprNode, exprPayload, normalizedRet))
            ABICall::storeReturnRegsToReturnBuffer(builder, callConvKind, outputStorageReg, normalizedRet);
        else
            ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);
    }
    builder.emitRet();
    return Result::Continue;
}

SWC_END_NAMESPACE();
