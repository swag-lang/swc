#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void scheduleCodeGen(Sema& sema, SymbolFunction& symFn)
    {
        if (symFn.tryMarkCodeGenJobScheduled())
        {
            auto* job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
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

        const auto* str = reinterpret_cast<const Runtime::String*>(strPtrAddress);
        if (!str->ptr || !str->length)
            return ConstantValue::makeString(ctx, std::string_view{});

        return ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
    }

    std::optional<Result> consumeJitExecCompletion(Sema& sema, AstNodeRef nodeRef)
    {
        const JITExecManager::Completion completion = sema.compiler().jitExecMgr().consumeCompletion(sema.ctx(), nodeRef);
        if (!completion.hasValue)
            return std::nullopt;
        return completion.result;
    }
}

Result SemaJIT::runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    SWC_RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeExprRef))
        return *completion;
    if (sema.viewConstant(nodeExprRef).hasConstant())
        return Result::Continue;
    const SemaNodeView initialView = sema.viewType(nodeExprRef);
    SWC_RESULT_VERIFY(sema.waitSemaCompleted(initialView.type(), nodeExprRef));

    const TypeRef exprTypeRef = sema.viewType(nodeExprRef).typeRef();
    SWC_ASSERT(exprTypeRef.isValid());

    sema.ctx().state().jitEmissionError = false;
    scheduleCodeGen(sema, symFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
    if (sema.ctx().state().jitEmissionError)
        return Result::Error;

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
    const auto     resultStorage        = std::make_shared<SmallVector<std::byte>>(resultSize);
    const uint64_t resultStorageAddress = reinterpret_cast<uint64_t>(resultStorage->data());

    // Call !
    SWC_RESULT_VERIFY(symFn.emit(ctx));
    if (ctx.state().jitEmissionError)
        return Result::Error;

    symFn.jit(ctx);
    if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
        return Result::Error;

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeExprRef;
    request.codeRef      = sema.node(nodeExprRef).codeRef();
    request.arg0         = resultStorageAddress;
    request.hasArg0      = true;
    request.runImmediate = false;
    request.onCompleted  = [semaPtr = &sema, nodeExprRef, exprTypeRef, storageTypeRef, normalizedRet, resultStorage](Result callResult) {
        if (callResult != Result::Continue)
            return;

        ConstantValue   resultConstant;
        const TypeInfo& exprType = semaPtr->typeMgr().get(exprTypeRef);
        if (!normalizedRet.isIndirect && exprType.isString())
            resultConstant = makeRunExprPointerStringConstant(*semaPtr, resultStorage->data());
        else
            resultConstant = makeRunExprConstant(*semaPtr, exprTypeRef, storageTypeRef, resultStorage->data());
        semaPtr->setConstant(nodeExprRef, semaPtr->cstMgr().addConstant(semaPtr->ctx(), resultConstant));
    };
    return sema.compiler().jitExecMgr().submit(ctx, std::move(request));
}

Result SemaJIT::runStatement(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeRef)
{
    if (const std::optional<Result> completion = consumeJitExecCompletion(sema, nodeRef))
        return *completion;

    sema.ctx().state().jitEmissionError = false;
    scheduleCodeGen(sema, symFn);
    SWC_RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));
    if (sema.ctx().state().jitEmissionError)
        return Result::Error;

    TaskContext& ctx = sema.ctx();

    SWC_RESULT_VERIFY(symFn.emit(ctx));
    if (ctx.state().jitEmissionError)
        return Result::Error;

    symFn.jit(ctx);
    if (ctx.state().jitEmissionError || !symFn.jitEntryAddress())
        return Result::Error;

    JITExecManager::Request request;
    request.function     = &symFn;
    request.nodeRef      = nodeRef;
    request.codeRef      = sema.node(nodeRef).codeRef();
    request.hasArg0      = false;
    request.runImmediate = false;
    return sema.compiler().jitExecMgr().submit(ctx, std::move(request));
}

SWC_END_NAMESPACE();
