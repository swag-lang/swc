#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenCompareHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct IfStmtCodeGenPayload
    {
        MicroLabelRef falseLabel   = MicroLabelRef::invalid();
        MicroLabelRef doneLabel    = MicroLabelRef::invalid();
        bool          hasElseBlock = false;
    };

    IfStmtCodeGenPayload* ifStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<IfStmtCodeGenPayload>(nodeRef);
    }

    IfStmtCodeGenPayload& setIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const IfStmtCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseIfStmtCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        IfStmtCodeGenPayload* payload = ifStmtCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    void emitIfStmtCondition(CodeGen& codeGen, AstNodeRef ifRef, const CodeGenNodePayload& conditionPayload, TypeRef conditionTypeRef, bool hasElseBlock)
    {
        MicroBuilder&        builder = codeGen.builder();
        IfStmtCodeGenPayload state;
        state.falseLabel   = builder.createLabel();
        state.doneLabel    = builder.createLabel();
        state.hasElseBlock = hasElseBlock;
        CodeGenCompareHelpers::emitConditionFalseJump(codeGen, conditionPayload, conditionTypeRef, state.falseLabel);

        // The branch bodies are emitted in later child callbacks, so keep their labels attached to the
        // `if` node until those callbacks run.
        setIfStmtCodeGenPayload(codeGen, ifRef, state);
    }

    const SymbolVariable& ifVarDeclConditionSymbol(CodeGen& codeGen, AstNodeRef varDeclRef)
    {
        SmallVector<Symbol*> symbols;
        codeGen.viewSymbol(varDeclRef).getSymbols(symbols);
        SWC_ASSERT(symbols.size() == 1);
        SWC_ASSERT(symbols.front()->isVariable());
        return symbols.front()->cast<SymbolVariable>();
    }

    Result codeGenIfStmtPostBlockChild(CodeGen& codeGen, AstNodeRef ifRef, AstNodeRef ifBlockRef, AstNodeRef elseBlockRef, AstNodeRef childRef)
    {
        const bool isIfBlockChild   = ifBlockRef.isValid() && childRef == ifBlockRef;
        const bool isElseBlockChild = elseBlockRef.isValid() && childRef == elseBlockRef;
        if (!isIfBlockChild && !isElseBlockChild)
            return Result::Continue;

        const IfStmtCodeGenPayload* state = ifStmtCodeGenPayload(codeGen, ifRef);
        SWC_ASSERT(state != nullptr);

        MicroBuilder& builder = codeGen.builder();
        if (isIfBlockChild)
        {
            if (state->hasElseBlock)
                builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, state->doneLabel);

            // Falling out of the `if` body either starts the `else` body or lands directly after the statement.
            builder.placeLabel(state->falseLabel);

            if (!state->hasElseBlock)
                eraseIfStmtCodeGenPayload(codeGen, ifRef);

            return Result::Continue;
        }

        builder.placeLabel(state->doneLabel);
        eraseIfStmtCodeGenPayload(codeGen, ifRef);
        return Result::Continue;
    }
}

Result AstIfStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef     = codeGen.resolvedNodeRef(childRef);
    const AstNodeRef resolvedIfBlockRef   = codeGen.resolvedNodeRef(nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = codeGen.resolvedNodeRef(nodeElseBlockRef);
    if (resolvedChildRef == resolvedIfBlockRef || resolvedChildRef == resolvedElseBlockRef)
        codeGen.pushDeferScope();
    return Result::Continue;
}

Result AstIfStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef ifRef                = codeGen.curNodeRef();
    const AstNodeRef resolvedConditionRef = codeGen.resolvedNodeRef(nodeConditionRef);
    const AstNodeRef resolvedIfBlockRef   = codeGen.resolvedNodeRef(nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = codeGen.resolvedNodeRef(nodeElseBlockRef);
    const AstNodeRef resolvedChildRef     = codeGen.resolvedNodeRef(childRef);

    if (resolvedConditionRef.isValid() && resolvedChildRef == resolvedConditionRef)
    {
        const CodeGenNodePayload& conditionPayload = codeGen.payload(resolvedConditionRef);
        const SemaNodeView        conditionView    = codeGen.viewType(resolvedConditionRef);
        SWC_ASSERT(conditionView.type() != nullptr);
        emitIfStmtCondition(codeGen, ifRef, conditionPayload, conditionView.typeRef(), resolvedElseBlockRef.isValid());
        return Result::Continue;
    }

    if (resolvedChildRef == resolvedIfBlockRef || resolvedChildRef == resolvedElseBlockRef)
        SWC_RESULT(codeGen.popDeferScope());

    return codeGenIfStmtPostBlockChild(codeGen, ifRef, resolvedIfBlockRef, resolvedElseBlockRef, resolvedChildRef);
}

Result AstIfVarDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef resolvedChildRef     = codeGen.resolvedNodeRef(childRef);
    const AstNodeRef resolvedIfBlockRef   = codeGen.resolvedNodeRef(nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = codeGen.resolvedNodeRef(nodeElseBlockRef);
    if (resolvedChildRef == resolvedIfBlockRef || resolvedChildRef == resolvedElseBlockRef)
        codeGen.pushDeferScope();
    return Result::Continue;
}

Result AstIfVarDecl::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    const AstNodeRef ifRef                = codeGen.curNodeRef();
    const AstNodeRef resolvedVarRef       = codeGen.resolvedNodeRef(nodeVarRef);
    const AstNodeRef resolvedWhereRef     = codeGen.resolvedNodeRef(nodeWhereRef);
    const AstNodeRef resolvedIfBlockRef   = codeGen.resolvedNodeRef(nodeIfBlockRef);
    const AstNodeRef resolvedElseBlockRef = codeGen.resolvedNodeRef(nodeElseBlockRef);
    const AstNodeRef resolvedChildRef     = codeGen.resolvedNodeRef(childRef);

    if (resolvedWhereRef.isInvalid() && resolvedVarRef.isValid() && resolvedChildRef == resolvedVarRef)
    {
        SmallVector<Symbol*> symbols;
        codeGen.viewSymbol(resolvedVarRef).getSymbols(symbols);
        SWC_ASSERT(symbols.size() == 1);

        if (symbols.front()->isVariable())
        {
            const auto& symVar           = symbols.front()->cast<SymbolVariable>();
            const auto* conditionPayload = codeGen.variablePayload(symVar);
            SWC_ASSERT(conditionPayload != nullptr);
            emitIfStmtCondition(codeGen, ifRef, *conditionPayload, symVar.typeRef(), resolvedElseBlockRef.isValid());
        }
        else
        {
            // 'if const a = expr': the constant was already emitted by the walker.
            const CodeGenNodePayload& payload = codeGen.payload(resolvedVarRef);
            const SemaNodeView        view    = codeGen.viewType(resolvedVarRef);
            emitIfStmtCondition(codeGen, ifRef, payload, view.typeRef(), resolvedElseBlockRef.isValid());
        }

        return Result::Continue;
    }

    if (resolvedWhereRef.isValid() && resolvedChildRef == resolvedWhereRef)
    {
        const CodeGenNodePayload& wherePayload = codeGen.payload(resolvedWhereRef);
        const SemaNodeView        whereView    = codeGen.viewType(resolvedWhereRef);
        SWC_ASSERT(whereView.type() != nullptr);
        emitIfStmtCondition(codeGen, ifRef, wherePayload, whereView.typeRef(), resolvedElseBlockRef.isValid());
        return Result::Continue;
    }

    if (resolvedChildRef == resolvedIfBlockRef || resolvedChildRef == resolvedElseBlockRef)
        SWC_RESULT(codeGen.popDeferScope());

    return codeGenIfStmtPostBlockChild(codeGen, ifRef, resolvedIfBlockRef, resolvedElseBlockRef, resolvedChildRef);
}

Result AstWithStmt::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) == codeGen.resolvedNodeRef(nodeBodyRef))
        codeGen.pushDeferScope();
    return Result::Continue;
}

Result AstWithStmt::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) == codeGen.resolvedNodeRef(nodeBodyRef))
        return codeGen.popDeferScope();
    return Result::Continue;
}

Result AstWithVarDecl::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) == codeGen.resolvedNodeRef(nodeBodyRef))
        codeGen.pushDeferScope();
    return Result::Continue;
}

Result AstWithVarDecl::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (codeGen.resolvedNodeRef(childRef) == codeGen.resolvedNodeRef(nodeBodyRef))
        return codeGen.popDeferScope();
    return Result::Continue;
}

SWC_END_NAMESPACE();
