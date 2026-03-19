#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/CodeGen/Core/CodeGenMemoryHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isActiveCompilerRunRoot(CodeGen& codeGen)
    {
        const AstNodeRef currentDeclRef = codeGen.viewZero(codeGen.curNodeRef()).nodeRef();
        const AstNodeRef activeDeclRef  = codeGen.viewZero(codeGen.function().declNodeRef()).nodeRef();
        return currentDeclRef.isValid() && currentDeclRef == activeDeclRef;
    }

    struct CompilerScopeCodeGenPayload
    {
        MicroLabelRef continueLabel = MicroLabelRef::invalid();
        MicroLabelRef doneLabel     = MicroLabelRef::invalid();
    };

    CompilerScopeCodeGenPayload* compilerScopeCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        return codeGen.safeNodePayload<CompilerScopeCodeGenPayload>(nodeRef);
    }

    CompilerScopeCodeGenPayload& setCompilerScopeCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef, const CompilerScopeCodeGenPayload& payloadValue)
    {
        return codeGen.setNodePayload(nodeRef, payloadValue);
    }

    void eraseCompilerScopeCodeGenPayload(CodeGen& codeGen, AstNodeRef nodeRef)
    {
        CompilerScopeCodeGenPayload* payload = compilerScopeCodeGenPayload(codeGen, nodeRef);
        if (payload)
            *payload = {};
    }

    AstNodeRef findNamedCompilerScope(CodeGen& codeGen, std::string_view scopeName)
    {
        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = codeGen.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return AstNodeRef::invalid();

            const AstNode& parentNode = codeGen.ast().node(parentRef);
            if (parentNode.isNot(AstNodeId::CompilerScope))
                continue;

            const auto& scopeNode = parentNode.cast<AstCompilerScope>();
            if (scopeNode.tokNameRef.isInvalid())
                continue;

            const Token& scopeTok = codeGen.token({scopeNode.srcViewRef(), scopeNode.tokNameRef});
            if (scopeTok.string(codeGen.ast().srcView()) == scopeName)
                return parentRef;
        }
    }

    void buildCompilerFunctionStackLayout(CodeGen& codeGen)
    {
        const std::vector<SymbolVariable*>& localSymbols = codeGen.function().localVariables();
        if (localSymbols.empty())
            return;

        const CallConv& callConv  = CallConv::get(codeGen.function().callConvKind());
        uint64_t        frameSize = 0;
        // Sema already fixed the per-local offsets. Codegen only turns that sparse layout into one
        // contiguous stack frame and marks each symbol as stack-backed.
        for (SymbolVariable* symVar : localSymbols)
        {
            SWC_ASSERT(symVar != nullptr);
            const TypeRef typeRef = symVar->typeRef();
            SWC_ASSERT(typeRef.isValid());

            if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, *symVar))
            {
                symVar->setCodeGenLocalSize(0);
                continue;
            }

            const TypeInfo& typeInfo = codeGen.typeMgr().get(typeRef);
            const auto      size     = static_cast<uint32_t>(typeInfo.sizeOf(codeGen.ctx()));
            if (!size)
                continue;

            const uint32_t symOffset = symVar->offset();
            symVar->setCodeGenLocalSize(size);
            symVar->addExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack);
            frameSize = std::max<uint64_t>(frameSize, symOffset + size);
        }

        const uint32_t stackAlignment = callConv.stackAlignment ? callConv.stackAlignment : 16;
        frameSize                     = Math::alignUpU64(frameSize, stackAlignment);
        SWC_ASSERT(frameSize <= std::numeric_limits<uint32_t>::max());
        codeGen.setLocalStackFrameSize(static_cast<uint32_t>(frameSize));
    }

    void emitCompilerFunctionStackPrologue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv  = CallConv::get(callConvKind);
        MicroBuilder&   builder   = codeGen.builder();
        const uint32_t  frameSize = codeGen.localStackFrameSize();
        SWC_ASSERT(frameSize != 0);
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(frameSize, 64), MicroOp::Subtract, MicroOpBits::B64);

        const MicroReg frameBaseReg = callConv.preferredLocalStackBaseReg();
        SWC_ASSERT(frameBaseReg.isValid());
        builder.emitLoadRegReg(frameBaseReg, callConv.stackPointer, MicroOpBits::B64);
        codeGen.setLocalStackBaseReg(frameBaseReg);
        codeGen.function().setDebugStackFrameSize(frameSize);
        codeGen.function().setDebugStackBaseReg(frameBaseReg);
    }

    void emitCompilerFunctionStackEpilogue(CodeGen& codeGen, CallConvKind callConvKind)
    {
        if (!codeGen.hasLocalStackFrame())
            return;

        const CallConv& callConv = CallConv::get(callConvKind);
        MicroBuilder&   builder  = codeGen.builder();
        builder.emitOpBinaryRegImm(callConv.stackPointer, ApInt(codeGen.localStackFrameSize(), 64), MicroOp::Add, MicroOpBits::B64);
    }

    bool canUseDirectCallReturnWriteBack(const AstNode& exprNode, const CodeGenNodePayload& payload, const ABITypeNormalize::NormalizedType& normalizedRet)
    {
        if (normalizedRet.isVoid || normalizedRet.isIndirect)
            return false;

        if (exprNode.isNot(AstNodeId::CallExpr))
            return false;

        return payload.isValue();
    }
}

Result AstCompilerFunc::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::SkipChildren;

    if (childRef != nodeBodyRef)
        return Result::SkipChildren;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    buildCompilerFunctionStackLayout(codeGen);
    emitCompilerFunctionStackPrologue(codeGen, callConvKind);
    return Result::Continue;
}

Result AstCompilerFunc::codeGenPostNode(CodeGen& codeGen)
{
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::Continue;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    MicroBuilder&      builder      = codeGen.builder();
    emitCompilerFunctionStackEpilogue(codeGen, callConvKind);
    builder.emitRet();
    return Result::Continue;
}

Result AstCompilerRunBlock::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::SkipChildren;

    if (childRef != nodeBodyRef)
        return Result::SkipChildren;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    SWC_ASSERT(!callConv.intArgRegs.empty());

    MicroBuilder&  builder          = codeGen.builder();
    const MicroReg outputStorageReg = codeGen.nextVirtualIntRegister();
    builder.emitLoadRegReg(outputStorageReg, callConv.intArgRegs[0], MicroOpBits::B64);
    codeGen.setCurrentFunctionIndirectReturnReg(outputStorageReg);

    buildCompilerFunctionStackLayout(codeGen);
    emitCompilerFunctionStackPrologue(codeGen, callConvKind);
    return Result::Continue;
}

Result AstCompilerRunBlock::codeGenPostNode(CodeGen& codeGen)
{
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::Continue;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    MicroBuilder&      builder      = codeGen.builder();
    emitCompilerFunctionStackEpilogue(codeGen, callConvKind);
    builder.emitRet();
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPreNode(CodeGen& codeGen)
{
    if (codeGen.curViewConstant().hasConstant())
        return Result::Continue;
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::SkipChildren;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    SWC_ASSERT(!callConv.intArgRegs.empty());

    // Compiler-run entry points receive the caller output buffer in the first integer argument.
    const MicroReg            outputStorageReg = callConv.intArgRegs[0];
    const CodeGenNodePayload& nodePayload      = codeGen.setPayloadAddress(codeGen.curNodeRef());
    MicroBuilder&             builder          = codeGen.builder();
    builder.emitLoadRegReg(nodePayload.reg, outputStorageReg, MicroOpBits::B64);
    return Result::Continue;
}

Result AstCompilerIf::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
        return Result::Continue;

    const SemaNodeView condView = codeGen.viewConstant(nodeConditionRef);
    SWC_ASSERT(condView.cst());

    if (childRef == nodeIfBlockRef && !condView.cst()->getBool())
        return Result::SkipChildren;
    if (childRef == nodeElseBlockRef && condView.cst()->getBool())
        return Result::SkipChildren;

    return Result::Continue;
}

Result AstCompilerScope::codeGenPreNode(CodeGen& codeGen)
{
    MicroBuilder&               builder = codeGen.builder();
    CompilerScopeCodeGenPayload scopeState;
    scopeState.continueLabel = builder.createLabel();
    scopeState.doneLabel     = builder.createLabel();
    setCompilerScopeCodeGenPayload(codeGen, codeGen.curNodeRef(), scopeState);
    return Result::Continue;
}

Result AstCompilerScope::codeGenPreNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    const CompilerScopeCodeGenPayload* scopeState = compilerScopeCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(scopeState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(scopeState->continueLabel);

    CodeGenFrame frame = codeGen.frame();
    frame.setCurrentBreakContent(codeGen.curNodeRef(), CodeGenFrame::BreakContextKind::Scope);
    frame.setCurrentLoopContinueLabel(scopeState->continueLabel);
    frame.setCurrentLoopBreakLabel(scopeState->doneLabel);
    codeGen.pushFrame(frame);
    return Result::Continue;
}

Result AstCompilerScope::codeGenPostNodeChild(CodeGen& codeGen, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    codeGen.popFrame();
    return Result::Continue;
}

Result AstCompilerScope::codeGenPostNode(CodeGen& codeGen)
{
    const CompilerScopeCodeGenPayload* scopeState = compilerScopeCodeGenPayload(codeGen, codeGen.curNodeRef());
    SWC_ASSERT(scopeState != nullptr);

    MicroBuilder& builder = codeGen.builder();
    builder.placeLabel(scopeState->doneLabel);
    eraseCompilerScopeCodeGenPayload(codeGen, codeGen.curNodeRef());
    return Result::Continue;
}

Result AstScopedBreakStmt::codeGenPostNode(CodeGen& codeGen)
{
    const auto&      node         = codeGen.curNode().cast<AstScopedBreakStmt>();
    const Token&     tokScopeName = codeGen.token({node.srcViewRef(), node.tokNameRef});
    const AstNodeRef scopeRef     = findNamedCompilerScope(codeGen, tokScopeName.string(codeGen.ast().srcView()));
    SWC_ASSERT(scopeRef.isValid());
    if (scopeRef.isInvalid())
        return Result::Continue;

    const CompilerScopeCodeGenPayload* scopeState = compilerScopeCodeGenPayload(codeGen, scopeRef);
    SWC_ASSERT(scopeState != nullptr);
    if (!scopeState)
        return Result::Continue;

    MicroBuilder& builder = codeGen.builder();
    builder.emitJumpToLabel(MicroCond::Unconditional, MicroOpBits::B32, scopeState->doneLabel);
    return Result::Continue;
}

Result AstCompilerRunExpr::codeGenPostNode(CodeGen& codeGen) const
{
    if (!isActiveCompilerRunRoot(codeGen))
        return Result::Continue;

    const CallConvKind callConvKind = codeGen.function().callConvKind();
    const CallConv&    callConv     = CallConv::get(callConvKind);
    MicroBuilder&      builder      = codeGen.builder();
    const SemaNodeView exprView     = codeGen.viewType(nodeExprRef);
    SWC_ASSERT(exprView.type());

    const CodeGenNodePayload&              exprPayload      = codeGen.payload(nodeExprRef);
    const MicroReg                         payloadReg       = exprPayload.reg;
    const bool                             payloadLValue    = exprPayload.isAddress();
    const CodeGenNodePayload&              runExprPayload   = codeGen.payload(codeGen.curNodeRef());
    const MicroReg                         outputStorageReg = runExprPayload.reg;
    const AstNode&                         exprNode         = codeGen.node(nodeExprRef);
    const ABITypeNormalize::NormalizedType normalizedRet    = ABITypeNormalize::normalize(codeGen.ctx(), callConv, exprView.typeRef(), ABITypeNormalize::Usage::Return);

    if (normalizedRet.isIndirect)
    {
        SWC_ASSERT(normalizedRet.indirectSize != 0);
        if (CodeGenFunctionHelpers::needsPersistentCompilerRunReturn(codeGen.sema(), exprView.typeRef()))
            CodeGenFunctionHelpers::emitPersistCompilerRunValue(codeGen, exprView.typeRef(), outputStorageReg, payloadReg, codeGen.localStackBaseReg(), codeGen.localStackFrameSize());
        else
            CodeGenMemoryHelpers::emitMemCopy(codeGen, outputStorageReg, payloadReg, normalizedRet.indirectSize);
    }
    else
    {
        // A direct call expression may still own the ABI return registers, so write them back without
        // round-tripping through a freshly materialized virtual value.
        if (canUseDirectCallReturnWriteBack(exprNode, exprPayload, normalizedRet))
            ABICall::storeReturnRegsToReturnBuffer(builder, callConvKind, outputStorageReg, normalizedRet);
        else
            ABICall::storeValueToReturnBuffer(builder, callConvKind, outputStorageReg, payloadReg, payloadLValue, normalizedRet);
    }
    builder.emitRet();
    return Result::Continue;
}

SWC_END_NAMESPACE();
