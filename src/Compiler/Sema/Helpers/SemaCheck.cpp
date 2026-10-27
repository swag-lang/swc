#include "pch.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaAccess.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Helpers/SemaVarDeclHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Trailing #code blocks are call arguments whose execution the callee
    // controls; they cannot end the enclosing statement block's local flow.
    bool stopsBlockFlow(Sema& sema, AstNodeRef blockRef, AstNodeRef childRef)
    {
        if (childRef.isInvalid() || sema.isImplicitCodeBlockArg(blockRef, childRef))
            return false;

        return SemaHelpers::stopsLocalFlow(sema, childRef, SemaHelpers::LocalFlowStop::Block);
    }

    // Inferred return types have no source node to highlight.
    AstNodeRef functionReturnTypeNodeRef(const AstNode* decl)
    {
        if (!decl)
            return AstNodeRef::invalid();

        switch (decl->id())
        {
            case AstNodeId::FunctionDecl:
                return decl->cast<AstFunctionDecl>().nodeReturnTypeRef;
            case AstNodeId::FunctionExpr:
                return decl->cast<AstFunctionExpr>().nodeReturnTypeRef;
            case AstNodeId::ClosureExpr:
                return decl->cast<AstClosureExpr>().nodeReturnTypeRef;
            default:
                return AstNodeRef::invalid();
        }
    }

    bool isConstAssignmentTargetImpl(Sema& sema, AstNodeRef leftExprRef);

    Diagnostic reportReadOnlyAssignment(Sema& sema, AstNodeRef leftExprRef)
    {
        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, leftExprRef);
        diag.removeArgument(Diagnostic::ARG_SYM);
        diag.removeArgument(Diagnostic::ARG_SYM_FAM);
        diag.removeArgument(Diagnostic::ARG_A_SYM_FAM);

        return diag;
    }

    bool isIgnoredValuePoison(Sema& sema, AstNodeRef nodeRef)
    {
        const SemaNodeView symbolView = sema.viewSymbol(nodeRef);
        return symbolView.hasSymbol() && symbolView.sym() && symbolView.sym()->isIgnored();
    }

    bool isInlineConstAssignmentTarget(const Sema& sema, AstNodeRef nodeRef)
    {
        return sema.isConstAssignTargetStored(nodeRef);
    }

    bool isInlineConstAssignmentBinding(const Sema& sema, AstNodeRef nodeRef)
    {
        return sema.isConstAssignBindingStored(nodeRef);
    }

    AstNodeRef resolveNodeRefForCheck(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        AstNodeRef resolvedNodeRef = sema.resolvedNodeRef(nodeRef);
        if (resolvedNodeRef.isInvalid())
            resolvedNodeRef = nodeRef;

        return resolvedNodeRef;
    }

    bool isConstTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isConst())
            return true;
        if (!type.isAlias())
            return false;

        const TypeInfo* unwrappedType = type.unwrapAliasType(sema.ctx());
        return unwrappedType && unwrappedType->isConst();
    }

    bool isNonReassignableFunctionParameter(Sema& sema, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
            return false;
        if (!symVar.typeRef().isValid())
            return true;

        return !sema.typeMgr().get(symVar.typeRef()).isReference();
    }

    bool isReadOnlyAggregateFunctionParameter(Sema& sema, const SymbolVariable& symVar)
    {
        if (!isNonReassignableFunctionParameter(sema, symVar))
            return false;
        if (!symVar.typeRef().isValid())
            return true;

        const TypeInfo& typeInfo = sema.typeMgr().get(symVar.typeRef());
        return !typeInfo.isPointerLike() && !typeInfo.isArray();
    }

    bool canResolveFunctionParameterIdentifier(const Sema& sema, const SourceCodeRef& codeRef)
    {
        if (!codeRef.isValid())
            return false;

        const SourceView& srcView = sema.srcView(codeRef.srcViewRef);
        if (codeRef.tokRef.get() >= srcView.tokens().size())
            return false;

        const Token& tok = srcView.token(codeRef.tokRef);
        if (tok.id != TokenId::Identifier)
            return false;
        if (tok.byteStart >= srcView.identifiers().size())
            return false;

        const uint32_t byteStart = srcView.identifiers()[tok.byteStart].byteStart;
        return byteStart + tok.byteLength <= srcView.stringView().size();
    }

    const SymbolVariable* inlineParameterByBinding(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        return sema.constAssignSourceParameter(nodeRef);
    }

    const SymbolVariable* inlineParameterByBindingPath(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const SymbolVariable* result = nullptr;
        Ast::visit(sema.ast(), nodeRef, [&](AstNodeRef childRef, const AstNode&) {
            result = inlineParameterByBinding(sema, childRef);
            return result ? Ast::VisitResult::Stop : Ast::VisitResult::Continue;
        });

        return result;
    }

    const SymbolVariable* parameterByIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;
        if (!sema.node(nodeRef).is(AstNodeId::Identifier))
            return nullptr;

        const SemaNodeView symbolView = sema.viewSymbol(nodeRef);
        if (sema.isCurrentFunction())
        {
            if (const Symbol* symbol = symbolView.sym())
            {
                if (symbol->isVariable())
                {
                    const auto& symVar = symbol->cast<SymbolVariable>();
                    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) && symVar.ownerSymMap() == sema.currentFunction())
                        return &symVar;
                    if (symVar.isClosureCapture())
                        return nullptr;
                }

                return inlineParameterByBinding(sema, nodeRef);
            }

            const SourceCodeRef codeRef = sema.node(nodeRef).codeRef();
            if (canResolveFunctionParameterIdentifier(sema, codeRef))
            {
                const IdentifierRef   idRef           = sema.idMgr().addIdentifier(sema.ctx(), codeRef);
                const SymbolFunction* currentFunction = sema.currentFunction();
                size_t                paramIndex      = 0;
                if (currentFunction->tryGetParameterIndexByName(paramIndex, idRef))
                    return currentFunction->parameters()[paramIndex];
            }
        }

        return inlineParameterByBinding(sema, nodeRef);
    }

    const SymbolVariable* nonReassignableParameterIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        const SymbolVariable* param = parameterByIdentifier(sema, nodeRef);
        return param && isNonReassignableFunctionParameter(sema, *param) ? param : nullptr;
    }

    const SymbolVariable* readOnlyAggregateParameterIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        const SymbolVariable* param = parameterByIdentifier(sema, nodeRef);
        return param && isReadOnlyAggregateFunctionParameter(sema, *param) ? param : nullptr;
    }

    bool isSyntheticAutoMemberLeft(const Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        return node.is(AstNodeId::Identifier) && node.codeRef().isValid() && sema.token(node.codeRef()).id == TokenId::SymDot;
    }

    const SymbolVariable* readOnlyAggregateParameterPath(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, nodeRef);
        if (resolvedRef.isInvalid())
            return nullptr;

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::Identifier))
            return readOnlyAggregateParameterIdentifier(sema, resolvedRef);

        if (node.is(AstNodeId::MemberAccessExpr))
        {
            const auto& member = node.cast<AstMemberAccessExpr>();
            return isSyntheticAutoMemberLeft(sema, member.nodeLeftRef) ? nullptr : readOnlyAggregateParameterPath(sema, member.nodeLeftRef);
        }

        if (node.is(AstNodeId::IndexExpr))
            return readOnlyAggregateParameterPath(sema, node.cast<AstIndexExpr>().nodeExprRef);
        if (node.is(AstNodeId::IndexListExpr))
            return readOnlyAggregateParameterPath(sema, node.cast<AstIndexListExpr>().nodeExprRef);

        return nullptr;
    }

    bool isConstSourceViewImpl(Sema& sema, const SemaNodeView& view)
    {
        if (isConstTypeRef(sema, view.typeRef()))
            return true;

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
        if (!sourceTypeRef.isValid())
            return false;

        const TypeInfo& sourceType = sema.typeMgr().get(sourceTypeRef);
        return sourceType.isAnyString();
    }

    AstNodeRef indexedSourceRef(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedNodeRef = resolveNodeRefForCheck(sema, nodeRef);
        if (resolvedNodeRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(resolvedNodeRef);
        if (node.is(AstNodeId::IndexExpr))
            return node.cast<AstIndexExpr>().nodeExprRef;
        if (node.is(AstNodeId::IndexListExpr))
            return node.cast<AstIndexListExpr>().nodeExprRef;

        return AstNodeRef::invalid();
    }

    // Selecting or indexing a pointer/slice writes its pointee, not the carrier.
    bool designatesPointee(Sema& sema, AstNodeRef baseRef)
    {
        const SemaNodeView view = sema.viewTypeSymbol(baseRef);
        if (!view.type())
            return false;

        const TypeRef typeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), view.typeRef());
        if (!typeRef.isValid())
            return false;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        return type.isAnyPointer() || type.isSlice();
    }

    bool isConstIndexedSource(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef sourceRef = indexedSourceRef(sema, nodeRef);
        if (sourceRef.isInvalid())
            return false;

        // Inline parameter bindings freeze their value, not its pointee.
        // Pointer/slice indexing is governed by the type's own const qualifier,
        // even when the pointer came from a by-value integer parameter.
        const SemaNodeView sourceView = sema.viewNodeTypeConstantSymbol(sourceRef);
        if (!designatesPointee(sema, sourceRef) && isConstAssignmentTargetImpl(sema, sourceRef))
            return true;
        if (!sourceView.type())
            return false;
        if (isConstSourceViewImpl(sema, sourceView))
            return true;

        const TypeRef sourceTypeRef = SemaHelpers::unwrapAliasRefType(sema.ctx(), sourceView.typeRef());
        if (!sourceTypeRef.isValid())
            return false;

        return sema.typeMgr().get(sourceTypeRef).isConst();
    }

    bool isDerefConstSource(Sema& sema, const AstUnaryExpr& node)
    {
        const Token& tok = sema.token(node.codeRef());
        if (!Token::isDeref(tok.id))
            return false;

        const SemaNodeView sourceView = sema.viewTypeSymbol(node.nodeExprRef);
        return isConstSourceViewImpl(sema, sourceView);
    }

    Result normalizeTypeInfoValueIfNeeded(Sema& sema, SemaNodeView& view)
    {
        if (!SemaHelpers::isTypeLikeTypeRef(sema.ctx(), view.typeRef()))
            return Result::Continue;

        bool        changed = false;
        ConstantRef cstRef  = view.cstRef();
        if (cstRef.isValid())
        {
            SWC_RESULT(SemaHelpers::normalizeTypeInfoConstantRef(sema, cstRef, view.nodeRef()));
            if (cstRef != view.cstRef())
            {
                sema.setConstant(view.nodeRef(), cstRef);
                changed = true;
            }
        }

        const TypeRef typeRef = SemaHelpers::normalizeTypeLikeValueTypeRef(sema, view.typeRef(), cstRef, view.nodeRef());
        if (typeRef.isValid() && typeRef != view.typeRef())
        {
            sema.setType(view.nodeRef(), typeRef);
            changed = true;
        }

        if (changed)
            view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

        return Result::Continue;
    }

    bool isConstAssignmentTargetImpl(Sema& sema, AstNodeRef leftExprRef)
    {
        if (isInlineConstAssignmentTarget(sema, leftExprRef))
            return true;

        const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, leftExprRef);
        if (resolvedRef.isInvalid())
            return false;

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::MemberAccessExpr))
        {
            const auto&        member     = node.cast<AstMemberAccessExpr>();
            const SemaNodeView sourceView = sema.viewNodeTypeConstantSymbol(member.nodeLeftRef);
            if (!isSyntheticAutoMemberLeft(sema, member.nodeLeftRef) && isConstSourceViewImpl(sema, sourceView))
                return true;

            return !designatesPointee(sema, member.nodeLeftRef) && isConstAssignmentTargetImpl(sema, member.nodeLeftRef);
        }

        if (node.is(AstNodeId::IndexExpr) || node.is(AstNodeId::IndexListExpr))
            return isConstIndexedSource(sema, resolvedRef);
        if (node.is(AstNodeId::UnaryExpr))
            return isDerefConstSource(sema, node.cast<AstUnaryExpr>());
        if (node.is(AstNodeId::ParenExpr))
            return isConstAssignmentTargetImpl(sema, node.cast<AstParenExpr>().nodeExprRef);

        return false;
    }

    TokenId tokenIdForModifierFlag(AstModifierFlagsE flag)
    {
        switch (flag)
        {
            case AstModifierFlagsE::Bit: return TokenId::ModifierBit;
            case AstModifierFlagsE::Try: return TokenId::KwdTry;
            case AstModifierFlagsE::Assume: return TokenId::KwdAssume;
            case AstModifierFlagsE::UnConst: return TokenId::ModifierUnConst;
            case AstModifierFlagsE::Fail: return TokenId::ModifierFail;
            case AstModifierFlagsE::NoFail: return TokenId::ModifierNoFail;
            case AstModifierFlagsE::Promote: return TokenId::ModifierPromote;
            case AstModifierFlagsE::Wrap: return TokenId::ModifierWrap;
            case AstModifierFlagsE::NoDrop: return TokenId::ModifierNoDrop;
            case AstModifierFlagsE::Complete: return TokenId::ModifierComplete;
            case AstModifierFlagsE::Move: return TokenId::ModifierMove;
            case AstModifierFlagsE::Relocate: return TokenId::ModifierRelocate;

            default:
                SWC_UNREACHABLE();
        }
    }

    void reportUnsupportedModifier(Sema& sema, const AstNode& node, AstModifierFlagsE flag)
    {
        const TokenId     tokId   = tokenIdForModifierFlag(flag);
        const SourceView& srcView = sema.compiler().srcView(node.srcViewRef());
        const TokenRef    mdfRef  = srcView.findRightFrom(node.tokRef(), {tokId});

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_modifier_unsupported, node.codeRef());
        diag.addArgument(Diagnostic::ARG_WHAT, Token::toName(tokId));

        // Generated modifier flags may have no source token to highlight.
        if (mdfRef.isValid())
            diag.last().addSpan(srcView.tokenCodeRange(sema.ctx(), mdfRef), "");

        diag.report(sema.ctx());
    }

    // Find global storage behind a target, or null for a non-global root.
    const SymbolVariable* assignedGlobalRoot(Sema& sema, AstNodeRef nodeRef)
    {
        while (true)
        {
            const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, nodeRef);
            if (resolvedRef.isInvalid())
                return nullptr;

            const AstNode& node = sema.node(resolvedRef);
            if (node.is(AstNodeId::ParenExpr))
            {
                nodeRef = node.cast<AstParenExpr>().nodeExprRef;
                continue;
            }

            if (node.is(AstNodeId::MemberAccessExpr))
            {
                nodeRef = node.cast<AstMemberAccessExpr>().nodeLeftRef;
                continue;
            }

            if (node.is(AstNodeId::IndexExpr))
            {
                nodeRef = node.cast<AstIndexExpr>().nodeExprRef;
                continue;
            }

            const Symbol* sym = sema.view(resolvedRef, SemaNodeViewPartE::Symbol).singleSymbol();
            if (!sym || !sym->isVariable())
                return nullptr;

            const auto& symVar = sym->cast<SymbolVariable>();
            return symVar.hasGlobalStorage() ? &symVar : nullptr;
        }
    }

    // Compile-time writes affect compiler data segments; only segments emitted
    // with their bytes preserve those values in the artifact.
    bool inCompileTimeExecutedFunction(const Sema& sema)
    {
        const SymbolFunction* symFn = sema.currentFunction();

        // Ordinary inlining retains the callee's storage contract. A runtime helper cloned
        // into #run must not move its globals after other callers already lowered them.
        // Macros and mixins expand in their caller's execution context instead.
        for (const auto* payload = SemaHelpers::effectiveInlinePayload(sema); payload; payload = payload->parentInlinePayload)
        {
            if (payload->sourceFunction && !payload->sourceFunction->attributes().hasMacroOrMixin())
            {
                symFn = payload->sourceFunction;
                break;
            }
        }

        if (!symFn)
            return false;

        // Compiler-attributed helpers can retain ordinary function declarations.
        // Checking only synthetic #run nodes would miss their global writes.
        if (symFn->attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return true;

        const AstNode* decl = symFn->decl();
        if (!decl)
            return false;

        if (decl->is(AstNodeId::CompilerRunBlock) || decl->is(AstNodeId::CompilerRunExpr))
            return true;
        if (!decl->is(AstNodeId::CompilerFunc))
            return false;

        const TokenId tokenId = sema.token(decl->codeRef()).id;
        return tokenId == TokenId::CompilerRun || tokenId == TokenId::CompilerAst || tokenId == TokenId::CompilerFuncMessage;
    }

    // GlobalZero becomes .bss, which emits no bytes and loses compile-time
    // writes. Promote written globals to initialized storage on demand.
    Result checkCompileTimeGlobalWrite(Sema& sema, AstNodeRef leftExprRef)
    {
        if (!inCompileTimeExecutedFunction(sema))
            return Result::Continue;

        SymbolVariable* symVar = const_cast<SymbolVariable*>(assignedGlobalRoot(sema, leftExprRef));
        if (!symVar || symVar->globalStorageKind() != DataSegmentKind::GlobalZero)
            return Result::Continue;

        const TypeInfo& type = sema.typeMgr().get(symVar->typeRef());
        const uint64_t  size = type.sizeOf(sema.ctx());
        if (!size)
            return Result::Continue;

        SWC_ASSERT(size <= std::numeric_limits<uint32_t>::max());

        const uint32_t alignment = std::max(1u, type.alignOf(sema.ctx()));
        const uint32_t offset    = sema.compiler().globalInitSegment().reserveBlock(static_cast<uint32_t>(size), alignment, true);
        symVar->setGlobalStorage(DataSegmentKind::GlobalInit, offset);

        return Result::Continue;
    }
}

Result SemaCheck::modifiers(Sema& sema, const AstNode& node, AstModifierFlags mods, AstModifierFlags allowed)
{
    AstModifierFlags unsupported = mods.maskInvert(allowed);

    // Flow analysis marks the first write after an elided default with FirstInit.
    // It has no source token, so later checks such as inline revisits must not
    // search for a spelling to report.
    unsupported.remove(AstModifierFlagsE::FirstInit);
    if (unsupported.none())
        return Result::Continue;

    unsupported.forEachSet([&](AstModifierFlagsE flag) { reportUnsupportedModifier(sema, node, flag); });

    return Result::Error;
}

Result SemaCheck::isValue(Sema& sema, AstNodeRef nodeRef)
{
    if (sema.isValue(nodeRef))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, nodeRef))
        return Result::Error;

    return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, nodeRef);
}

Result SemaCheck::noMoveRefType(Sema& sema, TypeRef typeRef, const SourceCodeRef& errorRef)
{
    if (!typeRef.isValid() || !sema.typeMgr().get(typeRef).isMoveReference())
        return Result::Continue;

    return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_move_ref_type_context, errorRef, typeRef);
}

Result SemaCheck::noCopyOfNonCopyable(Sema& sema, AstNodeRef srcRef, TypeRef srcTypeRef, TypeRef destTypeRef, AstModifierFlags modifierFlags, bool destReferenceBinds, bool forceCopy)
{
    SWC_RESULT(SemaSpecOp::addValueTransferCallDependencies(sema, srcRef, destTypeRef, modifierFlags, destReferenceBinds));

    // '#move'/'#relocate' transfer ownership: not a copy.
    if (modifierFlags.has(AstModifierFlagsE::Move) || modifierFlags.has(AstModifierFlagsE::Relocate))
        return Result::Continue;
    if (srcRef.isInvalid() || srcTypeRef.isInvalid() || destTypeRef.isInvalid())
        return Result::Continue;

    const TypeManager& typeMgr = sema.typeMgr();

    // Copy checks concern aggregate value destinations and writes through references.
    // Reference declarations bind; pointer destinations only store addresses.
    const TypeInfo* destType = &typeMgr.get(destTypeRef);
    if (destType->isReference())
    {
        if (destReferenceBinds)
            return Result::Continue;

        destType = &typeMgr.get(destType->payloadTypeRef());
    }

    if (const TypeInfo* unwrappedType = destType->unwrapAliasEnumType(sema.ctx()))
        destType = unwrappedType;

    if (!destType->isStructOrAggregateStruct() && !destType->isArray())
        return Result::Continue;

    // Rvalues construct or move. Copy checks apply when reading stored values,
    // including a #move parameter used without #move.
    const TypeInfo& srcType = typeMgr.get(srcTypeRef);
    if (!forceCopy && !srcType.isReference() && !SemaHelpers::expressionBorrowsStorage(sema, srcRef))
        return Result::Continue;

    // Overload resolution discards the #fwd copy variant for non-copyable types,
    // so copies from that parameter are dead code and must not report errors.
    const SemaNodeView srcSymView = sema.viewSymbol(srcRef);
    if (srcSymView.sym() && srcSymView.sym()->isVariable() && srcSymView.sym()->cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::FwdCopy))
        return Result::Continue;

    const TypeRef checkTypeRef = destType->typeRef();
    if (TypeGen::lifecycleFlagsOfTypeRef(sema.ctx(), checkTypeRef).canCopy)
        return Result::Continue;

    // Ownership and the explicit attribute deny the copy for different reasons, and their
    // repairs differ: an owning type opts the copy back in with 'opPostCopy'.
    const TypeRef owningTypeRef = TypeGen::copyDenialTypeRef(sema.ctx(), checkTypeRef, TypeGen::CopyDenial::OwningDrop);
    if (owningTypeRef.isValid())
    {
        auto owningDiag = SemaError::report(sema, DiagnosticId::sema_err_cannot_copy_owning, srcRef);
        owningDiag.addArgument(Diagnostic::ARG_TYPE, checkTypeRef);
        if (owningTypeRef != checkTypeRef)
            owningDiag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, owningTypeRef);

        owningDiag.report(sema.ctx());
        return Result::Error;
    }

    // Name the struct that refuses the copy: it can be a field of the copied type, and a signal
    // refuses for its own reason.
    const TypeRef   deniedTypeRef = TypeGen::copyDenialTypeRef(sema.ctx(), checkTypeRef, TypeGen::CopyDenial::NoCopy);
    const TypeInfo* deniedType    = deniedTypeRef.isValid() ? &typeMgr.get(deniedTypeRef) : nullptr;
    const bool      isSignal      = deniedType && deniedType->isStruct() && deniedType->payloadSymStruct().attributes().hasRtFlag(RtAttributeFlagsE::Signal);

    auto diag = SemaError::report(sema, isSignal ? DiagnosticId::sema_err_cannot_copy_signal : DiagnosticId::sema_err_cannot_copy_nocopy, srcRef);
    diag.addArgument(Diagnostic::ARG_TYPE, checkTypeRef);
    if (deniedTypeRef.isValid() && deniedTypeRef != checkTypeRef)
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, deniedTypeRef);
    diag.report(sema.ctx());

    return Result::Error;
}

Result SemaCheck::checkMoveSourceCanReset(Sema& sema, const AstNodeRef srcRef, TypeRef typeRef, const AstModifierFlags modifierFlags)
{
    if (srcRef.isValid() && typeRef.isValid() && modifierFlags.hasAny({AstModifierFlagsE::Move, AstModifierFlagsE::Relocate}))
        SWC_RESULT(SemaSpecOp::addValueTransferCallDependencies(sema, srcRef, typeRef, modifierFlags, true));

    if (!modifierFlags.has(AstModifierFlagsE::Move) || srcRef.isInvalid() || typeRef.isInvalid())
        return Result::Continue;

    typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);

    SWC_RESULT(SymbolStruct::waitTypeImplicitDefaultReady(sema, typeRef, srcRef));
    if (!TypeGen::lifecycleFlagsOfTypeRef(sema.ctx(), typeRef).hasDrop)
        return Result::Continue;
    if (!SymbolStruct::typeRequiresExplicitInitialization(sema, typeRef))
        return SemaSpecOp::addDefaultInitCallDependencies(sema, typeRef);

    return SemaError::raiseTypeArgumentError(sema, DiagnosticId::sema_err_move_source_no_default, sema.node(srcRef).codeRef(), typeRef);
}

Result SemaCheck::isValueOrType(Sema& sema, SemaNodeView& view)
{
    if (sema.isValue(view.nodeRef()))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, view.nodeRef()))
        return Result::Error;
    if (view.typeRef().isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), view.typeRef()));
    sema.setConstant(view.nodeRef(), cstRef);
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

    return Result::Continue;
}

Result SemaCheck::isValueOrTypeInfo(Sema& sema, SemaNodeView& view)
{
    if (sema.isValue(view.nodeRef()))
        return Result::Continue;
    if (isIgnoredValuePoison(sema, view.nodeRef()))
        return Result::Error;
    if (view.typeRef().isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, view.nodeRef());

    ConstantRef cstRef;
    SWC_RESULT(sema.makeRuntimeTypeInfo(cstRef, view.typeRef(), view.nodeRef()));
    sema.setConstant(view.nodeRef(), cstRef);
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

    return Result::Continue;
}

Result SemaCheck::prepareBoolExprValue(Sema& sema, SemaNodeView& view)
{
    SWC_RESULT(typePattern(sema, view.nodeRef()));
    SWC_RESULT(isValueOrTypeInfo(sema, view));
    SWC_RESULT(normalizeTypeInfoValueIfNeeded(sema, view));

    if (!view.typeRef().isValid())
        return Result::Continue;

    const TypeInfo& normalizedType = SemaHelpers::aliasEnumType(sema, view);
    if (!normalizedType.isReference())
        return Result::Continue;

    const TypeRef valueTypeRef = normalizedType.payloadTypeRef();
    SWC_RESULT(Cast::cast(sema, view, valueTypeRef, CastKind::Implicit));
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

    return Result::Continue;
}

Result SemaCheck::castToBool(Sema& sema, SemaNodeView& view)
{
    const bool representedTypeValue = SemaHelpers::resolveRepresentedTypeRef(sema, view).isValid();
    SWC_RESULT(prepareBoolExprValue(sema, view));
    SWC_RESULT(Cast::cast(sema, view, sema.typeMgr().typeBool(), CastKind::BoolExpr));

    if (representedTypeValue)
    {
        const SemaNodeView castView = sema.viewNodeTypeConstant(view.nodeRef());
        if (!castView.cst() || !castView.cst()->isBool())
        {
            sema.setConstant(view.nodeRef(), sema.cstMgr().cstTrue());
            view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }
    }

    return Result::Continue;
}

Result SemaCheck::conditionBinding(Sema& sema, AstNodeRef varDeclRef)
{
    const AstNodeRef declRef = SemaVarDeclHelpers::singleDeclarationRef(sema, varDeclRef);
    if (declRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, varDeclRef);

    if (const auto* decl = sema.node(declRef).safeCast<AstSingleVarDecl>())
        SWC_RESULT(typePattern(sema, decl->nodeInitRef, true));

    const SemaNodeView declView = sema.view(declRef, SemaNodeViewPartE::Symbol);
    const Symbol*      sym      = declView.singleSymbol();
    if (!sym)
        return SemaError::raise(sema, DiagnosticId::sema_err_not_value_expr, declRef);

    const TypeRef typeRef = sym->typeRef();
    if (typeRef.isInvalid())
        return Result::Continue;

    const TypeInfo& type = sema.typeMgr().get(typeRef);
    if (type.isConvertibleToBoolAliasAware(sema.ctx()))
        return Result::Continue;

    auto diag = SemaError::report(sema, DiagnosticId::sema_err_cannot_cast, sym->codeRef());
    diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, sema.typeMgr().typeBool());
    diag.report(sema.ctx());

    return Result::Error;
}

Result SemaCheck::typePattern(Sema& sema, AstNodeRef exprRef, bool binding)
{
    if (exprRef.isInvalid())
        return Result::Continue;

    while (const auto* paren = sema.node(exprRef).safeCast<AstParenExpr>())
        exprRef = paren->nodeExprRef;

    const AstNode& node     = sema.node(exprRef);
    const auto*    cast     = node.safeCast<AstCastExpr>();
    const auto*    autoCast = node.safeCast<AstAutoCastExpr>();
    if (!(cast && cast->modifierFlags.has(AstModifierFlagsE::Try)) &&
        !(autoCast && autoCast->modifierFlags.has(AstModifierFlagsE::Try)))
        return Result::Continue;

    // Patterns lower to casts too; their source token remains 'is'. Only a
    // user-written cast used directly as a test needs the canonical spelling.
    const TokenId token = sema.compiler().srcView(node.srcViewRef()).token(node.tokRef()).id;
    if (token == TokenId::KwdIs)
        return Result::Continue;

    return SemaError::raise(sema, binding ? DiagnosticId::sema_err_dynamic_cast_binding : DiagnosticId::sema_err_dynamic_cast_test, exprRef);
}

Result SemaCheck::isConstant(Sema& sema, AstNodeRef nodeRef)
{
    const SemaNodeView view = sema.viewConstant(nodeRef);
    if (view.cstRef().isInvalid())
    {
        SemaError::raiseExprNotConst(sema, nodeRef);
        return Result::Error;
    }

    return Result::Continue;
}

Result SemaCheck::isValidSignature(Sema& sema, const std::vector<SymbolVariable*>& parameters, bool attribute)
{
    bool                  hasName             = false;
    bool                  hasDefault          = false;
    const SymbolVariable* previousDefaultParm = nullptr;

    for (size_t i = 0; i < parameters.size(); i++)
    {
        const SymbolVariable& param = *(parameters[i]);
        const TypeInfo&       type  = param.type(sema.ctx());

        if (attribute)
        {
            const TypeInfo* baseType = &type;
            if (type.isTypedVariadic())
                baseType = &sema.typeMgr().get(type.payloadTypeRef());

            bool allowed = false;
            if (baseType->isBool() ||
                baseType->isChar() ||
                baseType->isString() ||
                baseType->isInt() ||
                baseType->isFloat() ||
                baseType->isRune() ||
                baseType->isEnum() ||
                baseType->isTypeInfo() ||
                baseType->isType())
            {
                allowed = true;
            }

            if (!allowed)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_attribute_parameter_type, param);
                diag.addArgument(Diagnostic::ARG_TYPE, type.toName(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        if (type.isAnyVariadic() && i != parameters.size() - 1)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_variadic_not_last, param);
            if (param.idRef().isValid() && parameters[i + 1]->idRef().isValid())
                diag.addArgument(Diagnostic::ARG_VALUE, parameters[i + 1]->name(sema.ctx()));

            diag.report(sema.ctx());
            return Result::Error;
        }

        // Required parameters must precede defaults, except trailing code blocks.
        if (param.hasExtraFlag(SymbolVariableFlagsE::Initialized))
        {
            hasDefault          = true;
            previousDefaultParm = &param;
        }
        else if (hasDefault && !type.isCodeBlock())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_parameter_default_value_not_last, param);
            if (param.idRef().isValid() && previousDefaultParm && previousDefaultParm->idRef().isValid())
                diag.addArgument(Diagnostic::ARG_VALUE, previousDefaultParm->name(sema.ctx()));

            diag.report(sema.ctx());
            return Result::Error;
        }

        // Once a parameter is named, later parameters need names; ? reserves a slot.
        const AstNode* paramDecl = param.decl();
        const bool     unnamed   = paramDecl && paramDecl->is(AstNodeId::LambdaParam) && paramDecl->cast<AstLambdaParam>().hasFlag(AstLambdaParamFlagsE::Named);
        if (param.idRef().isValid() || unnamed)
            hasName = true;
        else if (hasName)
            return SemaError::raise(sema, DiagnosticId::sema_err_unnamed_parameter, param);
    }

    return Result::Continue;
}

Result SemaCheck::isAssignable(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView, const bool allowLetReferenceWriteThrough)
{
    if (isInlineConstAssignmentBinding(sema, leftExprRef))
    {
        auto diag = reportReadOnlyAssignment(sema, leftExprRef);
        if (const SymbolVariable* param = inlineParameterByBinding(sema, leftExprRef))
            diag.addArgument(Diagnostic::ARG_VALUE, param->name(sema.ctx()));

        diag.report(sema.ctx());
        return Result::Error;
    }

    if (leftView.sym())
    {
        if (leftView.sym()->isLetVariable())
        {
            const bool canWriteThroughReference = allowLetReferenceWriteThrough &&
                                                  leftView.type() &&
                                                  leftView.type()->isReference();
            if (!canWriteThroughReference)
            {
                // Read-only captures are fixed in the capture list, so highlight
                // that contract rather than the declaration copied into it.
                const auto* symVar  = leftView.sym()->safeCast<SymbolVariable>();
                const bool  capture = symVar && symVar->isClosureCapture();

                auto diag = SemaError::report(sema, capture ? DiagnosticId::sema_err_assign_to_capture : DiagnosticId::sema_err_assign_to_let, leftExprRef);
                SemaError::setReportArguments(sema, diag, leftView.sym());

                diag.addNote(capture ? DiagnosticId::sema_note_capture_declared_here : DiagnosticId::sema_note_let_variable_declared_here);
                diag.last().addArgument(Diagnostic::ARG_SYM, leftView.sym()->name(sema.ctx()));
                diag.last().addSpan(leftView.sym()->codeRange(sema.ctx()));
                diag.report(sema.ctx());

                return Result::Error;
            }
        }

        if (leftView.sym()->isConstant())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_to_const, leftExprRef);
            SemaError::setReportArguments(sema, diag, leftView.sym());

            diag.addNote(DiagnosticId::sema_note_constant_declared_here);
            diag.last().addArgument(Diagnostic::ARG_SYM, leftView.sym()->name(sema.ctx()));
            diag.last().addSpan(leftView.sym()->codeRange(sema.ctx()));
            diag.report(sema.ctx());

            return Result::Error;
        }

        // Report the field's readonly contract before the generic const path
        // loses the more precise reason for rejecting the write.
        const auto* field = leftView.sym()->safeCast<SymbolVariable>();
        if (field && field->isMemberReadOnly() && !SemaAccess::canWriteMember(sema, *field, sema.node(leftExprRef).srcViewRef()))
            return SemaAccess::reportMemberWrite(sema, *field, leftExprRef);
    }

    const SymbolVariable* readOnlyParameter = nonReassignableParameterIdentifier(sema, leftExprRef);
    if (!readOnlyParameter)
        readOnlyParameter = readOnlyAggregateParameterPath(sema, leftExprRef);

    if (readOnlyParameter)
    {
        auto diag = reportReadOnlyAssignment(sema, leftExprRef);
        diag.addArgument(Diagnostic::ARG_VALUE, readOnlyParameter->name(sema.ctx()));
        diag.report(sema.ctx());

        return Result::Error;
    }

    // Assigning to a reference writes through it: a const reference (or a reference
    // to const) is never assignable.
    if (leftView.type() && leftView.typeRef().isValid())
    {
        const TypeInfo& unwrappedType = SemaHelpers::aliasEnumType(sema, leftView);
        if (unwrappedType.isReference() &&
            (unwrappedType.isConst() || sema.typeMgr().get(unwrappedType.payloadTypeRef()).isConst()))
        {
            const auto diag = reportReadOnlyAssignment(sema, leftExprRef);
            diag.report(sema.ctx());

            return Result::Error;
        }
    }

    if (isConstAssignmentTarget(sema, leftExprRef, leftView))
    {
        auto diag = reportReadOnlyAssignment(sema, leftExprRef);
        if (const SymbolVariable* param = inlineParameterByBindingPath(sema, leftExprRef))
            diag.addArgument(Diagnostic::ARG_VALUE, param->name(sema.ctx()));

        diag.report(sema.ctx());
        return Result::Error;
    }

    if (!sema.isLValue(leftExprRef) && !sema.isLValueStored(leftExprRef))
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_assign_not_lvalue, leftExprRef);
        diag.report(sema.ctx());

        return Result::Error;
    }

    return checkCompileTimeGlobalWrite(sema, leftExprRef);
}

bool SemaCheck::isConstAssignmentTarget(Sema& sema, AstNodeRef leftExprRef, const SemaNodeView& leftView)
{
    SWC_UNUSED(leftView);
    return isConstAssignmentTargetImpl(sema, leftExprRef);
}

bool SemaCheck::isImmutableBinding(Sema& sema, AstNodeRef nodeRef)
{
    const AstNodeRef resolvedRef = resolveNodeRefForCheck(sema, nodeRef);
    if (resolvedRef.isInvalid())
        return false;

    const SemaNodeView symbolView = sema.viewSymbol(resolvedRef);
    if (!symbolView.hasSymbol() || !symbolView.sym())
        return false;

    return symbolView.sym()->isLetVariable() || symbolView.sym()->isConstant();
}

bool SemaCheck::isReadOnlyParameterPath(Sema& sema, AstNodeRef nodeRef)
{
    return readOnlyAggregateParameterPath(sema, nodeRef) != nullptr;
}

void SemaCheck::unreachableCode(Sema& sema, AstNodeRef blockRef, AstNodeRef childRef)
{
    if (!stopsBlockFlow(sema, blockRef, childRef))
        return;

    // Only active-block post-child callbacks call this; their snapshot stays fixed here.
    const auto children = sema.visit().currentChildren();

    uint32_t index = 0;
    while (index < children.size() && children[index] != childRef)
        index++;
    if (index + 1 >= children.size())
        return;

    // Report only the first unreachable statement after the block's first jump.
    for (uint32_t before = 0; before < index; before++)
    {
        if (stopsBlockFlow(sema, blockRef, children[before]))
            return;
    }

    auto diag = SemaError::report(sema, DiagnosticId::sema_warn_unreachable_code, children[index + 1]);
    diag.addNote(DiagnosticId::sema_note_flow_stops_here);
    SemaError::addSpan(sema, diag.last(), childRef);
    diag.report(sema.ctx());
}

namespace
{
    // NoReturn callers discard following code and cannot receive a value;
    // reaching the body's end or returning a value would break that contract.
    Result checkNoReturnBody(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef)
    {
        const TypeRef returnTypeRef = sym.returnTypeRef();
        if (returnTypeRef.isValid() && !sema.typeMgr().get(returnTypeRef).isVoid())
        {
            const AstNodeRef returnTypeNodeRef = functionReturnTypeNodeRef(sym.decl());
            auto             diag              = SemaError::report(sema, DiagnosticId::sema_err_noreturn_return_type, returnTypeNodeRef.isValid() ? returnTypeNodeRef : bodyRef);
            diag.addArgument(Diagnostic::ARG_TYPE, sema.typeMgr().get(returnTypeRef).toName(sema.ctx()));
            diag.report(sema.ctx());

            return Result::Error;
        }

        if (SemaHelpers::stopsLocalFlow(sema, bodyRef, SemaHelpers::LocalFlowStop::Function))
            return Result::Continue;

        auto diag = SemaError::report(sema, DiagnosticId::sema_err_noreturn_reaches_end, sym);
        if (sym.name(sema.ctx()).empty())
            diag.removeArgument(Diagnostic::ARG_SYM);

        diag.report(sema.ctx());

        return Result::Error;
    }
}

Result SemaCheck::missingReturn(Sema& sema, const SymbolFunction& sym, AstNodeRef bodyRef)
{
    if (bodyRef.isInvalid() || sym.isForeign())
        return Result::Continue;

    // Macro and mixin bodies share the caller's frame, which owns their flow check.
    if (sym.attributes().hasMacroOrMixin())
        return Result::Continue;

    if (sym.attributes().hasRtFlag(RtAttributeFlagsE::NoReturn))
        return checkNoReturnBody(sema, sym, bodyRef);

    // Non-block bodies already are the returned expression, including short lambdas.
    if (sema.node(bodyRef).isNot(AstNodeId::EmbeddedBlock))
        return Result::Continue;

    const TypeRef returnTypeRef = sym.returnTypeRef();
    if (!returnTypeRef.isValid())
        return Result::Continue;

    const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
    if (returnType.isVoid())
        return Result::Continue;

    if (SemaHelpers::stopsLocalFlow(sema, bodyRef, SemaHelpers::LocalFlowStop::Function))
        return Result::Continue;

    // The declared return type is the promise being broken, so that is where the report goes.
    const AstNode*   decl              = sym.decl();
    const AstNodeRef returnTypeNodeRef = functionReturnTypeNodeRef(decl);
    auto             diag              = SemaError::report(sema, DiagnosticId::sema_err_missing_return, returnTypeNodeRef.isValid() ? returnTypeNodeRef : bodyRef);
    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));

    // Lambdas and closures need wording without an unwritten generated name.
    if (decl && decl->is(AstNodeId::FunctionDecl))
        diag.addArgument(Diagnostic::ARG_SYM, sym.name(sema.ctx()));

    diag.report(sema.ctx());

    return Result::Error;
}

namespace
{
    // Generic instances keep different #static if branches, so uses vary per
    // instance. Caller-written closures passed to an expansion do not vary;
    // stop at the first lexical function whose source does not contain them.
    bool writtenInside(Sema& sema, const SymbolFunction& inner, const SymbolFunction& outer)
    {
        if (!outer.decl() || outer.srcViewRef() != inner.srcViewRef())
            return false;
        if (sema.ast().srcView().ref() != outer.srcViewRef())
            return true;

        const uint32_t tok = inner.tokRef().get();
        return tok >= outer.decl()->tokRef().get() && tok <= outer.decl()->tokRefEnd(sema.ast()).get();
    }

    bool isInGenericInstance(Sema& sema, const SymbolFunction& sym)
    {
        for (const SymbolFunction* function = &sym; function; function = function->parentLexicalFunction())
        {
            if (function != &sym && !writtenInside(sema, sym, *function))
                return false;
            if (function->isGenericInstance())
                return true;

            const SymbolStruct* owner = function->ownerStruct();
            if (owner && owner->isGenericInstance())
                return true;
        }

        return false;
    }

    bool isReportedUnused(Sema& sema, const SymbolVariable& symVar)
    {
        if (symVar.isReferenced() || !symVar.idRef().isValid() || !symVar.decl())
            return false;
        if (symVar.hasExtraFlag(SymbolVariableFlagsE::RuntimeStorage) || symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal))
            return false;
        if (symVar.idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
            return false;

        // A 'using' variable is reached through the names it brings in, not through its own.
        if (symVar.isUsingField())
            return false;

        // Compiler-made names ('__' prefix, '#uniq') are not the author's to remove.
        if (sema.idMgr().get(symVar.idRef()).name.starts_with("__") || Token::isCompilerUniq(sema.token(symVar.codeRef()).id))
            return false;

        const AstNode* decl = symVar.decl();
        if (decl->is(AstNodeId::LambdaParam) && decl->cast<AstLambdaParam>().hasFlag(AstLambdaParamFlagsE::Generated))
            return false;

        // An '#inject' binding is offered to the injected code, which takes what it needs.
        if (decl->is(AstNodeId::SingleVarDecl) && decl->cast<AstSingleVarDecl>().injectBlockRef.isValid())
            return false;

        return true;
    }
}

Result SemaCheck::unusedVariables(Sema& sema, const SymbolFunction& sym)
{
    // Foreign/empty functions have no body to judge; generic uses vary by instance.
    if (sym.isEmpty() || sym.isForeign() || isInGenericInstance(sema, sym))
        return Result::Continue;
    if (sym.attributes().hasMacroOrMixin())
        return Result::Continue;
    if (!SemaError::isCurrentModuleSymbol(sema, sym))
        return Result::Continue;

    // The callee owns inline-generated local declarations; the caller owns
    // injected code. Check each name at its original declaration.
    if (sym.hasExtraFlag(SymbolFunctionFlagsE::InlineLocalFunction))
        return Result::Continue;

    // Generated source views refer to their origin, not an author of these names.
    const SourceView& srcView = sema.srcView(sym.srcViewRef());
    if (srcView.debugSourceCodeRef().isValid() || (srcView.ownerFileRef().isValid() && srcView.ownerFileRef() != srcView.fileRef()))
        return Result::Continue;

    // Interface parameter names serve implementations and documentation, even
    // when a default body does not use them.
    const bool interfaceContract = sym.ownerSymMap() && sym.ownerSymMap()->isInterface();

    bool reported = false;

    for (const SymbolVariable* param : sym.parameters())
    {
        if (interfaceContract)
            break;
        if (param && isReportedUnused(sema, *param))
        {
            SemaError::report(sema, DiagnosticId::sema_err_unused_parameter, *param).report(sema.ctx());
            reported = true;
        }
    }

    // Repeated expansions can declare one caller alias: any use counts for all.
    SmallVector<SourceCodeRef> usedAliasNames;
    for (const SymbolVariable* local : sym.localVariables())
    {
        if (local && local->callerNameRef().isValid() && local->isReferenced())
            usedAliasNames.push_back(local->callerNameRef());
    }

    SmallVector<SourceCodeRef> reportedAliasNames;
    TokenRef                   bodyEndRef = TokenRef::invalid();

    for (const SymbolVariable* local : sym.localVariables())
    {
        if (!local || local->hasExtraFlag(SymbolVariableFlagsE::Parameter))
            continue;

        // A local with opDrop is a guard: its scoped lifetime is its use.
        const bool guard = sema.typeMgr().hasLifecycleOperator(sema.ctx(), local->typeRef(), &SymbolStruct::opDrop);

        // Callee locals count here only when this body supplied their names
        // through a caller alias or injected code.
        if (local->isInlineExpansion())
        {
            const SourceCodeRef& aliasRef = local->callerNameRef();
            if (aliasRef.isValid())
            {
                if (local->isReferenced() || guard || std::ranges::find(usedAliasNames, aliasRef) != usedAliasNames.end() || std::ranges::find(reportedAliasNames, aliasRef) != reportedAliasNames.end())
                    continue;

                auto diag = SemaError::report(sema, DiagnosticId::sema_err_unused_variable, aliasRef);
                diag.addArgument(Diagnostic::ARG_SYM, local->idRef());
                diag.report(sema.ctx());

                reportedAliasNames.push_back(aliasRef);
                reported = true;
                continue;
            }

            if (local->srcViewRef() != sym.srcViewRef())
                continue;
            if (!bodyEndRef.isValid())
                bodyEndRef = sym.decl()->tokRefEnd(sema.ast());
            if (local->tokRef().get() < sym.tokRef().get() || local->tokRef().get() > bodyEndRef.get())
                continue;
        }

        if (guard || !isReportedUnused(sema, *local))
            continue;

        SemaError::report(sema, DiagnosticId::sema_err_unused_variable, *local).report(sema.ctx());
        reported = true;
    }

    // Sort captures into declaration order only when the body has any.
    if (sym.hasClosureCapture())
    {
        std::vector<const Symbol*> symbols;
        sym.getAllSymbols(symbols, true);

        for (const Symbol* symbol : symbols)
        {
            const auto* capture = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            if (capture && capture->isClosureCapture() && isReportedUnused(sema, *capture))
            {
                SemaError::report(sema, DiagnosticId::sema_err_unused_capture, *capture).report(sema.ctx());
                reported = true;
            }
        }
    }

    return reported ? Result::Error : Result::Continue;
}

SWC_END_NAMESPACE();
