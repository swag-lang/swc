#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.sema().token(codeRef());
    if (tok.id != TokenId::KwdDRef)
        return Result::Continue;

    const auto* childPayload = codeGen.payload(nodeExprRef);
    if (!childPayload || childPayload->kind != CodeGenNodePayloadKind::PointerStorageU64)
        return Result::Continue;

    const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
    codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::DerefPointerStorageU64, childPayload->valueU64, nodeView.typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
