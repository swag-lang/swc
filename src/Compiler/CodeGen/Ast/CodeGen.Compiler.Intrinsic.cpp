#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.sema().token(codeRef());
    if (tok.id != TokenId::IntrinsicCompiler)
        return Result::Continue;

    const auto compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.ctx().compiler().runtimeCompiler());
    const auto nodeView          = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::AddressValue, compilerIfAddress, nodeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
