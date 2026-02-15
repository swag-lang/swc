#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicCallExpr::codeGenPostNode(CodeGen& codeGen) const
{
    const Token& tok = codeGen.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicCompiler:
        {
            const auto  compilerIfAddress = reinterpret_cast<uint64_t>(&codeGen.ctx().compiler().runtimeCompiler());
            const auto  nodeView          = codeGen.curNodeView();
            const auto& payload           = codeGen.setPayload(codeGen.curNodeRef(), nodeView.typeRef);
            codeGen.builder().encodeLoadRegImm(CodeGen::payloadVirtualReg(payload), compilerIfAddress, MicroOpBits::B64, EncodeFlagsE::Zero);
            return Result::Continue;
        }

        default:
            SWC_ASSERT(false); // TODO: replace assert with a proper codegen diagnostic.
            return Result::Error;
    }
}

SWC_END_NAMESPACE();
