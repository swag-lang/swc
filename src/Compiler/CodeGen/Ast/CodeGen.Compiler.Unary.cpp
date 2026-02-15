#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenUnaryDeref(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        const auto* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);
        if (childPayload->kind != CodeGenNodePayloadKind::PointerStorageU64)
            SWC_INTERNAL_ERROR();

        const auto nodeView = SemaNodeView(codeGen.sema(), codeGen.visit().currentNodeRef());
        codeGen.setPayload(codeGen.visit().currentNodeRef(), CodeGenNodePayloadKind::DerefPointerStorageU64, childPayload->valueU64, nodeView.typeRef);
        return Result::Continue;
    }
}

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.sema().token(codeRef());
    switch (tok.id)
    {
        case TokenId::KwdDRef:
            return codeGenUnaryDeref(codeGen, nodeExprRef);

        default:
            SWC_INTERNAL_ERROR();
    }
}

SWC_END_NAMESPACE();
