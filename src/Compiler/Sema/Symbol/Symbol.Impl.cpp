#include "pch.h"
#include "Support/Report/Assert.h"

#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Symbol.Function.h"
#include "Symbol.Interface.h"
#include "Symbol.Struct.h"
#include "Symbol.Variable.h"

#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef interfaceMethodTableTypeRef(TaskContext& ctx, uint32_t count)
    {
        SmallVector4<uint64_t> dims;
        dims.push_back(count);
        return ctx.typeMgr().addType(TypeInfo::makeArray(dims, ctx.typeMgr().typeValuePtrVoid()));
    }

    const SymbolFunction* resolveInterfaceMethodTargetRec(const TaskContext& ctx, const SymbolImpl& impl, const SymbolFunction& interfaceMethod, std::unordered_set<const SymbolStruct*>& visited);

    const SymbolFunction* resolveInterfaceMethodTargetInUsingFieldsRec(const TaskContext& ctx, const SymbolStruct& objectStruct, const SymbolInterface& interfaceSym, const SymbolFunction& interfaceMethod, std::unordered_set<const SymbolStruct*>& visited)
    {
        if (!visited.insert(&objectStruct).second)
            return nullptr;

        for (const Symbol* field : objectStruct.fields())
        {
            if (!field || !field->isVariable())
                continue;

            const auto& symVar = field->cast<SymbolVariable>();
            if (!symVar.isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* targetStruct        = symVar.usingTargetStruct(ctx, usingFieldIsPointer);
            if (!targetStruct || usingFieldIsPointer || symVar.offset() != 0)
                continue;

            if (const SymbolImpl* targetImpl = targetStruct->findInterfaceImpl(interfaceSym.idRef()))
            {
                if (const SymbolFunction* targetMethod = resolveInterfaceMethodTargetRec(ctx, *targetImpl, interfaceMethod, visited))
                    return targetMethod;
            }
            else if (const SymbolFunction* targetMethod = resolveInterfaceMethodTargetInUsingFieldsRec(ctx, *targetStruct, interfaceSym, interfaceMethod, visited))
            {
                return targetMethod;
            }
        }

        return nullptr;
    }

    const SymbolFunction* resolveInterfaceMethodTargetRec(const TaskContext& ctx, const SymbolImpl& impl, const SymbolFunction& interfaceMethod, std::unordered_set<const SymbolStruct*>& visited)
    {
        if (const SymbolFunction* implMethod = impl.findFunction(interfaceMethod.idRef()))
            return implMethod;

        if (!interfaceMethod.isEmpty())
            return &interfaceMethod;

        if (!impl.isForStruct())
            return nullptr;

        const SymbolStruct* objectStruct = impl.symStruct();
        if (!objectStruct)
            return nullptr;

        const SymbolInterface* interfaceSym = impl.symInterface();
        if (!interfaceSym)
            return nullptr;

        return resolveInterfaceMethodTargetInUsingFieldsRec(ctx, *objectStruct, *interfaceSym, interfaceMethod, visited);
    }
}

SymbolStruct* SymbolImpl::symStruct() const
{
    SWC_ASSERT(isForStruct());
    return ownerStruct_;
}

void SymbolImpl::setSymStruct(SymbolStruct* sym)
{
    removeExtraFlag(SymbolImplFlagsE::ForEnum);
    addExtraFlag(SymbolImplFlagsE::ForStruct);
    ownerStruct_ = sym;
}

SymbolEnum* SymbolImpl::symEnum() const
{
    SWC_ASSERT(isForEnum());
    return ownerEnum_;
}

void SymbolImpl::setSymEnum(SymbolEnum* sym)
{
    removeExtraFlag(SymbolImplFlagsE::ForStruct);
    addExtraFlag(SymbolImplFlagsE::ForEnum);
    ownerEnum_ = sym;
}

void SymbolImpl::addFunction(const TaskContext& ctx, SymbolFunction* sym)
{
    SWC_UNUSED(ctx);
    const std::unique_lock lk(mutex_);
    if (sym->specOpKind() != SpecOpKind::None && sym->specOpKind() != SpecOpKind::Invalid)
        specOps_.push_back(sym);
}

const SymbolFunction* SymbolImpl::findFunction(IdentifierRef functionIdRef) const
{
    for (const Symbol* symbol = findFirstSymbol(functionIdRef); symbol; symbol = symbol->nextHomonym())
    {
        if (symbol->isFunction())
            return &symbol->cast<SymbolFunction>();
    }

    return nullptr;
}

const SymbolFunction* SymbolImpl::resolveInterfaceMethodTarget(const TaskContext& ctx, const SymbolFunction& interfaceMethod) const
{
    std::unordered_set<const SymbolStruct*> visited;
    return resolveInterfaceMethodTargetRec(ctx, *this, interfaceMethod, visited);
}

std::vector<SymbolFunction*> SymbolImpl::specOps() const
{
    const std::shared_lock lk(mutex_);
    return specOps_;
}

Result SymbolImpl::ensureInterfaceMethodTable(Sema& sema, ConstantRef& outRef) const
{
    outRef = ConstantRef::invalid();
    if (!isForInterface())
        return Result::Error;

    const ConstantRef publishedRef{interfaceMethodTablePublishedRef_.load(std::memory_order_acquire)};
    if (publishedRef.isValid())
    {
        outRef = publishedRef;
        return Result::Continue;
    }

    {
        const std::scoped_lock lk(interfaceMethodTableMutex_);
        if (interfaceMethodTableRef_.isValid())
        {
            outRef = interfaceMethodTableRef_;
            interfaceMethodTablePublishedRef_.store(outRef.get(), std::memory_order_release);
            return Result::Continue;
        }
    }

    TaskContext&           ctx          = sema.ctx();
    const SymbolStruct*    objectStruct = symStruct();
    const SymbolInterface* itfSym       = symInterface();
    SWC_ASSERT(objectStruct != nullptr);
    SWC_ASSERT(itfSym != nullptr);
    SWC_ASSERT(objectStruct->typeRef().isValid());
    SWC_RESULT(sema.waitSemaCompleted(this, codeRef()));
    SWC_RESULT(sema.waitSemaCompleted(objectStruct, objectStruct->codeRef()));
    SWC_RESULT(sema.waitSemaCompleted(itfSym, itfSym->codeRef()));

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.makeRuntimeTypeInfo(typeInfoCstRef, objectStruct->typeRef(), ctx.state().nodeRef));
    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());

    DataSegmentRef typeInfoRef;
    const bool     hasTypeInfoRef = sema.cstMgr().resolveConstantDataSegmentRef(typeInfoRef, typeInfoCstRef, reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    SWC_ASSERT(hasTypeInfoRef);
    if (!hasTypeInfoRef)
        return Result::Error;

    const auto&    methods      = itfSym->functions();
    const uint32_t slotCount    = static_cast<uint32_t>(methods.size()) + 1;
    const TypeRef  tableTypeRef = interfaceMethodTableTypeRef(ctx, slotCount);

    SmallVector<const SymbolFunction*> implMethods;
    implMethods.reserve(methods.size());
    for (const SymbolFunction* interfaceMethod : methods)
    {
        SWC_ASSERT(interfaceMethod != nullptr);
        const SymbolFunction* implMethod = resolveInterfaceMethodTarget(ctx, *interfaceMethod);
        if (!implMethod)
        {
            // A broken impl method can be ignored after an earlier semantic error.
            // In that case the interface table is incomplete and must fail quietly.
            return Result::Error;
        }

        SWC_RESULT(sema.waitSemaCompleted(implMethod, implMethod->codeRef()));
        implMethods.push_back(implMethod);
    }

    const std::scoped_lock lk(interfaceMethodTableMutex_);
    if (interfaceMethodTableRef_.isValid())
    {
        outRef = interfaceMethodTableRef_;
        interfaceMethodTablePublishedRef_.store(outRef.get(), std::memory_order_release);
        return Result::Continue;
    }

    const uint32_t shardIndex              = typeInfoRef.shardIndex;
    DataSegment&   segment                 = sema.cstMgr().shardDataSegment(shardIndex);
    const auto [tableOffset, tableStorage] = segment.reserveSpan<void*>(slotCount);
    SWC_ASSERT(tableStorage != nullptr);
    tableStorage[0] = reinterpret_cast<void*>(typeInfoCst.getValuePointer());
    segment.addRelocation(tableOffset, typeInfoRef.offset);

    for (uint32_t i = 0; i < implMethods.size(); ++i)
    {
        tableStorage[i + 1] = nullptr;
        segment.addFunctionRelocation(tableOffset + (i + 1) * sizeof(void*), implMethods[i]);
    }

    const std::span tableBytes{reinterpret_cast<const std::byte*>(tableStorage), static_cast<size_t>(slotCount) * sizeof(void*)};
    ConstantValue   tableCst = ConstantValue::makeArrayBorrowed(ctx, tableTypeRef, tableBytes);
    tableCst.setDataSegmentRef({.shardIndex = shardIndex, .offset = tableOffset});
    interfaceMethodTableRef_ = sema.cstMgr().addMaterializedPayloadConstant(tableCst);
    SWC_ASSERT(interfaceMethodTableRef_.isValid());
    interfaceMethodTablePublishedRef_.store(interfaceMethodTableRef_.get(), std::memory_order_release);
    outRef = interfaceMethodTableRef_;
    return Result::Continue;
}

SWC_END_NAMESPACE();
