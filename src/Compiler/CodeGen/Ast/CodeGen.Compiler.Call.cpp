#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolFunction* resolveFunctionSymbol(const SemaNodeView& nodeView)
    {
        const Symbol* sym = nodeView.sym;
        if (!sym && !nodeView.symList.empty())
            sym = nodeView.symList.front();

        if (!sym || !sym->isFunction())
            return nullptr;

        return &sym->cast<SymbolFunction>();
    }

    bool isInterfaceMethod(const SymbolFunction& methodSym)
    {
        const SymbolMap* ownerSymMap = methodSym.ownerSymMap();
        if (!ownerSymMap)
            return false;
        return ownerSymMap->safeCast<SymbolInterface>() != nullptr;
    }
}

Result AstCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* calleePayload = codeGen.payload(nodeExprRef);
    if (!calleePayload || calleePayload->kind != CodeGenNodePayloadKind::ExternalFunctionAddress)
        return Result::Continue;

    std::span<const MicroABICallArg> callArgs{};

    const auto& calleeNode = codeGen.ast().node(nodeExprRef);
    if (calleeNode.id() == AstNodeId::MemberAccessExpr)
    {
        const SemaNodeView callView(codeGen.sema(), codeGen.visit().currentNodeRef());
        const SymbolFunction* calledFunction = resolveFunctionSymbol(callView);

        const AstMemberAccessExpr* memberAccessExpr = calleeNode.cast<AstMemberAccessExpr>();
        if (!calledFunction)
        {
            const SemaNodeView rightView(codeGen.sema(), memberAccessExpr->nodeRightRef);
            calledFunction = resolveFunctionSymbol(rightView);
        }

        if (calledFunction && isInterfaceMethod(*calledFunction))
        {
            const auto* leftPayload = codeGen.payload(memberAccessExpr->nodeLeftRef);
            if (leftPayload && leftPayload->kind == CodeGenNodePayloadKind::AddressValue)
            {
                const auto* runtimeInterface = reinterpret_cast<const Runtime::Interface*>(leftPayload->valueU64);
                SWC_ASSERT(runtimeInterface != nullptr);
                SWC_ASSERT(runtimeInterface->obj != nullptr);
                auto* callArgStorage = codeGen.ctx().compiler().allocate<MicroABICallArg>();
                *callArgStorage      = {
                    .value   = reinterpret_cast<uint64_t>(runtimeInterface->obj),
                    .isFloat = false,
                    .numBits = 64,
                };
                callArgs = std::span<const MicroABICallArg>(callArgStorage, 1);
            }
        }
    }

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
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

    emitMicroABICallByAddress(codeGen.builder(), CallConvKind::Host, calleePayload->valueU64, callArgs, ret);

    const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::PointerStorageU64, reinterpret_cast<uint64_t>(resultStorage), nodeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
