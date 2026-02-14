#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* calleePayload = codeGen.payload(nodeExprRef);
    if (!calleePayload || calleePayload->kind != CodeGenNodePayloadKind::ExternalFunctionAddress)
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty());
    if (!args.empty())
        return Result::Continue;

    auto* resultStorage = codeGen.ctx().compiler().allocate<uint64_t>();
    *resultStorage      = 0;

    const MicroABICallReturn ret = {
        .valuePtr   = resultStorage,
        .isVoid     = false,
        .isFloat    = false,
        .isIndirect = false,
        .numBits    = 64,
    };

    emitMicroABICallByAddress(codeGen.builder(), CallConvKind::Host, calleePayload->valueU64, std::span<const MicroABICallArg>{}, ret);

    const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::PointerStorageU64, reinterpret_cast<uint64_t>(resultStorage), nodeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
