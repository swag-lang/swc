#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result codeGenDataOf(CodeGen& codeGen, const AstIntrinsicCall& node)
    {
        SmallVector<AstNodeRef> children;
        codeGen.ast().appendNodes(children, node.spanChildrenRef);
        SWC_ASSERT(!children.empty());

        const AstNodeRef          exprRef     = children[0];
        const CodeGenNodePayload* exprPayload = SWC_CHECK_NOT_NULL(codeGen.payload(exprRef));
        const SemaNodeView        exprView    = codeGen.nodeView(exprRef);
        CodeGenNodePayload&       payload     = codeGen.setPayload(codeGen.curNodeRef(), codeGen.curNodeView().typeRef);
        MicroBuilder&             builder     = codeGen.builder();

        if (exprView.type && (exprView.type->isString() || exprView.type->isSlice() || exprView.type->isAny()))
            builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
        else if (exprView.type && exprView.type->isArray())
            builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
        else if (exprPayload->storageKind == CodeGenNodePayload::StorageKind::Address)
            builder.encodeLoadRegMem(payload.reg, exprPayload->reg, 0, MicroOpBits::B64);
        else
            builder.encodeLoadRegReg(payload.reg, exprPayload->reg, MicroOpBits::B64);
        payload.storageKind = CodeGenNodePayload::StorageKind::Value;
        return Result::Continue;
    }
}

Result AstIntrinsicCall::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return codeGenDataOf(codeGen, *this);

        default:
            SWC_UNREACHABLE();
    }
}

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicCompiler:
        {
            const uint64_t      compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.compiler().runtimeCompiler());
            const SemaNodeView  nodeView          = codeGen.curNodeView();
            CodeGenNodePayload& payload           = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
            codeGen.builder().encodeLoadRegPtrImm(payload.reg, compilerIfAddress);
            payload.storageKind = CodeGenNodePayload::StorageKind::Value;
            return Result::Continue;
        }

        default:
            // TODO
            SWC_UNREACHABLE();
    }
}

SWC_END_NAMESPACE();
