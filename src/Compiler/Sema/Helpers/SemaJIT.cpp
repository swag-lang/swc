#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/Runtime.h"
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
            CodeGenJob* job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }

    Result ensureJitReady(SymbolFunction& root)
    {
        std::unordered_set<SymbolFunction*> visited;
        SmallVector<SymbolFunction*>        stack;
        stack.push_back(&root);

        while (!stack.empty())
        {
            SymbolFunction* const function = stack.back();
            stack.pop_back();
            if (!function)
                continue;
            if (!visited.insert(function).second)
                continue;

            if (!function->hasLoweredCode())
                return Result::Error;

            SmallVector<SymbolFunction*> dependencies;
            function->appendCallDependencies(dependencies);
            for (SymbolFunction* dependency : dependencies)
            {
                if (!dependency || dependency == function)
                    continue;
                stack.push_back(dependency);
            }
        }

        return Result::Continue;
    }

    TypeRef computeRunExprStorageTypeRef(Sema& sema, TypeRef exprTypeRef)
    {
        const TypeInfo& exprType = sema.typeMgr().get(exprTypeRef);
        return exprType.unwrap(sema.ctx(), exprTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    ConstantValue makeRunExprConstant(Sema& sema, TypeRef exprTypeRef, TypeRef storageTypeRef, const std::byte* storagePtr)
    {
        TaskContext&    ctx         = sema.ctx();
        const TypeInfo& exprType    = sema.typeMgr().get(exprTypeRef);
        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        if (exprType.isEnum())
        {
            const ConstantValue storageValue = ConstantValue::make(ctx, storagePtr, storageTypeRef);
            const ConstantRef   storageRef   = sema.cstMgr().addConstant(ctx, storageValue);
            return ConstantValue::makeEnumValue(ctx, storageRef, exprTypeRef);
        }

        if (storageType.isValuePointer() || storageType.isBlockPointer())
        {
            const uint64_t ptrValue = *reinterpret_cast<const uint64_t*>(storagePtr);
            if (!ptrValue)
            {
                ConstantValue nullValue = ConstantValue::makeNull(ctx);
                if (exprType.isAlias())
                    nullValue.setTypeRef(exprTypeRef);
                else
                    nullValue.setTypeRef(storageTypeRef);
                return nullValue;
            }
        }

        ConstantValue result = ConstantValue::make(ctx, storagePtr, storageTypeRef);
        if (exprType.isAlias())
            result.setTypeRef(exprTypeRef);
        return result;
    }

    ConstantValue makeRunExprPointerStringConstant(Sema& sema, const std::byte* storagePtr)
    {
        const TaskContext& ctx           = sema.ctx();
        const uint64_t     strPtrAddress = *reinterpret_cast<const uint64_t*>(storagePtr);
        if (!strPtrAddress)
            return ConstantValue::makeString(ctx, std::string_view{});

        const auto str = reinterpret_cast<const Runtime::String*>(strPtrAddress);
        if (!str->ptr || !str->length)
            return ConstantValue::makeString(ctx, std::string_view{});

        return ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
    }
}

Result SemaJIT::runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;
    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT_VERIFY(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    SWC_ASSERT(exprTypeRef.isValid());

    scheduleCodeGen(sema, symFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));

    TaskContext&                           ctx            = sema.ctx();
    const TypeRef                          storageTypeRef = computeRunExprStorageTypeRef(sema, exprTypeRef);
    const TypeInfo&                        storageType    = sema.typeMgr().get(storageTypeRef);
    const ABITypeNormalize::NormalizedType normalizedRet  = ABITypeNormalize::normalize(ctx, CallConv::host(), exprTypeRef, ABITypeNormalize::Usage::Return);
    SWC_ASSERT(!storageType.isVoid());

    // Storage, to store the call result of the expression
    uint64_t resultSize = storageType.sizeOf(ctx);
    if (!normalizedRet.isIndirect)
    {
        if (normalizedRet.numBits)
            resultSize = normalizedRet.numBits / 8;
        else
            resultSize = 8;
    }

    SWC_ASSERT(resultSize > 0);
    SmallVector<std::byte> resultStorage(resultSize);
    const uint64_t         resultStorageAddress = reinterpret_cast<uint64_t>(resultStorage.data());

    // Call !
    SWC_RESULT_VERIFY(ensureJitReady(symFn));
    symFn.jit(ctx);
    if (!symFn.jitEntryAddress())
        return Result::Error;

    {
        TaskScopedState scopedState(ctx);
        ctx.state().setRunJit(&symFn, nodeExprRef, sema.node(nodeExprRef).codeRef());

        auto         callErrorKind = JITCallErrorKind::None;
        const Result callResult    = JIT::call(ctx, symFn.jitEntryAddress(), &resultStorageAddress, &callErrorKind);
        if (callResult != Result::Continue)
            return Result::Error;
    }

    ConstantValue   resultConstant;
    const TypeInfo& exprType = sema.typeMgr().get(exprTypeRef);
    if (!normalizedRet.isIndirect && exprType.isString())
        resultConstant = makeRunExprPointerStringConstant(sema, resultStorage.data());
    else
        resultConstant = makeRunExprConstant(sema, exprTypeRef, storageTypeRef, resultStorage.data());
    sema.setConstant(nodeExprRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

SWC_END_NAMESPACE();
