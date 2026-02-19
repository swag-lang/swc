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

SWC_BEGIN_NAMESPACE();

namespace
{
    bool canUseDirectCallReturnWriteBack(const AstNode& exprNode, const CodeGenNodePayload& payload, const ABITypeNormalize::NormalizedType& normalizedRet)
    {
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;

        if (exprNode.isNot(AstNodeId::CallExpr))
            return false;

        return payload.storageKind == CodeGenNodePayload::StorageKind::Value;
    }
}

Result AstCompilerRunExpr::codeGenPreNode(CodeGen& codeGen)
{
    const CallConv& callConv = CallConv::host();
    SWC_ASSERT(!callConv.intArgRegs.empty());

    const MicroReg            outputStorageReg = callConv.intArgRegs[0];
    const CodeGenNodePayload& nodePayload      = codeGen.setPayloadAddress(codeGen.curNodeRef());
    codeGen.builder().emitLoadRegReg(nodePayload.reg, outputStorageReg, MicroOpBits::B64);
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const CallConv& callConv     = CallConv::host();
    constexpr auto  callConvKind = CallConvKind::Host;
    MicroBuilder&   builder      = codeGen.builder();
    const auto      exprView     = codeGen.sema().nodeViewType(nodeExprRef);
    SWC_ASSERT(exprView.type());

    const CodeGenNodePayload* payload = codeGen.payload(nodeExprRef);
    SWC_ASSERT(payload != nullptr);
    const MicroReg            payloadReg       = payload->reg;
    const bool                payloadLValue    = payload->storageKind == CodeGenNodePayload::StorageKind::Address;
    const CodeGenNodePayload* runExprPayload   = codeGen.payload(codeGen.curNodeRef());
    const MicroReg            outputStorageReg = runExprPayload ? runExprPayload->reg : MicroReg::invalid();
    SWC_ASSERT(outputStorageReg.isValid());
    const AstNode& exprNode = codeGen.node(nodeExprRef);

    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(codeGen.ctx(), callConv, exprView.typeRef(), ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(normalizedRet.indirectSize != 0);
        if (payload->storageKind == CodeGenNodePayload::StorageKind::Address)
        {
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
        }
        else
        {
            const uint32_t spillSize = normalizedRet.indirectSize;
            std::byte*     spillData = codeGen.compiler().allocateArray<std::byte>(spillSize);
            std::memset(spillData, 0, spillSize);

            const MicroReg spillAddrReg = codeGen.nextVirtualIntRegister();

            builder.emitLoadRegPtrImm(spillAddrReg, reinterpret_cast<uint64_t>(spillData));
            builder.emitLoadMemReg(spillAddrReg, 0, payloadReg, MicroOpBits::B64);
            CodeGenHelpers::emitMemCopy(codeGen, outputStorageReg, spillAddrReg, spillSize);
        }
    }
    else
    {
        if (canUseDirectCallReturnWriteBack(exprNode, *payload, normalizedRet))
            ABICall::storeReturnRegsToReturnBuffer(builder, callConvKind, outputStorageReg, normalizedRet);
        else
            ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);
    }
    builder.emitRet();
    return Result::Continue;
}

SWC_END_NAMESPACE();

