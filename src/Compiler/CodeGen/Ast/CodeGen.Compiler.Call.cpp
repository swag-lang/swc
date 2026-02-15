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
    SWC_ASSERT(calleePayload != nullptr);
    SWC_ASSERT(calleePayload->kind == CodeGenNodePayloadKind::ExternalFunctionAddress); // TODO: replace assert with a proper codegen diagnostic.

    std::span<const MicroABICallArg> callArgs{};

    const auto& calleeNode = codeGen.node(nodeExprRef);
    SWC_ASSERT(calleeNode.id() == AstNodeId::MemberAccessExpr); // TODO: replace assert with a proper codegen diagnostic.

    const auto callView = codeGen.curNodeView();
    const SymbolFunction* calledFunction = resolveFunctionSymbol(callView);

    const AstMemberAccessExpr* memberAccessExpr = calleeNode.cast<AstMemberAccessExpr>();
    if (!calledFunction)
    {
        const auto rightView = codeGen.nodeView(memberAccessExpr->nodeRightRef);
        calledFunction = resolveFunctionSymbol(rightView);
    }

    SWC_ASSERT(calledFunction != nullptr);
    SWC_ASSERT(isInterfaceMethod(*calledFunction)); // TODO: replace assert with a proper codegen diagnostic.

    const auto* leftPayload = codeGen.payload(memberAccessExpr->nodeLeftRef);
    SWC_ASSERT(leftPayload != nullptr);
    SWC_ASSERT(leftPayload->kind == CodeGenNodePayloadKind::AddressValue); // TODO: replace assert with a proper codegen diagnostic.

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

    SmallVector<AstNodeRef> args;
    collectArguments(args, codeGen.ast());
    SWC_ASSERT(args.empty()); // TODO: replace assert with a proper codegen diagnostic.

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

    const auto nodeView = codeGen.curNodeView();
    codeGen.setPayload(codeGen.curNodeRef(), CodeGenNodePayloadKind::PointerStorageU64, reinterpret_cast<uint64_t>(resultStorage), nodeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
