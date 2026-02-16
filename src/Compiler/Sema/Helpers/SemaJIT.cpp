#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collectRunExprCallDependencies(Sema& sema, SymbolFunction& owner, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = sema.getSubstituteRef(nodeRef);
        if (!resolvedRef.isValid())
            return;

        const AstNode& node = sema.node(resolvedRef);
        if (node.is(AstNodeId::CallExpr))
        {
            if (sema.hasSymbol(resolvedRef))
            {
                Symbol& sym = sema.symbolOf(resolvedRef);
                if (sym.isFunction())
                {
                    auto& calledFn = sym.cast<SymbolFunction>();
                    if (owner.decl() && calledFn.decl() && owner.srcViewRef() == calledFn.srcViewRef())
                        owner.addCallDependency(&calledFn);
                }
            }
        }

        SmallVector<AstNodeRef> children;
        node.collectChildren(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectRunExprCallDependencies(sema, owner, childRef);
    }

    Result getOrCreateRunExprSymbol(Sema& sema, SymbolFunction*& outSymFn, AstNodeRef nodeExprRef)
    {
        auto&            ctx     = sema.ctx();
        const AstNodeRef nodeRef = sema.curNodeRef();

        if (sema.hasSymbol(nodeRef))
        {
            outSymFn = &sema.symbolOf(nodeRef).cast<SymbolFunction>();
            return Result::Continue;
        }

        const IdentifierRef idRef = SemaHelpers::getUniqueIdentifier(sema, "__run_expr");
        const AstNode&      node  = sema.node(nodeRef);

        outSymFn = Symbol::make<SymbolFunction>(ctx, &node, node.tokRef(), idRef, sema.frame().flagsForCurrentAccess());
        outSymFn->setOwnerSymMap(SemaFrame::currentSymMap(sema));
        outSymFn->setDeclNodeRef(nodeRef);
        outSymFn->setReturnTypeRef(sema.typeMgr().typeVoid());
        outSymFn->setAttributes(sema.frame().currentAttributes());
        outSymFn->setDeclared(ctx);
        outSymFn->setTyped(ctx);
        outSymFn->setSemaCompleted(ctx);
        SWC_ASSERT(outSymFn->tryMarkCodeGenJobScheduled());

        sema.setSymbol(nodeRef, outSymFn);

        const auto job = heapNew<CodeGenJob>(ctx, sema, *outSymFn, nodeRef);
        sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        return Result::Continue;
    }
}

Result SemaJIT::runExpr(Sema& sema, AstNodeRef nodeExprRef)
{
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (sema.hasConstant(nodeExprRef))
        return Result::Continue;

    auto&           ctx   = sema.ctx();
    SymbolFunction* symFn = nullptr;
    RESULT_VERIFY(getOrCreateRunExprSymbol(sema, symFn, nodeExprRef));
    SWC_ASSERT(symFn != nullptr);
    collectRunExprCallDependencies(sema, *symFn, nodeExprRef);
    RESULT_VERIFY(sema.waitCodeGenCompleted(symFn, sema.curNode().codeRef()));

    const SemaNodeView nodeView(sema, nodeExprRef);
    RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, nodeExprRef));

    const TypeInfo& nodeType         = *SWC_CHECK_NOT_NULL(nodeView.type);
    const TypeRef   resultStorageRef = nodeType.unwrap(ctx, nodeView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    const TypeInfo& resultStorageTy  = sema.typeMgr().get(resultStorageRef);
    SWC_ASSERT(!resultStorageTy.isVoid());

    // Storage, to store the call result of the expression
    const uint64_t resultSize = resultStorageTy.sizeOf(ctx);
    SWC_ASSERT(resultSize > 0);
    SmallVector<std::byte> resultStorage(resultSize);
    const uint64_t         resultStorageAddress = reinterpret_cast<uint64_t>(resultStorage.data());

    // Call !
    symFn->emit(ctx);
    symFn->jit(ctx);
    JIT::callVoidU64(ctx, symFn->jitEntryAddress(), resultStorageAddress);

    // Create a constant based on the result
    ConstantValue resultConstant;
    if (nodeType.isEnum())
    {
        ConstantValue     enumStorage    = ConstantValue::make(ctx, resultStorage.data(), resultStorageRef);
        const ConstantRef enumStorageRef = sema.cstMgr().addConstant(ctx, enumStorage);
        resultConstant                   = ConstantValue::makeEnumValue(ctx, enumStorageRef, nodeView.typeRef);
    }
    else if (nodeType.isAlias())
    {
        resultConstant = ConstantValue::make(ctx, resultStorage.data(), resultStorageRef);
        resultConstant.setTypeRef(nodeView.typeRef);
    }
    else
    {
        resultConstant = ConstantValue::make(ctx, resultStorage.data(), nodeView.typeRef);
    }

    sema.setConstant(nodeExprRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

SWC_END_NAMESPACE();
