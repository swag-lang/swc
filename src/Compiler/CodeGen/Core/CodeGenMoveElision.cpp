#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenMoveElision.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isPlainBlock(const AstNodeId id)
    {
        return id == AstNodeId::FunctionBody || id == AstNodeId::EmbeddedBlock || id == AstNodeId::TopLevelBlock;
    }

    // Contexts whose whole subtree makes any use unsafe for elision: defer bodies run at
    // scope exit (after the move), and closures/nested functions capture.
    bool isEscapeContext(const AstNodeId id)
    {
        switch (id)
        {
            case AstNodeId::DeferStmt:
            case AstNodeId::ClosureExpr:
            case AstNodeId::ClosureArgument:
            case AstNodeId::FunctionExpr:
                return true;
            default:
                return false;
        }
    }

    // Only proven plain reads/writes are safe. Other uses can expose an address
    // directly or through hidden operator/intrinsic calls.
    bool useEscapes(const CodeGen& codeGen, const AstVisit& walker)
    {
        bool crossedMember = false;
        for (size_t up = 0;; ++up)
        {
            const AstNode* parent = walker.parentNode(up);
            if (!parent)
                return false;

            switch (parent->id())
            {
                case AstNodeId::MemberAccessExpr:
                case AstNodeId::AutoMemberAccessExpr:
                    crossedMember = true;
                    continue;

                case AstNodeId::ParenExpr:
                    continue;

                // Plain value sinks: the value was read, copied, or the storage directly
                // assigned. Literals take a full copy, so the address does not flow.
                case AstNodeId::AssignStmt:
                case AstNodeId::AssignList:
                case AstNodeId::InitializerExpr:
                case AstNodeId::SingleVarDecl:
                case AstNodeId::MultiVarDecl:
                case AstNodeId::ReturnStmt:
                case AstNodeId::StructLiteral:
                case AstNodeId::StructInitializerList:
                case AstNodeId::ArrayLiteral:
                    return false;

                // Value operators and conditions: fine on a scalar member, but applied to
                // the struct itself they can resolve to a user operator taking its address.
                case AstNodeId::BinaryExpr:
                case AstNodeId::LogicalExpr:
                case AstNodeId::RelationalExpr:
                case AstNodeId::NullCoalescingExpr:
                case AstNodeId::ConditionalExpr:
                case AstNodeId::RangeExpr:
                case AstNodeId::CastExpr:
                case AstNodeId::AutoCastExpr:
                case AstNodeId::AsCastExpr:
                case AstNodeId::IsTypeExpr:
                case AstNodeId::SwitchStmt:
                case AstNodeId::IfStmt:
                case AstNodeId::ElseIfStmt:
                case AstNodeId::WhileStmt:
                case AstNodeId::ForStmt:
                case AstNodeId::ForCStyleStmt:
                    if (!crossedMember)
                        return true;

                    continue;

                case AstNodeId::UnaryExpr:
                {
                    const TokenId tokId = codeGen.token(parent->codeRef()).id;
                    if (tokId == TokenId::SymAmpersand || tokId == TokenId::ModifierMove || tokId == TokenId::ModifierFwd)
                        return true;
                    if (!crossedMember)
                        return true;

                    continue;
                }

                default:
                    return true;
            }
        }
    }

    // The function-local variable a symbol names, or null: only those carry move-elision state.
    const SymbolVariable* trackedLocalVariable(const Symbol* sym)
    {
        if (!sym || !sym->isVariable())
            return nullptr;

        const auto& symVar = sym->cast<SymbolVariable>();
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) || symVar.hasGlobalStorage())
            return nullptr;

        return &symVar;
    }

    void recordDeclaredSymbols(CodeGen& codeGen, const AstVisit& walker, const AstNodeRef blockRef)
    {
        if (blockRef.isInvalid())
            return;

        const auto record = [&](const Symbol* sym) {
            if (const SymbolVariable* symVar = trackedLocalVariable(sym))
                codeGen.moveElisionVar(*symVar).declBlockRef = blockRef;
        };

        const SemaNodeView view = codeGen.sema().viewStored(walker.currentNodeRef(), SemaNodeViewPartE::Symbol);
        if (view.sym())
            record(view.sym());
        else
        {
            for (const Symbol* sym : view.symList())
                record(sym);
        }
    }

    void recordUse(CodeGen& codeGen, const AstVisit& walker, const int escapeDepth)
    {
        const SymbolVariable* symVar = trackedLocalVariable(codeGen.sema().viewStored(walker.currentNodeRef(), SemaNodeViewPartE::Symbol).sym());
        if (!symVar)
            return;

        CodeGenMoveElisionVar& info = codeGen.moveElisionVar(*symVar);
        info.lastUseRef             = walker.currentNodeRef();
        if (escapeDepth > 0)
        {
            info.escaped      = true;
            info.deferEscaped = true;
        }
        else if (!info.escaped && useEscapes(codeGen, walker))
            info.escaped = true;
    }

    // Use the emission walk's resolver so declaration blocks, uses, and escapes
    // describe the same substituted nodes as code generation.
    void buildAnalysis(CodeGen& codeGen)
    {
        codeGen.setMoveElisionAnalyzed();

        // Match the emission root, including #test blocks and short functions.
        // Parameters and attributes encountered along the way are not function locals.
        const AstNodeRef rootRef = codeGen.function().declNodeRef();
        if (rootRef.isInvalid())
            return;

        AstVisit                walker;
        SmallVector<AstNodeRef> blockRefs;
        int                     escapeDepth = 0;

        walker.setMode(AstVisitMode::ResolveBeforeCallbacks);
        walker.setNodeRefResolver([&codeGen](const AstNodeRef nodeRef) { return codeGen.resolvedNodeRef(nodeRef); });
        walker.setPreNodeVisitor([&codeGen, &walker, &blockRefs, &escapeDepth](const AstNode& node) {
            if (isEscapeContext(node.id()))
                escapeDepth++;

            switch (node.id())
            {
                case AstNodeId::FunctionBody:
                case AstNodeId::EmbeddedBlock:
                case AstNodeId::TopLevelBlock:
                    // Cache the lexical owner shared by declarations in this block.
                    blockRefs.push_back(walker.currentNodeRef());
                    break;

                case AstNodeId::Identifier:
                    recordUse(codeGen, walker, escapeDepth);
                    break;

                case AstNodeId::SingleVarDecl:
                case AstNodeId::MultiVarDecl:
                case AstNodeId::VarDeclDestructuring:
                case AstNodeId::IfVarDecl:
                case AstNodeId::WithVarDecl:
                    recordDeclaredSymbols(codeGen, walker, blockRefs.empty() ? AstNodeRef::invalid() : blockRefs.back());
                    break;

                default:
                    break;
            }

            return Result::Continue;
        });

        walker.setPostNodeVisitor([&blockRefs, &escapeDepth](const AstNode& node) {
            if (isEscapeContext(node.id()))
                escapeDepth--;

            if (isPlainBlock(node.id()))
                blockRefs.pop_back();

            return Result::Continue;
        });

        walker.start(codeGen.ast(), rootRef);
        while (true)
        {
            const AstVisitResult result = walker.step(codeGen.ctx());
            if (result == AstVisitResult::Stop)
                break;

            if (result != AstVisitResult::Continue)
            {
                // The analysis could not complete: forbid every elision in this function.
                codeGen.clearMoveElisionVars();
                return;
            }
        }
    }
}

const SymbolVariable* CodeGenMoveElision::directStructVariable(CodeGen& codeGen, const AstNodeRef nodeRef, AstNodeRef* outResolvedRef)
{
    if (outResolvedRef)
        *outResolvedRef = AstNodeRef::invalid();

    if (nodeRef.isInvalid())
        return nullptr;

    AstNodeRef resolvedRef = codeGen.resolvedNodeRef(nodeRef);
    if (resolvedRef.isValid())
    {
        if (const auto* initExpr = codeGen.node(resolvedRef).safeCast<AstInitializerExpr>())
            resolvedRef = codeGen.resolvedNodeRef(initExpr->nodeExprRef);
    }

    if (resolvedRef.isInvalid())
        return nullptr;

    const Symbol* sym = codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol).sym();
    if (!sym || !sym->isVariable())
        return nullptr;

    const auto&     symVar      = sym->cast<SymbolVariable>();
    const TypeInfo& storageType = codeGen.typeMgr().unwrapAliasEnumTypeOrSelf(codeGen.ctx(), symVar.typeRef());
    if (!storageType.isStruct())
        return nullptr;

    if (outResolvedRef)
        *outResolvedRef = resolvedRef;

    return &symVar;
}

namespace
{
    bool isElidableLocal(CodeGen& codeGen, const SymbolVariable& symVar)
    {
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
            symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
            symVar.hasGlobalStorage() ||
            symVar.isClosureCapture())
            return false;

        return !CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar);
    }
}

bool CodeGenMoveElision::canElideMoveSource(CodeGen& codeGen, const SymbolVariable& symVar, const AstNodeRef resolvedSourceRef)
{
    if (resolvedSourceRef.isInvalid() || codeGen.inDeferredEmission())
        return false;
    if (!isElidableLocal(codeGen, symVar))
        return false;

    if (!codeGen.moveElisionAnalyzed())
        buildAnalysis(codeGen);

    const CodeGenMoveElisionVar* found = codeGen.findMoveElisionVar(symVar);
    if (!found)
        return false;

    const CodeGenMoveElisionVar& info = *found;
    if (info.escaped || info.declBlockRef.isInvalid() || info.lastUseRef != resolvedSourceRef)
        return false;

    // Only plain blocks may separate the move from its declaring scope, so it
    // post-dominates every later exit. Earlier exits already have their drops.
    const AstVisit& visit = codeGen.visit();
    for (size_t up = 0;; ++up)
    {
        const AstNode* parent = visit.parentNode(up);
        if (!parent)
            return false;
        if (visit.parentNodeRef(up) == info.declBlockRef)
            return true;
        if (!isPlainBlock(parent->id()))
            return false;
    }
}

bool CodeGenMoveElision::canMoveOutAtReturn(CodeGen& codeGen, const SymbolVariable& symVar)
{
    if (codeGen.inDeferredEmission())
        return false;
    if (!isElidableLocal(codeGen, symVar))
        return false;

    if (!codeGen.moveElisionAnalyzed())
        buildAnalysis(codeGen);

    const CodeGenMoveElisionVar* found = codeGen.findMoveElisionVar(symVar);
    if (!found)
        return false;

    // Calls and stored pointers cannot legitimately observe the local after return:
    // its scope drop would have run anyway. opPostMove restores relocation invariants.
    // Defers and closures can still access the local, so their escapes block the move.
    const CodeGenMoveElisionVar& info = *found;
    return !info.deferEscaped && info.declBlockRef.isValid();
}

const SymbolVariable* CodeGenMoveElision::returnedVariable(CodeGen& codeGen, AstNodeRef exprRef)
{
    if (exprRef.isInvalid())
        return nullptr;

    if (const auto* unary = codeGen.node(exprRef).safeCast<AstUnaryExpr>())
    {
        if (codeGen.token(unary->codeRef()).id != TokenId::ModifierMove)
            return nullptr;
        exprRef = unary->nodeExprRef;
    }

    if (!codeGen.node(exprRef).is(AstNodeId::Identifier))
        return nullptr;

    return trackedLocalVariable(codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol).sym());
}

namespace
{
    struct ReturnStorageCandidate
    {
        const SymbolVariable*    symVar        = nullptr;
        const SemaInlinePayload* returnContext = nullptr;
        bool                     returned      = false;
        bool                     rejected      = false;
        bool                     addressTaken  = false;
    };

    // A return of another value that the candidate, built in the return slot, gives way to.
    struct ReturnStorageReplacement
    {
        uint32_t   candidate = 0;
        AstNodeRef returnRef = AstNodeRef::invalid();
    };

    struct ReturnStorageBlock
    {
        size_t inScope      = 0;
        size_t activeDefers = 0;
        size_t deferUses    = 0;
    };

    struct ReturnStorageWalk
    {
        SmallVector<ReturnStorageCandidate>   candidates;
        SmallVector<ReturnStorageReplacement> replacements;
        FlatKeyMap<uint32_t, uint64_t>        indexOf;
        SmallVector<uint32_t>                 inScope;     // candidates declared in the open blocks
        SmallVector<uint32_t>                 deferUses;   // candidates the active defers read or write
        SmallVector<uint32_t>                 bodyUses;    // candidates used in the defers being walked
        SmallVector<ReturnStorageBlock>       blocks;      // sizes of the lists above when each block opened
        SmallVector<size_t>                   deferMarks;  // 'bodyUses' size when each defer body opened
        SmallVector<AstNodeRef>               contextRefs; // nodes that opened an inline context
        SmallVector<const SemaInlinePayload*> contexts;
        size_t                                activeDefers  = 0; // defers registered in the open blocks
        int                                   captureDepth  = 0;
        int                                   functionDepth = 0;

        // Where a 'return' emitted here goes, as AstReturnStmt::codeGenPostNode decides it.
        const SemaInlinePayload* returnContext() const
        {
            const SemaInlinePayload* payload = contexts.empty() ? nullptr : contexts.back();
            return payload && !payload->returnsToCallerSite() ? payload : nullptr;
        }

        ReturnStorageCandidate* find(const SymbolVariable* symVar)
        {
            const uint32_t* index = symVar ? indexOf.find(reinterpret_cast<uintptr_t>(symVar)) : nullptr;
            return index ? &candidates[*index] : nullptr;
        }
    };

    AstNodeRef functionBodyRef(const AstNode& node)
    {
        if (const auto* fn = node.safeCast<AstFunctionDecl>())
            return fn->nodeBodyRef;
        if (const auto* fn = node.safeCast<AstFunctionExpr>())
            return fn->nodeBodyRef;
        if (const auto* fn = node.safeCast<AstClosureExpr>())
            return fn->nodeBodyRef;
        return AstNodeRef::invalid();
    }

    bool isNestedFunction(const AstNodeId id)
    {
        return id == AstNodeId::FunctionExpr || id == AstNodeId::ClosureExpr;
    }

    // An explicit '&local', or the address of one of its parts.
    bool isAddressTaken(const CodeGen& codeGen, const AstVisit& walker)
    {
        for (size_t up = 0;; ++up)
        {
            const AstNode* parent = walker.parentNode(up);
            if (!parent || parent->isNot(AstNodeId::MemberAccessExpr))
                return parent && parent->is(AstNodeId::UnaryExpr) && codeGen.token(parent->codeRef()).id == TokenId::SymAmpersand;
        }
    }

    void addReturnStorageCandidates(CodeGen& codeGen, ReturnStorageWalk& walk, const AstNodeRef declRef)
    {
        const AstNode& decl = codeGen.node(declRef);
        const auto*    one  = decl.safeCast<AstSingleVarDecl>();
        const auto*    many = decl.safeCast<AstMultiVarDecl>();
        if (one && one->flags().hasAny({AstVarDeclFlagsE::Const, AstVarDeclFlagsE::Parameter, AstVarDeclFlagsE::Using}))
            return;
        if (many && many->flags().hasAny({AstVarDeclFlagsE::Const, AstVarDeclFlagsE::Parameter, AstVarDeclFlagsE::Using}))
            return;

        const auto add = [&](const Symbol* sym) {
            const SymbolVariable* symVar = trackedLocalVariable(sym);
            if (!symVar || symVar->hasExtraFlag(SymbolVariableFlagsE::Parameter) || symVar->isClosureCapture() || walk.find(symVar))
                return;
            if (codeGen.typeMgr().get(symVar->typeRef()).isReference())
                return;

            walk.indexOf.getOrInsert(reinterpret_cast<uintptr_t>(symVar)) = static_cast<uint32_t>(walk.candidates.size());
            walk.inScope.push_back(static_cast<uint32_t>(walk.candidates.size()));
            walk.candidates.push_back({.symVar = symVar, .returnContext = walk.returnContext()});
        };

        const SemaNodeView view = codeGen.sema().viewStored(declRef, SemaNodeViewPartE::Symbol);
        if (view.sym())
            add(view.sym());
        else
        {
            for (const Symbol* sym : view.symList())
                add(sym);
        }
    }

    // A returned value that is complete before the local it replaces is released: a call, a
    // literal, an operator result, or a plain variable. A place reached through a member, an
    // index or a pointer could still be owned by that local, and is read only afterwards.
    bool isEvaluatedApart(CodeGen& codeGen, AstNodeRef exprRef)
    {
        if (exprRef.isInvalid())
            return false;

        const AstNode& node = codeGen.node(exprRef);
        switch (node.id())
        {
            case AstNodeId::ParenExpr:
                return isEvaluatedApart(codeGen, node.cast<AstParenExpr>().nodeExprRef);
            case AstNodeId::ErrorManagementExpr:
                return isEvaluatedApart(codeGen, node.cast<AstErrorManagementExpr>().nodeExprRef);
            case AstNodeId::ConditionalExpr:
            {
                const auto& conditional = node.cast<AstConditionalExpr>();
                return isEvaluatedApart(codeGen, conditional.nodeTrueRef) && isEvaluatedApart(codeGen, conditional.nodeFalseRef);
            }
            case AstNodeId::Identifier:
            {
                const Symbol* sym = codeGen.sema().viewStored(exprRef, SemaNodeViewPartE::Symbol).sym();
                return sym && (!sym->isVariable() || !codeGen.typeMgr().get(sym->cast<SymbolVariable>().typeRef()).isReference());
            }
            case AstNodeId::CallExpr:
            case AstNodeId::IntrinsicCallExpr:
            case AstNodeId::IntrinsicCall:
            case AstNodeId::IntrinsicCallVariadic:
            case AstNodeId::BinaryExpr:
            case AstNodeId::StructLiteral:
            case AstNodeId::StructInitializerList:
            case AstNodeId::ArrayLiteral:
            case AstNodeId::StringLiteral:
            case AstNodeId::NullLiteral:
            case AstNodeId::TaggedUnionLiteral:
                return true;
            default:
                return false;
        }
    }

    // Every candidate of this return context still in scope is replaced by this return,
    // unless it is the very local returned. A defer that runs after this return must not
    // see the result change under it: an ordinary local is a copy by then. The function's
    // own result can give way to another returned value: that value is built apart, the
    // local is released, and the value takes its place (see 'returnReplacedLocal').
    void recordReturn(CodeGen& codeGen, ReturnStorageWalk& walk, AstNodeRef returnRef, const AstReturnStmt& returnStmt)
    {
        const SemaInlinePayload* context        = walk.returnContext();
        const SymbolVariable*    returned       = CodeGenMoveElision::returnedVariable(codeGen, returnStmt.nodeExprRef);
        const auto*              returnedLocal  = walk.find(returned);
        const bool               returnsInScope = returnedLocal && std::ranges::find(walk.inScope, static_cast<uint32_t>(returnedLocal - walk.candidates.data())) != walk.inScope.end();
        for (const uint32_t index : walk.inScope)
        {
            ReturnStorageCandidate& candidate   = walk.candidates[index];
            const bool              usedByDefer = std::ranges::find(walk.deferUses, index) != walk.deferUses.end();
            if (candidate.returnContext != context)
                continue;
            if (candidate.symVar == returned)
            {
                candidate.returned = true;
                if (usedByDefer || (candidate.addressTaken && walk.activeDefers))
                    candidate.rejected = true;
                continue;
            }

            const bool initialized = candidate.symVar->hasExtraFlag(SymbolVariableFlagsE::Initialized);
            if (context || returnsInScope || usedByDefer || candidate.addressTaken || !initialized || !isEvaluatedApart(codeGen, returnStmt.nodeExprRef))
                candidate.rejected = true;
            else
                walk.replacements.push_back({.candidate = index, .returnRef = returnRef});
        }
    }

    // The type a context returns through storage the callee writes, or invalid when it
    // returns in registers, by reference, or not at all.
    TypeRef returnStorageTypeRef(CodeGen& codeGen, const SemaInlinePayload* context)
    {
        TypeRef typeRef = TypeRef::invalid();
        if (context)
        {
            if (!context->resultVar)
                return TypeRef::invalid();
            typeRef = context->returnTypeRef;
        }
        else
        {
            const SymbolFunction& function = codeGen.function();
            const AstNode*        decl     = function.decl();
            if (!decl || (decl->isNot(AstNodeId::FunctionDecl) && decl->isNot(AstNodeId::FunctionExpr) && decl->isNot(AstNodeId::ClosureExpr)))
                return TypeRef::invalid();
            if (!CodeGenFunctionHelpers::functionUsesIndirectReturnStorage(codeGen, function))
                return TypeRef::invalid();
            typeRef = function.returnTypeRef();
        }

        if (!typeRef.isValid() || typeRef == codeGen.typeMgr().typeVoid() || codeGen.typeMgr().get(typeRef).isReference())
            return TypeRef::invalid();

        return typeRef;
    }
}

void CodeGenMoveElision::selectReturnStorageLocals(CodeGen& codeGen)
{
    const AstNodeRef rootRef = codeGen.function().declNodeRef();
    if (rootRef.isInvalid())
        return;

    ReturnStorageWalk walk;
    AstVisit          walker;
    walker.setMode(AstVisitMode::ResolveBeforeCallbacks);
    walker.setNodeRefResolver([&codeGen](const AstNodeRef nodeRef) { return codeGen.resolvedNodeRef(nodeRef); });
    walker.setPreNodeVisitor([&codeGen, &walker, &walk](const AstNode& node) {
        const AstNodeRef nodeRef = walker.currentNodeRef();

        // Track inline contexts exactly as emission pushes them.
        void* rawInlinePayload = nullptr;
        void* rawOverride      = nullptr;
        codeGen.sema().inlineContext(nodeRef, rawInlinePayload, rawOverride);
        const auto* inlinePayload  = static_cast<const SemaInlinePayload*>(rawInlinePayload);
        const auto* inlineOverride = static_cast<const SemaInlineContextOverride*>(rawOverride);
        if (inlinePayload && inlinePayload->inlineRootRef == nodeRef)
        {
            walk.contextRefs.push_back(nodeRef);
            walk.contexts.push_back(inlinePayload);
        }
        else if (inlineOverride)
        {
            walk.contextRefs.push_back(nodeRef);
            walk.contexts.push_back(inlineOverride->targetInlinePayload);
        }

        if (node.is(AstNodeId::ClosureArgument))
            walk.captureDepth++;
        if (isNestedFunction(node.id()))
            walk.functionDepth++;
        if (node.is(AstNodeId::DeferStmt))
            walk.deferMarks.push_back(walk.bodyUses.size());
        if (isPlainBlock(node.id()))
            walk.blocks.push_back({.inScope = walk.inScope.size(), .activeDefers = walk.activeDefers, .deferUses = walk.deferUses.size()});

        if (node.is(AstNodeId::Identifier))
        {
            ReturnStorageCandidate* candidate = walk.find(trackedLocalVariable(codeGen.sema().viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym()));
            if (candidate)
            {
                // A capture borrows the local like '&local': no closure that captures it can
                // outlive the function, but a defer could still call one. A closure body only
                // names its captures, so a local found there is reached some other way.
                if (walk.captureDepth)
                    candidate->addressTaken = true;
                else if (walk.functionDepth)
                    candidate->rejected = true;
                else if (!walk.deferMarks.empty())
                    walk.bodyUses.push_back(static_cast<uint32_t>(candidate - walk.candidates.data()));
                else if (isAddressTaken(codeGen, walker))
                    candidate->addressTaken = true;
            }
        }

        if ((node.is(AstNodeId::SingleVarDecl) || node.is(AstNodeId::MultiVarDecl)) && walk.deferMarks.empty() && !walk.captureDepth && !walk.functionDepth)
            addReturnStorageCandidates(codeGen, walk, nodeRef);

        return Result::Continue;
    });

    // Skip what code generation does not emit here: the parts of the function other than its
    // body, a nested function except the captures a closure takes, a '#code' argument (emitted
    // where it is injected), and the branches a compile-time condition did not select.
    walker.setPreChildVisitor([&codeGen, &walker, rootRef](AstNode& node, AstNodeRef& childRef) {
        if (codeGen.sema().isImplicitCodeBlockArg(walker.currentNodeRef(), childRef))
            return Result::SkipChildren;

        if (node.is(AstNodeId::FunctionDecl) || node.is(AstNodeId::FunctionExpr) || node.is(AstNodeId::ClosureExpr))
        {
            const AstNodeRef resolvedChildRef = codeGen.resolvedNodeRef(childRef);
            if (walker.currentNodeRef() == codeGen.resolvedNodeRef(rootRef))
                return resolvedChildRef == codeGen.resolvedNodeRef(functionBodyRef(node)) ? Result::Continue : Result::SkipChildren;
            return node.is(AstNodeId::ClosureExpr) && resolvedChildRef.isValid() && codeGen.node(resolvedChildRef).is(AstNodeId::ClosureArgument) ? Result::Continue : Result::SkipChildren;
        }

        if (node.isNot(AstNodeId::CompilerIf) && node.isNot(AstNodeId::CompilerSwitch))
            return Result::Continue;
        return Ast::nodeIdInfos(node.id()).codeGenPreNodeChild(codeGen, node, childRef);
    });

    walker.setPostNodeVisitor([&codeGen, &walker, &walk](const AstNode& node) {
        if (node.is(AstNodeId::ReturnStmt) && !walk.functionDepth)
            recordReturn(codeGen, walk, walker.currentNodeRef(), node.cast<AstReturnStmt>());

        // A defer outside any other defer body runs at the exits of its block. One that only
        // runs on failure never follows a return.
        if (node.is(AstNodeId::DeferStmt))
        {
            walk.deferMarks.pop_back();
            if (walk.deferMarks.empty())
            {
                if (!node.cast<AstDeferStmt>().modifierFlags.has(AstModifierFlagsE::Fail))
                {
                    walk.deferUses.append(walk.bodyUses.data(), walk.bodyUses.size());
                    walk.activeDefers++;
                }

                walk.bodyUses.clear();
            }
        }

        if (isPlainBlock(node.id()))
        {
            const ReturnStorageBlock& block = walk.blocks.back();
            walk.inScope.resize(block.inScope);
            walk.deferUses.resize(block.deferUses);
            walk.activeDefers = block.activeDefers;
            walk.blocks.pop_back();
        }

        if (isNestedFunction(node.id()))
            walk.functionDepth--;
        if (node.is(AstNodeId::ClosureArgument))
            walk.captureDepth--;

        if (!walk.contextRefs.empty() && walk.contextRefs.back() == walker.currentNodeRef())
        {
            walk.contextRefs.pop_back();
            walk.contexts.pop_back();
        }

        return Result::Continue;
    });

    walker.start(codeGen.ast(), rootRef);
    while (true)
    {
        const AstVisitResult result = walker.step(codeGen.ctx());
        if (result == AstVisitResult::Stop)
            break;

        // An incomplete walk proves nothing: every local keeps its own storage.
        if (result != AstVisitResult::Continue)
            return;
    }

    for (const ReturnStorageCandidate& candidate : walk.candidates)
    {
        if (!candidate.returned || candidate.rejected)
            continue;

        const TypeRef typeRef = returnStorageTypeRef(codeGen, candidate.returnContext);
        if (!typeRef.isValid())
            continue;
        if (candidate.symVar->typeRef() != typeRef && codeGen.typeMgr().unwrapAlias(codeGen.ctx(), candidate.symVar->typeRef()) != codeGen.typeMgr().unwrapAlias(codeGen.ctx(), typeRef))
            continue;

        codeGen.addReturnStorageLocal(*candidate.symVar, candidate.returnContext);
    }

    // The value a replacing return gives back cannot be built where the local still lives:
    // the storage the compiler reserved for it there becomes an ordinary temporary.
    for (const ReturnStorageReplacement& replacement : walk.replacements)
    {
        const ReturnStorageCandidate& candidate = walk.candidates[replacement.candidate];
        if (!codeGen.isReturnStorageLocal(*candidate.symVar))
            continue;

        const CodeGenLoweringPayload* lowering = codeGen.loweringPayload(replacement.returnRef);
        codeGen.addReplacingReturn(replacement.returnRef, *candidate.symVar, lowering ? lowering->runtimeStorageSym : nullptr);
    }
}

// The reference is used before the next insertion, which can move it.
CodeGenMoveElisionVar& CodeGen::moveElisionVar(const SymbolVariable& symVar)
{
    return moveElisionVars_.getOrInsert(reinterpret_cast<uintptr_t>(&symVar));
}

const CodeGenMoveElisionVar* CodeGen::findMoveElisionVar(const SymbolVariable& symVar) const
{
    return moveElisionVars_.find(reinterpret_cast<uintptr_t>(&symVar));
}

SWC_END_NAMESPACE();
