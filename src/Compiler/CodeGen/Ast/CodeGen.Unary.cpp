#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenUnaryDeref(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroBuilder&             builder      = codeGen.builder();
        const CodeGenNodePayload* childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const SemaNodeView        nodeView = codeGen.curNodeView();
        const CodeGenNodePayload& payload  = codeGen.setPayloadAddress(codeGen.curNodeRef(), nodeView.typeRef);
        builder.encodeLoadRegReg(payload.reg, childPayload->reg, MicroOpBits::B64);
        return Result::Continue;
    }
}

Result AstUnaryExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::KwdDRef:
            return codeGenUnaryDeref(codeGen, nodeExprRef);

        default:
            // TODO
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
