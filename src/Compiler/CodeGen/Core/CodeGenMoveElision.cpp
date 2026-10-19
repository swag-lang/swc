#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenMoveElision.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/CodeGen/Core/CodeGenFunctionHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Ast/AstVisit.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
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
