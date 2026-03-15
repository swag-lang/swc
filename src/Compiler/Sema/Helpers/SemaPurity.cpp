#include "pch.h"
#include "Compiler/Sema/Helpers/SemaPurity.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_PURITY_BUDGET = 64;

    bool resolveFunctionDeclInCurrentAst(const Sema& sema, const SymbolFunction& fn, const AstFunctionDecl*& outDecl)
    {
        outDecl = nullptr;

        const AstNode* declNode = fn.decl();
        if (!declNode || !declNode->is(AstNodeId::FunctionDecl))
            return false;

        const Ast* const declAst = declNode->sourceAst(sema.ctx());
        if (!declAst || declAst != &sema.ast())
            return false;

        outDecl = &declNode->cast<AstFunctionDecl>();
        return true;
    }

    AstNodeRef functionBodyRef(const AstFunctionDecl& decl)
    {
        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        return decl.nodeBodyRef;
    }

    bool isWritableLocalVariable(const SymbolFunction& fn, const Symbol* sym)
    {
        if (!sym || !sym->isVariable())
            return false;

        const auto* var = &sym->cast<SymbolVariable>();
        if (var->hasExtraFlag(SymbolVariableFlagsE::Let))
            return false;

        return var->isFunctionLocalVariable(fn);
    }

    bool isWritableAssignmentTarget(Sema& sema, const SymbolFunction& fn, AstNodeRef leftRef)
    {
        if (leftRef.isInvalid())
            return false;

        const AstNodeRef resolvedLeftRef = sema.viewZero(leftRef).nodeRef();
        if (resolvedLeftRef.isInvalid())
            return false;

        const AstNode& leftNode = sema.node(resolvedLeftRef);
        if (!leftNode.is(AstNodeId::Identifier))
            return false;

        const SemaNodeView leftView = sema.viewSymbol(resolvedLeftRef);
        if (!leftView.hasSymbol())
            return false;

        return isWritableLocalVariable(fn, leftView.sym());
    }

    bool isPureCall(Sema& sema, const SymbolFunction& fn, AstNodeRef callRef)
    {
        const SemaNodeView callView = sema.viewSymbol(callRef);
        if (!callView.hasSymbol())
            return false;

        Symbol* const calledSymbol = callView.sym();
        if (!calledSymbol || !calledSymbol->isFunction())
            return false;

        const auto& calledFn = calledSymbol->cast<SymbolFunction>();
        if (&calledFn == &fn)
            return true;

        if (calledFn.isForeign())
            return false;

        return calledFn.isPure();
    }

    bool isPureFunctionBody(Sema& sema, const SymbolFunction& fn, AstNodeRef rootRef, uint32_t& budget)
    {
        if (rootRef.isInvalid())
            return false;

        SmallVector<AstNodeRef> toScan;
        toScan.push_back(rootRef);

        while (!toScan.empty())
        {
            if (!budget)
                return false;
            budget--;

            const AstNodeRef currentRef = sema.viewZero(toScan.back()).nodeRef();
            toScan.pop_back();
            if (currentRef.isInvalid())
                return false;

            const AstNode& node = sema.node(currentRef);
            if (node.is(AstNodeId::AssignStmt))
            {
                const auto& assignStmt = node.cast<AstAssignStmt>();
                if (!isWritableAssignmentTarget(sema, fn, assignStmt.nodeLeftRef))
                    return false;

                if (assignStmt.nodeRightRef.isValid())
                    toScan.push_back(assignStmt.nodeRightRef);
                continue;
            }

            if (node.is(AstNodeId::CallExpr) || node.is(AstNodeId::IntrinsicCallExpr))
            {
                if (!isPureCall(sema, fn, currentRef))
                    return false;
            }

            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : std::ranges::reverse_view(children))
            {
                if (childRef.isValid())
                    toScan.push_back(childRef);
            }
        }

        return true;
    }
}

namespace SemaPurity
{
    void computePurityFlag(Sema& sema, SymbolFunction& sym)
    {
        sym.setPure(false);

        const AstFunctionDecl* decl = nullptr;
        if (!resolveFunctionDeclInCurrentAst(sema, sym, decl))
            return;

        const AstNodeRef bodyRef = functionBodyRef(*decl);
        if (bodyRef.isInvalid())
            return;
        uint32_t budget = K_PURITY_BUDGET;
        if (!isPureFunctionBody(sema, sym, bodyRef, budget))
            return;

        sym.setPure(true);
    }
}

SWC_END_NAMESPACE();
