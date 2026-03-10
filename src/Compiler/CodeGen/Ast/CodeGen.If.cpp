#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfStmtCodeGenPayload
    {
        MicroLabelRef falseLabel   = MicroLabelRef::invalid();
        MicroLabelRef doneLabel    = MicroLabelRef::invalid();
        bool          hasElseBlock = false;
    };

    AstNodeRef resolvedNodeRef(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.viewZero(nodeRef).nodeRef();
    }

    IfStmtCodeGenPayload* ifStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        if (nodeRef.isInvalid())
            return nullptr;
        return codeGen.sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
    }

    IfStmtCodeGenPayload& setIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const IfStmtCodeGenPayload& payloadValue)
    {
        nodeRef = resolvedNodeRef(codeGen, nodeRef);
        SWC_ASSERT(nodeRef.isValid());

        auto* payload = codeGen.sema().codeGenPayload<IfStmtCodeGenPayload>(nodeRef);
        if (!payload)
        {
            payload = codeGen.compiler().allocate<IfStmtCodeGenPayload>();
            codeGen.sema().setCodeGenPayload(nodeRef, payload);
        }

        *payload = payloadValue;
        return *payload;
    }

    void eraseIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        IfStmtCodeGenPayload* payload = ifStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    MicroOpBits conditionOpBits(const TypeInfo& typeInfo, TaskContext& ctx)
    {
        switch (typeInfo.sizeOf(ctx))
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

Result AstIfStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    MicroBuilder&    builder              = codeGen.builder();
    const AstNodeRef ifRef                = codeGen.curNodeRef();
    const AstNodeRef resolvedConditionRef = resolvedNodeRef(codeGen, nodeConditionRef);
    const AstNodeRef resolvedIfBlockRef   = resolvedNodeRef(codeGen, nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = resolvedNodeRef(codeGen, nodeElseBlockRef);
    const AstNodeRef resolvedChildRef     = resolvedNodeRef(codeGen, childRef);

    if (resolvedConditionRef.isValid() && resolvedChildRef == resolvedConditionRef)
    {
        const CodeGenNodePayload& conditionPayload = codeGen.payload(nodeConditionRef);
        const SemaNodeView        conditionView    = codeGen.viewType(nodeConditionRef);
        SWC_ASSERT(conditionView.type() != nullptr);
        const MicroOpBits condBits = conditionOpBits(*conditionView.type(), codeGen.ctx());
        const MicroReg    condReg  = codeGen.nextVirtualIntRegister();

        if (conditionPayload.isAddress())
            builder.emitLoadRegMem(condReg, conditionPayload.reg, 0, condBits);
        else
            builder.emitLoadRegReg(condReg, conditionPayload.reg, condBits);

        builder.emitCmpRegImm(condReg, ApInt(0, 64), condBits);

        IfStmtCodeGenPayload state;
        state.falseLabel   = builder.createLabel();
        state.doneLabel    = builder.createLabel();
        state.hasElseBlock = resolvedElseBlockRef.isValid();
        builder.emitJumpToLabel(MicroCond::Equal, MicroOpBits::B32, state.falseLabel);
        setIfStmtCodeGenPayload(codeGen, ifRef, state);

        return Result::Continue;
    }

    const bool isIfBlockChild   = resolvedIfBlockRef.isValid() && resolvedChildRef == resolvedIfBlockRef;
    const bool isElseBlockChild = resolvedElseBlockRef.isValid() && resolvedChildRef == resolvedElseBlockRef;
    if (!isIfBlockChild && !isElseBlockChild)
        return Result::Continue;

    const IfStmtCodeGenPayload* state = ifStmtCodeGenPayload(codeGen, ifRef);
    SWC_ASSERT(state != nullptr);

    if (isIfBlockChild)
    {
        if (state->hasElseBlock)
            builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);

        builder.placeLabel(state->falseLabel);

        if (!state->hasElseBlock)
            eraseIfStmtCodeGenPayload(codeGen, ifRef);

        return Result::Continue;
    }

    if (isElseBlockChild)
    {
        builder.placeLabel(state->doneLabel);
        eraseIfStmtCodeGenPayload(codeGen, ifRef);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
