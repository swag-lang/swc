#include "pch.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Backend/CodeGen/ABI/ABITypeNormalize.h"
#include "Backend/CodeGen/ABI/CallConv.h"
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
            const auto job = heapNew<CodeGenJob>(sema.ctx(), sema, symFn, symFn.declNodeRef());
            sema.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }

    TypeRef computeRunExprStorageTypeRef(Sema& sema, const SemaNodeView& nodeView)
    {
        SWC_ASSERT(nodeView.type);
        return nodeView.type->unwrap(sema.ctx(), nodeView.typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
    }

    ConstantValue makeRunExprConstant(Sema& sema, const SemaNodeView& nodeView, TypeRef storageTypeRef, const std::byte* storagePtr)
    {
        auto& ctx = sema.ctx();
        SWC_ASSERT(nodeView.type);
        if (nodeView.type->isEnum())
        {
            const ConstantValue storageValue = ConstantValue::make(ctx, storagePtr, storageTypeRef);
            const ConstantRef   storageRef   = sema.cstMgr().addConstant(ctx, storageValue);
            return ConstantValue::makeEnumValue(ctx, storageRef, nodeView.typeRef);
        }

        ConstantValue result = ConstantValue::make(ctx, storagePtr, storageTypeRef);
        if (nodeView.type->isAlias())
            result.setTypeRef(nodeView.typeRef);
        return result;
    }

    ConstantValue makeRunExprPointerStringConstant(Sema& sema, const std::byte* storagePtr)
    {
        const auto& ctx           = sema.ctx();
        const auto  strPtrAddress = *reinterpret_cast<const uint64_t*>(storagePtr);
        if (!strPtrAddress)
            return ConstantValue::makeString(ctx, std::string_view{});

        const auto* str = reinterpret_cast<const Runtime::String*>(strPtrAddress);
        if (!str->ptr || !str->length)
            return ConstantValue::makeString(ctx, std::string_view{});

        return ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
    }
}

Result SemaJIT::runExpr(Sema& sema, SymbolFunction& symFn, AstNodeRef nodeExprRef)
{
    RESULT_VERIFY(SemaCheck::isValue(sema, nodeExprRef));
    if (sema.hasConstant(nodeExprRef))
        return Result::Continue;
    const SemaNodeView nodeView(sema, nodeExprRef);
    RESULT_VERIFY(sema.waitSemaCompleted(nodeView.type, nodeExprRef));

    scheduleCodeGen(sema, symFn);
    RESULT_VERIFY(sema.waitCodeGenCompleted(&symFn, symFn.codeRef()));

    auto&           ctx            = sema.ctx();
    const TypeRef   storageTypeRef = computeRunExprStorageTypeRef(sema, nodeView);
    const TypeInfo& storageType    = sema.typeMgr().get(storageTypeRef);
    const auto      normalizedRet  = ABITypeNormalize::normalize(ctx, CallConv::host(), nodeView.typeRef, ABITypeNormalize::Usage::Return);
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
    symFn.emit(ctx);
    symFn.jit(ctx);
    RESULT_VERIFY(JIT::call(ctx, symFn.jitEntryAddress(), &resultStorageAddress));

    ConstantValue resultConstant;
    if (!normalizedRet.isIndirect && nodeView.type->isString())
        resultConstant = makeRunExprPointerStringConstant(sema, resultStorage.data());
    else
        resultConstant = makeRunExprConstant(sema, nodeView, storageTypeRef, resultStorage.data());
    sema.setConstant(nodeExprRef, sema.cstMgr().addConstant(ctx, resultConstant));
    return Result::Continue;
}

SWC_END_NAMESPACE();
