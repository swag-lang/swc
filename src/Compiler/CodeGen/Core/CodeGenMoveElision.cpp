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

    // Whether the use of a local at the walker's current node can leak the local's
    // address (or reach it through a hidden call, like a user operator or an intrinsic).
    // Conservative: anything not provably a plain value read/write escapes.
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

    void recordDeclaredSymbols(CodeGen& codeGen, const AstVisit& walker)
    {
        AstNodeRef blockRef = AstNodeRef::invalid();
        for (size_t up = 0;; ++up)
        {
            const AstNode* parent = walker.parentNode(up);
            if (!parent)
                break;
            if (isPlainBlock(parent->id()))
            {
                blockRef = walker.parentNodeRef(up);
                break;
            }
        }

        if (blockRef.isInvalid())
            return;

        const auto record = [&](const Symbol* sym) {
            if (!sym || !sym->isVariable())
                return;
            const auto& symVar = sym->cast<SymbolVariable>();
            if (!symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) || symVar.hasGlobalStorage())
                return;
            codeGen.moveElisionVars()[&symVar].declBlockRef = blockRef;
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
        const Symbol* sym = codeGen.sema().viewStored(walker.currentNodeRef(), SemaNodeViewPartE::Symbol).sym();
        if (!sym || !sym->isVariable())
            return;

        const auto& symVar = sym->cast<SymbolVariable>();
        if (!symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) || symVar.hasGlobalStorage())
            return;

        CodeGenMoveElisionVar& info = codeGen.moveElisionVars()[&symVar];
        info.lastUseRef             = walker.currentNodeRef();
        if (escapeDepth > 0 || useEscapes(codeGen, walker))
            info.escaped = true;
    }

    // One lexical pass over the function body, resolved exactly like the emission walk
    // (the same node-ref resolver), recording per-local uses, escapes, and decl blocks.
    void buildAnalysis(CodeGen& codeGen)
    {
        codeGen.setMoveElisionAnalyzed();

        // Walk the same root as the emission walk ('#test' blocks and short functions do
        // not use a plain FunctionDecl node): parameters and attributes visited along the
        // way record nothing (parameters are not function locals).
        const AstNodeRef rootRef = codeGen.function().declNodeRef();
        if (rootRef.isInvalid())
            return;

        AstVisit walker;
        int      escapeDepth = 0;
        walker.setMode(AstVisitMode::ResolveBeforeCallbacks);
        walker.setNodeRefResolver([&codeGen](const AstNodeRef nodeRef) { return codeGen.sema().viewZero(nodeRef).nodeRef(); });
        walker.setPreNodeVisitor([&codeGen, &walker, &escapeDepth](const AstNode& node) {
            if (isEscapeContext(node.id()))
                escapeDepth++;

            switch (node.id())
            {
                case AstNodeId::Identifier:
                    recordUse(codeGen, walker, escapeDepth);
                    break;

                case AstNodeId::SingleVarDecl:
                case AstNodeId::MultiVarDecl:
                case AstNodeId::VarDeclDestructuring:
                case AstNodeId::IfVarDecl:
                case AstNodeId::WithVarDecl:
                    recordDeclaredSymbols(codeGen, walker);
                    break;

                default:
                    break;
            }

            return Result::Continue;
        });
        walker.setPostNodeVisitor([&escapeDepth](const AstNode& node) {
            if (isEscapeContext(node.id()))
                escapeDepth--;
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
                codeGen.moveElisionVars().clear();
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

    AstNodeRef resolvedRef = codeGen.sema().viewZero(nodeRef).nodeRef();
    if (resolvedRef.isValid())
    {
        if (const auto* initExpr = codeGen.node(resolvedRef).safeCast<AstInitializerExpr>())
            resolvedRef = codeGen.sema().viewZero(initExpr->nodeExprRef).nodeRef();
    }

    if (resolvedRef.isInvalid())
        return nullptr;

    const Symbol* sym = codeGen.sema().viewStored(resolvedRef, SemaNodeViewPartE::Symbol).sym();
    if (!sym || !sym->isVariable())
        return nullptr;

    const auto&   symVar           = sym->cast<SymbolVariable>();
    const TypeRef unwrappedTypeRef = codeGen.typeMgr().unwrapAliasEnum(codeGen.ctx(), symVar.typeRef());
    const TypeRef storageTypeRef   = unwrappedTypeRef.isValid() ? unwrappedTypeRef : symVar.typeRef();
    if (!codeGen.typeMgr().get(storageTypeRef).isStruct())
        return nullptr;

    if (outResolvedRef)
        *outResolvedRef = resolvedRef;
    return &symVar;
}

bool CodeGenMoveElision::canElideMoveSource(CodeGen& codeGen, const SymbolVariable& symVar, const AstNodeRef resolvedSourceRef)
{
    if (resolvedSourceRef.isInvalid() || codeGen.inDeferredEmission())
        return false;

    if (!symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
        symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
        symVar.hasExtraFlag(SymbolVariableFlagsE::RetVal) ||
        symVar.hasGlobalStorage() ||
        symVar.isClosureCapture())
        return false;
    if (CodeGenFunctionHelpers::usesCallerReturnStorage(codeGen, symVar))
        return false;

    if (!codeGen.moveElisionAnalyzed())
        buildAnalysis(codeGen);

    const auto& vars = codeGen.moveElisionVars();
    const auto  it   = vars.find(&symVar);
    if (it == vars.end())
        return false;

    const CodeGenMoveElisionVar& info = it->second;
    if (info.escaped || info.declBlockRef.isInvalid() || info.lastUseRef != resolvedSourceRef)
        return false;

    // The move must post-dominate every later exit of the declaring scope: only plain
    // blocks between the statement being emitted and the declaring block. Earlier exits
    // are unaffected — their scope drops were already emitted when this decision is made.
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

SWC_END_NAMESPACE();
