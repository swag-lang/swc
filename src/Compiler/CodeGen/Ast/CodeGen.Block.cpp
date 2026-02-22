#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    MicroOpBits conditionOpBits(const TypeInfo* typeInfo, TaskContext& ctx)
    {
        if (!typeInfo)
            return MicroOpBits::B64;

        switch (typeInfo->sizeOf(ctx))
        {
            case 1:
                return MicroOpBits::B8;
            case 2:
                return MicroOpBits::B16;
            case 4:
                return MicroOpBits::B32;
            case 8:
                return MicroOpBits::B64;
            default:
                return MicroOpBits::B64;
        }
    }

}

Result AstParenExpr::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeExprRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstNamedArgument::codeGenPostNode(CodeGen& codeGen) const
{
    codeGen.inheritPayload(codeGen.curNodeRef(), nodeArgRef, codeGen.curViewType().typeRef());
    return Result::Continue;
}

Result AstIfStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    MicroBuilder&    builder = codeGen.builder();
    const AstNodeRef ifRef   = codeGen.curNodeRef();

    if (childRef == nodeConditionRef)
    {
        const CodeGenNodePayload* conditionPayload = SWC_CHECK_NOT_NULL(codeGen.payload(nodeConditionRef));
        const SemaNodeView        conditionView    = codeGen.viewType(nodeConditionRef);
        const MicroOpBits         condBits         = conditionOpBits(conditionView.type(), codeGen.ctx());
        const MicroReg            condReg          = codeGen.nextVirtualIntRegister();

        if (conditionPayload->isAddress())
            builder.emitLoadRegMem(condReg, conditionPayload->reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, conditionPayload->reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(uint64_t{0}, 64), condBits);

        CodeGen::IfStmtCodeGenState state;
        state.falseLabel   = builder.createLabel();
        state.doneLabel    = builder.createLabel();
        state.hasElseBlock = nodeElseBlockRef.isValid();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);
        codeGen.setIfStmtCodeGenState(ifRef, state);

        return Result::Continue;
    }

    const CodeGen::IfStmtCodeGenState* state = codeGen.ifStmtCodeGenState(ifRef);
    SWC_ASSERT(state != nullptr);
    if (!state)
        return Result::Continue;

    if (childRef == nodeIfBlockRef)
    {
        if (state->hasElseBlock)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);

        builder.placeLabel(state->falseLabel);

        if (!state->hasElseBlock)
            codeGen.eraseIfStmtCodeGenState(ifRef);

        return Result::Continue;
    }

    if (childRef == nodeElseBlockRef)
    {
        builder.placeLabel(state->doneLabel);
        codeGen.eraseIfStmtCodeGenState(ifRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
