#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenUnaryDeref(CodeGen& codeGen, AstNodeRef nodeExprRef)
    {
        MicroInstrBuilder& builder      = codeGen.builder();
        const auto*        childPayload = codeGen.payload(nodeExprRef);
        SWC_ASSERT(childPayload != nullptr);

        const auto  nodeView = codeGen.curNodeView();
        const auto& payload  = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
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

