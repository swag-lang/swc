#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
        {
            SmallVector<AstNodeRef> children;
            codeGen.ast().appendNodes(children, spanChildrenRef);
            SWC_ASSERT(!children.empty());

            const AstNodeRef exprRef     = children[0];
            const auto*      exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
            const auto       exprView    = codeGen.nodeView(exprRef);
            auto&            payload     = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
            auto&            builder     = codeGen.builder();

            if (exprView.type && (exprView.type->isString() || exprView.type->isSlice() || exprView.type->isAny()))
            {
                builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
            }
            else if (exprView.type && exprView.type->isArray())
            {
                builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
            }
            else if (exprPayload->storageKind == CodeGenNodePayload::StorageKind::Address)
            {
                builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
            }
            else
            {
                builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
            }

            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
            return Result::Continue;
        }

        default:
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
