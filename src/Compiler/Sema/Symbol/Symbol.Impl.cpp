#include "pch.h"

#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.impl.h"
#include "Symbol.Function.h"
#include "Symbol.Interface.h"
#include "Symbol.Struct.h"

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
    std::vector<const Symbol*> symbols;
    getAllSymbols(symbols);
    for (const Symbol* symbol : symbols)
    {
        if (symbol && symbol->isFunction() && symbol->idRef() == functionIdRef)
            return &symbol->cast<SymbolFunction>();
    }

    return nullptr;
}

const SymbolFunction* SymbolImpl::resolveInterfaceMethodTarget(const SymbolFunction& interfaceMethod) const
{
    if (const SymbolFunction* implMethod = findFunction(interfaceMethod.idRef()))
        return implMethod;

    if (!interfaceMethod.isEmpty())
        return &interfaceMethod;

    return nullptr;
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

    {
        const std::scoped_lock lk(interfaceMethodTableMutex_);
        if (interfaceMethodTableRef_.isValid())
        {
            outRef = interfaceMethodTableRef_;
            return Result::Continue;
        }
    }

    TaskContext&           ctx          = sema.ctx();
    const SymbolStruct*    objectStruct = symStruct();
    const SymbolInterface* itfSym       = symInterface();
    SWC_ASSERT(objectStruct != nullptr);
    SWC_ASSERT(itfSym != nullptr);
    SWC_ASSERT(objectStruct->typeRef().isValid());
    SWC_RESULT(sema.waitSemaCompleted(objectStruct, objectStruct->codeRef()));
    SWC_RESULT(sema.waitSemaCompleted(itfSym, itfSym->codeRef()));

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, objectStruct->typeRef(), ctx.state().nodeRef));
    const ConstantValue& typeInfoCst = sema.cstMgr().get(typeInfoCstRef);
    SWC_ASSERT(typeInfoCst.isValuePointer());

    uint32_t  shardIndex = 0;
    const Ref typeInfoOffset =
        sema.cstMgr().findDataSegmentRef(shardIndex, reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    SWC_ASSERT(typeInfoOffset != INVALID_REF);
    if (typeInfoOffset == INVALID_REF)
        return Result::Error;

    const auto&    methods      = itfSym->functions();
    const uint32_t slotCount    = static_cast<uint32_t>(methods.size()) + 1;
    const TypeRef  tableTypeRef = interfaceMethodTableTypeRef(ctx, slotCount);

    SmallVector<SymbolFunction*> implMethods;
    implMethods.reserve(methods.size());
    for (const SymbolFunction* interfaceMethod : methods)
    {
        SWC_ASSERT(interfaceMethod != nullptr);
        const SymbolFunction* implMethod = resolveInterfaceMethodTarget(*interfaceMethod);
        SWC_ASSERT(implMethod != nullptr);
        if (!implMethod)
            return Result::Error;
        SWC_RESULT(sema.waitSemaCompleted(implMethod, implMethod->codeRef()));
        implMethods.push_back(const_cast<SymbolFunction*>(implMethod));
    }

    const std::scoped_lock lk(interfaceMethodTableMutex_);
    if (interfaceMethodTableRef_.isValid())
    {
        outRef = interfaceMethodTableRef_;
        return Result::Continue;
    }

    DataSegment& segment                   = sema.cstMgr().shardDataSegment(shardIndex);
    const auto [tableOffset, tableStorage] = segment.reserveSpan<void*>(slotCount);
    SWC_ASSERT(tableStorage != nullptr);
    tableStorage[0] = const_cast<void*>(reinterpret_cast<const void*>(typeInfoCst.getValuePointer()));
    segment.addRelocation(tableOffset, typeInfoOffset);

    for (uint32_t i = 0; i < implMethods.size(); ++i)
    {
        tableStorage[i + 1] = nullptr;
        segment.addFunctionRelocation(tableOffset + (i + 1) * sizeof(void*), implMethods[i]);
    }

    const ByteSpan      tableBytes{reinterpret_cast<const std::byte*>(tableStorage), static_cast<size_t>(slotCount) * sizeof(void*)};
    const ConstantValue tableCst = ConstantValue::makeArrayBorrowed(ctx, tableTypeRef, tableBytes);
    interfaceMethodTableRef_     = sema.cstMgr().addConstant(ctx, tableCst);
    SWC_ASSERT(interfaceMethodTableRef_.isValid());
    outRef = interfaceMethodTableRef_;
    return Result::Continue;
}

SWC_END_NAMESPACE();
