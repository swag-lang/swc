#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstMemberAccessExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const auto* leftPayload = codeGen.payload(nodeLeftRef);
    if (!leftPayload || leftPayload->kind != CodeGenNodePayloadKind::AddressValue)
        return Result::Continue;

    const SemaNodeView rightView(codeGen.sema(), nodeRightRef);

    const Symbol* methodSym = rightView.sym;
    if (!methodSym && !rightView.symList.empty())
        methodSym = rightView.symList.front();
    if (!methodSym || !methodSym->isFunction())
        return Result::Continue;

    if (methodSym->name(codeGen.ctx()) != "getBuildCfg")
        return Result::Continue;

    auto& runtimeCompiler = codeGen.ctx().compiler().runtimeCompiler();
    SWC_ASSERT(runtimeCompiler.itable != nullptr);
    const auto targetAddress = reinterpret_cast<uint64_t>(runtimeCompiler.itable[1]);
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::ExternalFunctionAddress, targetAddress);
    return Result::Continue;
}

SWC_END_NAMESPACE();
