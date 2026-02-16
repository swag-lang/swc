#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/JIT/JIT.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void scheduleCodeGen(Sema& sema, SymbolFunction& symFn)
    {
        if (symFn.tryMarkCodeGenJobScheduled())
        {
            const auto job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }
}

Result SemaJIT::runExpr(Sema& sema, AstNodeRef nodeRunExprRef, AstNodeRef nodeExprRef)
{
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (sema.hasConstant(nodeExprRef))
        return Result::Continue;

    auto& ctx = sema.ctx();
    SWC_ASSERT(sema.hasSymbol(nodeRunExprRef));
    auto& symFn = sema.symbolOf(nodeRunExprRef).cast<SymbolFunction>();

    scheduleCodeGen(sema, symFn);
    RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, sema.node(nodeRunExprRef).codeRef()));

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
    symFn.emit(ctx);
    symFn.jit(ctx);
    RESULT_VERIFY(JIT::call(ctx, symFn.jitEntryAddress(), &resultStorageAddress));

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
