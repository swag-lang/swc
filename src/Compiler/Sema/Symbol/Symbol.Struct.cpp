#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isConcreteStructLayoutPending(const SymbolStruct& symbolStruct)
    {
        return !symbolStruct.isGenericRoot() || symbolStruct.isGenericInstance();
    }

    uint64_t checkedStructLayoutSize(const SymbolStruct& symbolStruct, const uint64_t sizeInBytes)
    {
        if (!isConcreteStructLayoutPending(symbolStruct))
            return 0;

#if SWC_DEV_MODE
        if (!sizeInBytes)
        {
            Utf8 detail;
            detail += std::format("  structPtr={} semaCompleted={} typed={} declared={} genericRoot={} genericInstance={} union={} fields={} declNodeRef={}\n",
                                  static_cast<const void*>(&symbolStruct),
                                  symbolStruct.isSemaCompleted(),
                                  symbolStruct.isTyped(),
                                  symbolStruct.isDeclared(),
                                  symbolStruct.isGenericRoot(),
                                  symbolStruct.isGenericInstance(),
                                  symbolStruct.isUnion(),
                                  symbolStruct.fields().size(),
                                  symbolStruct.declNodeRef().get());
            swcAssertDetail("sizeInBytes != 0", __FILE__, __LINE__, detail.view());
        }
#endif

        SWC_ASSERT(sizeInBytes != 0);
        return sizeInBytes;
    }

    uint32_t checkedStructLayoutAlignment(const SymbolStruct& symbolStruct, const uint32_t alignment)
    {
        if (!isConcreteStructLayoutPending(symbolStruct))
            return 0;

#if SWC_DEV_MODE
        if (!alignment)
        {
            Utf8 detail;
            detail += std::format("  structPtr={} semaCompleted={} typed={} declared={} genericRoot={} genericInstance={} union={} fields={} declNodeRef={}\n",
                                  static_cast<const void*>(&symbolStruct),
                                  symbolStruct.isSemaCompleted(),
                                  symbolStruct.isTyped(),
                                  symbolStruct.isDeclared(),
                                  symbolStruct.isGenericRoot(),
                                  symbolStruct.isGenericInstance(),
                                  symbolStruct.isUnion(),
                                  symbolStruct.fields().size(),
                                  symbolStruct.declNodeRef().get());
            swcAssertDetail("alignment != 0", __FILE__, __LINE__, detail.view());
        }
#endif

        SWC_ASSERT(alignment != 0);
        return alignment;
    }

    bool compareFunctionOrder(const SymbolFunction* left, const SymbolFunction* right)
    {
        SWC_ASSERT(left);
        SWC_ASSERT(right);
        return left->tokRef().get() < right->tokRef().get();
    }

    bool isRuntimeReflectedMethod(const SymbolFunction& symFunc)
    {
        if (symFunc.isIgnored() || symFunc.isAttribute() || symFunc.isEmpty())
            return false;
        if (symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
            return false;

        const SymbolStruct* ownerStruct = symFunc.ownerStruct();
        if (ownerStruct && ownerStruct->isGenericRoot() && !ownerStruct->isGenericInstance())
            return false;

        if (symFunc.isGenericRoot() && !symFunc.isGenericInstance())
            return false;

        if (!symFunc.returnTypeRef().isValid())
            return false;

        for (const SymbolVariable* param : symFunc.parameters())
        {
            if (!param || !param->typeRef().isValid())
                return false;
        }

        return true;
    }

    const SymbolFunction* registeredLifecycleFunction(const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        switch (kind)
        {
            case SpecOpKind::OpDrop:
                return ownerStruct.opDrop();
            case SpecOpKind::OpPostCopy:
                return ownerStruct.opPostCopy();
            case SpecOpKind::OpPostMove:
                return ownerStruct.opPostMove();
            default:
                return nullptr;
        }
    }

    const SymbolFunction* resolvedLifecycleFunction(const TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        if (const SymbolFunction* symFunc = registeredLifecycleFunction(ownerStruct, kind); symFunc && symFunc->isSemaCompleted())
            return symFunc;

        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc || symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (const SymbolImpl* symImpl = symFunc->declImplContext(); symImpl && symImpl->isForInterface())
                continue;
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;
            if (symFunc->specOpKind() == kind)
                return symFunc;
        }

        SWC_UNUSED(ctx);
        return registeredLifecycleFunction(ownerStruct, kind);
    }

    const SymbolFunction* findGeneratedImplicitMethod(const TaskContext& ctx, const SymbolStruct& ownerStruct, const std::string_view expectedName)
    {
        if (expectedName.empty())
            return nullptr;

        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc)
                continue;
            if (!symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;
            if (symFunc->name(ctx) == expectedName)
                return symFunc;
        }

        return nullptr;
    }

    const SymbolFunction* findGeneratedLifecycleWrapper(const TaskContext& ctx, const SymbolStruct& ownerStruct, const SpecOpKind kind)
    {
        return findGeneratedImplicitMethod(ctx, ownerStruct, SemaSpecOp::generatedLifecycleWrapperName(kind));
    }

    const SymbolFunction* findGeneratedInitWrapper(const TaskContext& ctx, const SymbolStruct& ownerStruct)
    {
        return findGeneratedImplicitMethod(ctx, ownerStruct, SemaSpecOp::generatedInitWrapperName());
    }

    enum class ImplicitDefaultKind : uint8_t
    {
        Mixed,
        AllZero,
        AllUndefined,
    };

    ImplicitDefaultKind classifyTypeImplicitDefault(Sema& sema, TypeRef typeRef);
    ImplicitDefaultKind classifyConstantImplicitDefault(Sema& sema, TypeRef typeRef, ConstantRef cstRef);

    bool updateImplicitDefaultKindState(bool& allZero, bool& allUndefined, const ImplicitDefaultKind childKind)
    {
        allZero &= childKind == ImplicitDefaultKind::AllZero;
        allUndefined &= childKind == ImplicitDefaultKind::AllUndefined;
        return allZero || allUndefined;
    }

    ImplicitDefaultKind combineImplicitDefaultKinds(const std::span<const ImplicitDefaultKind> childKinds)
    {
        if (childKinds.empty())
            return ImplicitDefaultKind::AllZero;

        bool allZero      = true;
        bool allUndefined = true;
        for (const ImplicitDefaultKind childKind : childKinds)
        {
            if (!updateImplicitDefaultKindState(allZero, allUndefined, childKind))
                return ImplicitDefaultKind::Mixed;
        }

        if (allUndefined)
            return ImplicitDefaultKind::AllUndefined;
        if (allZero)
            return ImplicitDefaultKind::AllZero;
        return ImplicitDefaultKind::Mixed;
    }

    ImplicitDefaultKind classifyConstantChildrenImplicitDefault(Sema& sema, const std::span<const ConstantRef> childValues, const std::span<const TypeRef> childTypes)
    {
        if (childValues.size() != childTypes.size())
            return ImplicitDefaultKind::Mixed;

        SmallVector<ImplicitDefaultKind> childKinds;
        childKinds.reserve(childValues.size());
        for (size_t i = 0; i < childValues.size(); ++i)
            childKinds.push_back(classifyConstantImplicitDefault(sema, childTypes[i], childValues[i]));

        return combineImplicitDefaultKinds(childKinds);
    }

    ImplicitDefaultKind classifyRepeatedConstantImplicitDefault(Sema& sema, const std::span<const ConstantRef> childValues, const TypeRef childTypeRef)
    {
        SmallVector<ImplicitDefaultKind> childKinds;
        childKinds.reserve(childValues.size());
        for (const ConstantRef childValueRef : childValues)
            childKinds.push_back(classifyConstantImplicitDefault(sema, childTypeRef, childValueRef));

        return combineImplicitDefaultKinds(childKinds);
    }

    ImplicitDefaultKind classifyConstantImplicitDefault(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return ImplicitDefaultKind::Mixed;

        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (cst.isUndefined())
            return ImplicitDefaultKind::AllUndefined;

        const TypeInfo& rawType = sema.typeMgr().get(typeRef);
        if (const TypeRef storageTypeRef = rawType.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum); storageTypeRef.isValid())
            typeRef = storageTypeRef;

        if (cst.isEnumValue())
        {
            const TypeInfo& type = sema.typeMgr().get(typeRef);
            if (!type.isIntLike())
                return ImplicitDefaultKind::Mixed;
            return classifyConstantImplicitDefault(sema, typeRef, cst.getEnumValue());
        }

        if (cst.isStruct())
            return allZeroBytes(cst.getStruct()) ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (cst.isArray())
            return allZeroBytes(cst.getArray()) ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (!type.sizeOf(sema.ctx()))
            return ImplicitDefaultKind::AllZero;

        if (cst.isNull())
        {
            if (type.isAnyPointer() || type.isReference() || type.isString() || type.isCString() || type.isSlice() || type.isAny() || type.isInterface() ||
                type.isTypeInfo() || type.isFunction())
                return ImplicitDefaultKind::AllZero;
            return ImplicitDefaultKind::Mixed;
        }

        if (type.isBool())
            return cst.isBool() && !cst.getBool() ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isChar())
            return cst.isChar() && cst.getChar() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isRune())
            return cst.isRune() && cst.getRune() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isInt())
            return cst.isInt() && cst.getInt().isZero() ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isFloat())
            return cst.isFloat() && cst.getFloat().isZero() ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isSlice())
            return cst.isSlice() && cst.getSliceCount() == 0 && cst.getSlice().empty() ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isAnyPointer() || type.isReference() || type.isTypeInfo() || type.isFunction())
        {
            if (cst.isValuePointer())
                return cst.getValuePointer() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;
            if (cst.isBlockPointer())
                return cst.getBlockPointer() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;
            return ImplicitDefaultKind::Mixed;
        }

        if (type.isArray() && cst.isAggregateArray())
        {
            uint64_t totalCount = 1;
            for (const uint64_t dim : type.payloadArrayDims())
                totalCount *= dim;
            if (cst.getAggregateArray().size() != totalCount)
                return ImplicitDefaultKind::Mixed;
            return classifyRepeatedConstantImplicitDefault(sema, cst.getAggregateArray(), type.payloadArrayElemTypeRef());
        }

        if (type.isAggregateStruct() && cst.isAggregateStruct())
            return classifyConstantChildrenImplicitDefault(sema, cst.getAggregateStruct(), type.payloadAggregate().types);

        if (type.isAggregateArray() && cst.isAggregateArray())
            return classifyConstantChildrenImplicitDefault(sema, cst.getAggregateArray(), type.payloadAggregate().types);

        return ImplicitDefaultKind::Mixed;
    }

    ImplicitDefaultKind classifyAggregateTypeImplicitDefault(Sema& sema, const std::span<const TypeRef> childTypes)
    {
        SmallVector<ImplicitDefaultKind> childKinds;
        childKinds.reserve(childTypes.size());
        for (const TypeRef childTypeRef : childTypes)
            childKinds.push_back(classifyTypeImplicitDefault(sema, childTypeRef));

        return combineImplicitDefaultKinds(childKinds);
    }

    ImplicitDefaultKind classifyTypeImplicitDefault(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return ImplicitDefaultKind::Mixed;

        const TypeInfo& rawType = sema.typeMgr().get(typeRef);
        if (const TypeRef storageTypeRef = rawType.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum); storageTypeRef.isValid())
            typeRef = storageTypeRef;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isStruct())
        {
            const auto& symStruct = type.payloadSymStruct();
            symStruct.computeImplicitDefaultFlags(sema);
            if (symStruct.hasImplicitAllUndefinedDefault())
                return ImplicitDefaultKind::AllUndefined;
            if (symStruct.hasImplicitAllZeroDefault())
                return ImplicitDefaultKind::AllZero;
            return ImplicitDefaultKind::Mixed;
        }

        if (type.isArray())
            return classifyTypeImplicitDefault(sema, type.payloadArrayElemTypeRef());

        if (type.isAggregateStruct() || type.isAggregateArray())
            return classifyAggregateTypeImplicitDefault(sema, type.payloadAggregate().types);

        return ImplicitDefaultKind::AllZero;
    }

    Result lowerImplicitDefaultBytes(Sema& sema, ByteSpanRW dstBytes, TypeRef typeRef)
    {
        const TypeInfo& rawType = sema.typeMgr().get(typeRef);
        if (const TypeRef storageTypeRef = rawType.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum); storageTypeRef.isValid())
            typeRef = storageTypeRef;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isStruct())
        {
            for (const SymbolVariable* field : type.payloadSymStruct().fields())
            {
                if (!field)
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());

                const ByteSpanRW fieldBytes = dstBytes.subspan(fieldOffset, fieldSize);
                if (const ConstantRef valueRef = field->defaultValueRef(); valueRef.isValid())
                {
                    SWC_RESULT(ConstantLower::lowerToBytes(sema, fieldBytes, valueRef, fieldTypeRef));
                }
                else if (fieldSize)
                {
                    SWC_RESULT(lowerImplicitDefaultBytes(sema, fieldBytes, fieldTypeRef));
                }
            }

            return Result::Continue;
        }

        if (type.isArray())
        {
            const TypeRef   elemTypeRef = type.payloadArrayElemTypeRef();
            const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
            const uint64_t  elemSize    = elemType.sizeOf(sema.ctx());
            if (!elemSize)
                return Result::Continue;

            uint64_t totalCount = 1;
            for (const uint64_t dim : type.payloadArrayDims())
                totalCount *= dim;

            for (uint64_t idx = 0; idx < totalCount; ++idx)
                SWC_RESULT(lowerImplicitDefaultBytes(sema, dstBytes.subspan(idx * elemSize, elemSize), elemTypeRef));
            return Result::Continue;
        }

        if (!dstBytes.empty())
            std::memset(dstBytes.data(), 0, dstBytes.size());
        return Result::Continue;
    }

    void appendImplFunctions(std::vector<SymbolFunction*>& out, const std::vector<SymbolImpl*>& implList)
    {
        for (const SymbolImpl* symImpl : implList)
        {
            if (!symImpl)
                continue;

            std::vector<Symbol*> symbols;
            symImpl->getAllSymbols(symbols);
            for (Symbol* symbol : symbols)
            {
                if (!symbol || !symbol->isFunction())
                    continue;

                out.push_back(&symbol->cast<SymbolFunction>());
            }
        }
    }

    bool sameAttributeInstance(const AttributeInstance& lhs, const AttributeInstance& rhs)
    {
        if (lhs.symbol != rhs.symbol || lhs.params.size() != rhs.params.size())
            return false;

        for (size_t i = 0; i < lhs.params.size(); ++i)
        {
            const auto& lhsParam = lhs.params[i];
            const auto& rhsParam = rhs.params[i];
            if (lhsParam.nameIdRef != rhsParam.nameIdRef || lhsParam.valueCstRef != rhsParam.valueCstRef)
                return false;
        }

        return true;
    }

    size_t inheritedAttributePrefixCount(const AttributeList& attributes, const AttributeList& inheritedAttributes)
    {
        const size_t inheritedCount = std::min(attributes.attributes.size(), inheritedAttributes.attributes.size());
        size_t       prefixCount    = 0;
        while (prefixCount < inheritedCount && sameAttributeInstance(attributes.attributes[prefixCount], inheritedAttributes.attributes[prefixCount]))
            prefixCount++;

        return prefixCount;
    }

    bool tryGetSwagLayoutAttributeValue(uint32_t& outValue, TaskContext& ctx, const AttributeList& attributes, const std::string_view attrName)
    {
        outValue = 0;
        for (const AttributeInstance& attribute : attributes.attributes)
        {
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != attrName)
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    bool tryGetFieldAlignAttributeValue(uint32_t& outValue, TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field)
    {
        outValue                             = 0;
        const AttributeList& fieldAttributes = field.attributes();
        const AttributeList& ownerAttributes = owner.attributes();
        const size_t         startIndex      = inheritedAttributePrefixCount(fieldAttributes, ownerAttributes);

        for (size_t i = startIndex; i < fieldAttributes.attributes.size(); ++i)
        {
            const AttributeInstance& attribute = fieldAttributes.attributes[i];
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != "Align")
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isInt())
                    continue;

                outValue = static_cast<uint32_t>(cst.getInt().as64());
                return true;
            }
        }

        return false;
    }

    bool tryGetFieldOffsetAttributeValue(std::string_view& outValue, TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field)
    {
        outValue                             = {};
        const AttributeList& fieldAttributes = field.attributes();
        const AttributeList& ownerAttributes = owner.attributes();
        const size_t         startIndex      = inheritedAttributePrefixCount(fieldAttributes, ownerAttributes);

        for (size_t i = startIndex; i < fieldAttributes.attributes.size(); ++i)
        {
            const AttributeInstance& attribute = fieldAttributes.attributes[i];
            if (!attribute.symbol || !attribute.symbol->inSwagNamespace(ctx) || attribute.symbol->name(ctx) != "Offset")
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (!cst.isString())
                    continue;

                outValue = cst.getString();
                return true;
            }
        }

        return false;
    }

    const SymbolVariable* findOffsetTargetField(const TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field, std::string_view targetName)
    {
        for (const SymbolVariable* candidate : owner.fields())
        {
            if (!candidate)
                continue;
            if (candidate == &field)
                break;
            if (candidate->name(ctx) == targetName)
                return candidate;
        }

        return nullptr;
    }

    uint32_t effectiveFieldAlignment(TaskContext& ctx, const SymbolStruct& owner, const SymbolVariable& field, const uint32_t structPack)
    {
        const TypeInfo& fieldType = field.typeInfo(ctx);
        uint32_t        alignOf   = std::max<uint32_t>(fieldType.alignOf(ctx), 1);

        if (structPack != 0)
            alignOf = std::min(alignOf, structPack);

        uint32_t fieldAlign = 0;
        if (tryGetFieldAlignAttributeValue(fieldAlign, ctx, owner, field) && fieldAlign != 0)
            alignOf = std::max(alignOf, fieldAlign);

        return std::max<uint32_t>(alignOf, 1);
    }

    bool resolveUsingFieldPathRec(const TaskContext& ctx, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps, std::unordered_set<const SymbolStruct*>& visited)
    {
        if (&currentStruct == &targetStruct)
            return true;
        if (!visited.insert(&currentStruct).second)
            return false;

        for (const SymbolVariable* field : currentStruct.fields())
        {
            if (!field || !field->isUsingField())
                continue;

            bool                usingFieldIsPointer = false;
            const SymbolStruct* usingTargetStruct   = field->usingTargetStruct(ctx, usingFieldIsPointer);
            if (!usingTargetStruct)
                continue;

            outSteps.push_back({.field = field, .isPointer = usingFieldIsPointer});
            if (resolveUsingFieldPathRec(ctx, *usingTargetStruct, targetStruct, outSteps, visited))
                return true;
            outSteps.pop_back();
        }

        return false;
    }

    bool sameInterfaceImplementation(const SymbolImpl& lhs, const SymbolImpl& rhs)
    {
        if (const SymbolInterface* lhsInterface = lhs.symInterface())
        {
            if (const SymbolInterface* rhsInterface = rhs.symInterface())
                return lhsInterface == rhsInterface;
        }

        return lhs.idRef() == rhs.idRef();
    }
}

void SymbolStruct::addImpl(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexImpls_);
    if (!implsSet_.insert(&symImpl).second)
    {
        symImpl.setSymStruct(this);
        return;
    }

    symImpl.setSymStruct(this);
    impls_.push_back(&symImpl);
    sema.compiler().notifyAlive();
}

std::vector<SymbolImpl*> SymbolStruct::impls() const
{
    const std::shared_lock lk(mutexImpls_);
    return impls_;
}

std::vector<SymbolFunction*> SymbolStruct::declaredMethods() const
{
    std::vector<SymbolFunction*> result;
    appendImplFunctions(result, impls());
    appendImplFunctions(result, interfaces());
    std::ranges::sort(result, compareFunctionOrder);
    return result;
}

std::vector<SymbolFunction*> SymbolStruct::methods() const
{
    // Generic roots are marked sema-complete before their impl methods are specialized.
    // Exporting runtime method reflection from that state can observe signatures that still
    // depend on the owner generic context and have no stable runtime function type yet.
    if (isGenericRoot() && !isGenericInstance())
        return {};

    std::vector<SymbolFunction*> result;
    for (SymbolFunction* symFunc : declaredMethods())
    {
        if (!symFunc || !isRuntimeReflectedMethod(*symFunc))
            continue;
        result.push_back(symFunc);
    }

    std::ranges::sort(result, compareFunctionOrder);
    return result;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    if (!interfacesSet_.insert(&symImpl).second)
    {
        symImpl.setSymStruct(this);
        return;
    }

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
}

Result SymbolStruct::addInterface(Sema& sema, SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    if (interfacesSet_.contains(&symImpl))
    {
        symImpl.setSymStruct(this);
        return Result::Continue;
    }

    for (const auto* itf : interfaces_)
    {
        if (sameInterfaceImplementation(*itf, symImpl))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_interface_already_implemented, symImpl);
            if (const SymbolInterface* symInterface = symImpl.symInterface())
                diag.addArgument(Diagnostic::ARG_SYM, symInterface->getFullScopedName(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_WHAT, name(sema.ctx()));
            auto&             note    = diag.addElement(DiagnosticId::sema_note_other_implementation);
            const SourceView& srcView = sema.compiler().srcView(itf->srcViewRef());
            note.setSrcView(&srcView);
            note.addSpan(srcView.tokenCodeRange(sema.ctx(), itf->tokRef()), "");
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    // Expose the interface implementation scope under the struct symbol map so we can resolve
    // `StructName.InterfaceName.Symbol`.
    const Symbol* inserted = addSingleSymbol(sema.ctx(), &symImpl);
    if (inserted != &symImpl)
        return SemaError::raiseAlreadyDefined(sema, &symImpl, inserted);

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
    interfacesSet_.insert(&symImpl);
    sema.compiler().notifyAlive();
    return Result::Continue;
}

std::vector<SymbolImpl*> SymbolStruct::interfaces() const
{
    const std::shared_lock lk(mutexInterfaces_);
    return interfaces_;
}

void SymbolStruct::removeIgnoredFields()
{
    std::erase_if(fields_, std::mem_fn(&Symbol::isIgnored));
    rebuildFieldIndexMap();
}

bool SymbolStruct::tryGetFieldIndex(size_t& outIndex, const SymbolVariable& sym) const noexcept
{
    const auto it = fieldIndexMap_.find(&sym);
    if (it == fieldIndexMap_.end())
        return false;

    outIndex = it->second;
    return true;
}

ConstantRef SymbolStruct::computeDefaultValue(Sema& sema, TypeRef typeRef)
{
    computeImplicitDefaultFlags(sema);
    if (hasImplicitAllUndefinedDefault())
        return ConstantRef::invalid();
    if (hasImplicitAllZeroDefault())
        return sema.cstMgr().addZeroPayloadConstant(sema.ctx(), typeRef);

    std::call_once(defaultStructOnce_, [&] {
        auto            ctx = sema.ctx();
        const TypeInfo& ty  = type(ctx);

        uint64_t structSize = ty.sizeOf(ctx);
        if (!structSize)
        {
            SWC_INTERNAL_CHECK(computeLayout(ctx) == Result::Continue);
            structSize = ty.sizeOf(ctx);
        }

        SWC_ASSERT(structSize);
        std::vector<std::byte> buffer(structSize);
        const ByteSpanRW       bytes = asByteSpan(buffer);
        SWC_INTERNAL_CHECK(lowerImplicitDefaultBytes(sema, bytes, typeRef) == Result::Continue);
        defaultStructCst_ = ConstantHelpers::materializeStaticPayloadConstant(sema, typeRef, ByteSpan{bytes.data(), bytes.size()});
        SWC_ASSERT(defaultStructCst_.isValid());
    });

    return defaultStructCst_;
}

void SymbolStruct::computeImplicitDefaultFlags(Sema& sema) const
{
    std::call_once(implicitDefaultFlagsOnce_, [&] {
        auto* self = const_cast<SymbolStruct*>(this);
        self->addExtraFlag(SymbolStructFlagsE::DefaultClassified);

        if (fields_.empty())
        {
            self->addExtraFlag(SymbolStructFlagsE::DefaultAllZero);
            return;
        }

        bool allZero      = true;
        bool allUndefined = true;
        for (const SymbolVariable* field : fields_)
        {
            if (!field)
                continue;

            auto fieldKind = ImplicitDefaultKind::Mixed;
            if (field->hasExtraFlag(SymbolVariableFlagsE::ExplicitUndefined))
            {
                fieldKind = ImplicitDefaultKind::AllUndefined;
            }
            else if (const ConstantRef valueRef = field->defaultValueRef(); valueRef.isValid())
            {
                fieldKind = classifyConstantImplicitDefault(sema, field->typeRef(), valueRef);
            }
            else
            {
                fieldKind = classifyTypeImplicitDefault(sema, field->typeRef());
            }

            allZero &= fieldKind == ImplicitDefaultKind::AllZero;
            allUndefined &= fieldKind == ImplicitDefaultKind::AllUndefined;
            if (!allZero && !allUndefined)
                return;
        }

        if (allZero)
            self->addExtraFlag(SymbolStructFlagsE::DefaultAllZero);
        if (allUndefined)
            self->addExtraFlag(SymbolStructFlagsE::DefaultAllUndefined);
    });
}

ConstantRef SymbolStruct::resolveImplicitDefaultValueRef(Sema& sema, TypeRef typeRef) const
{
    computeImplicitDefaultFlags(sema);
    if (hasImplicitAllUndefinedDefault())
        return ConstantRef::invalid();
    return const_cast<SymbolStruct*>(this)->computeDefaultValue(sema, typeRef);
}

namespace
{
    constexpr uint32_t K_GENERIC_COMPLETION_DEPTH_MASK = 0x7FFFFFFFu;
    constexpr uint32_t K_GENERIC_NODE_COMPLETED_MASK   = 1u << 31;
}

struct SymbolStruct::GenericData
{
    // Keep generic-only state off the main symbol so non-generic structs stay compact.
    GenericInstanceStorage                        instances;
    std::atomic<const TaskContext*>               completionOwner = nullptr;
    mutable std::atomic<uint32_t>                 completionState = 0;
    SymbolStruct*                                 rootSym         = nullptr;
    mutable std::recursive_mutex                  evalRunMutex;
    mutable std::shared_mutex                     evalCacheMutex;
    std::vector<SymbolInternal::GenericEvalEntry> evalCache;
};

const SymbolImpl* SymbolStruct::findInterfaceImpl(IdentifierRef interfaceIdRef) const
{
    for (const auto* itfImpl : interfaces())
    {
        if (itfImpl && itfImpl->idRef() == interfaceIdRef)
            return itfImpl;
    }

    return nullptr;
}

bool SymbolStruct::implementsInterface(const SymbolInterface& itf) const
{
    SWC_ASSERT(isSemaCompleted());
    return findInterfaceImpl(itf.idRef()) != nullptr;
}

bool SymbolStruct::implementsInterfaceOrUsingFields(Sema& sema, const SymbolInterface& itf) const
{
    if (implementsInterface(itf))
        return true;

    for (const Symbol* field : fields_)
    {
        if (!field)
            continue;

        const auto& symVar = field->cast<SymbolVariable>();
        if (!symVar.isUsingField())
            continue;

        const SymbolStruct* targetStruct = symVar.usingTargetStruct(sema.ctx());
        if (targetStruct && targetStruct->implementsInterface(itf))
            return true;
    }

    return false;
}

uint64_t SymbolStruct::sizeOf() const
{
    return checkedStructLayoutSize(*this, sizeInBytes_);
}

bool SymbolStruct::hasConcreteLayout() const noexcept
{
    if (!isConcreteStructLayoutPending(*this))
        return true;

    return sizeInBytes_ != 0 && alignment_ != 0;
}

uint32_t SymbolStruct::alignment() const
{
    return checkedStructLayoutAlignment(*this, alignment_);
}

bool SymbolStruct::resolveUsingFieldPath(const TaskContext& ctx, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps) const
{
    outSteps.clear();
    std::unordered_set<const SymbolStruct*> visited;
    return resolveUsingFieldPathRec(ctx, *this, targetStruct, outSteps, visited);
}

Result SymbolStruct::canBeCompleted(Sema& sema) const
{
    for (const auto* field : fields_)
    {
        auto& symVar = field->cast<SymbolVariable>();

        const AstNode* decl = symVar.decl();
        SWC_ASSERT(decl != nullptr);
        SWC_ASSERT(decl->is(AstNodeId::SingleVarDecl) || decl->is(AstNodeId::MultiVarDecl));
        const auto& type        = symVar.typeInfo(sema.ctx());
        AstNodeRef  typeNodeRef = AstNodeRef::invalid();
        if (decl->is(AstNodeId::SingleVarDecl))
            typeNodeRef = decl->cast<AstSingleVarDecl>().typeOrInitRef();
        else if (decl->is(AstNodeId::MultiVarDecl))
            typeNodeRef = decl->cast<AstMultiVarDecl>().typeOrInitRef();
        else
            SWC_UNREACHABLE();

        // A struct is referencing itself
        if (type.isStruct() && &type.payloadSymStruct() == this)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_struct_circular_reference, typeNodeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, symVar.name(sema.ctx()));
            diag.addArgument(Diagnostic::ARG_SYM, name(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        // Function values have pointer/closure storage. Their parameter and return
        // types do not affect the enclosing struct layout, and waiting for them can
        // create false cycles for signatures such as `func(Self)`.
        if (!type.isFunction())
            SWC_RESULT(sema.waitSemaCompleted(&type, typeNodeRef));
    }

    return Result::Continue;
}

AstNodeRef SymbolStruct::findGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings) const
{
    const auto&            data = ensureGenericData();
    const std::shared_lock lock(data.evalCacheMutex);
    return SymbolInternal::findGenericEvalNode(data.evalCache, payloadContext, ownerAst, sourceRef, bindings);
}

void SymbolStruct::cacheGenericEvalNode(const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, const AstNodeRef evalRef) const
{
    if (sourceRef.isInvalid() || evalRef.isInvalid())
        return;

    auto&                  data = ensureGenericData();
    const std::unique_lock lock(data.evalCacheMutex);
    SymbolInternal::cacheGenericEvalNode(data.evalCache, payloadContext, ownerAst, sourceRef, bindings, evalRef);
}

std::recursive_mutex& SymbolStruct::genericEvalRunMutex() const noexcept
{
    return ensureGenericData().evalRunMutex;
}

Result SymbolStruct::registerSpecOps(Sema& sema) const
{
    for (const SymbolImpl* symImpl : impls())
    {
        if (symImpl->isIgnored())
            continue;
        for (SymbolFunction* symFunc : symImpl->specOps())
        {
            if (!symFunc)
                continue;
            if (symFunc->isGenericRoot() && !symFunc->isGenericInstance())
                continue;
            SWC_RESULT(SemaSpecOp::registerSymbol(sema, *symFunc));
        }
    }

    return Result::Continue;
}

void SymbolStruct::addField(SymbolVariable* sym)
{
    SWC_ASSERT(sym != nullptr);
    SWC_ASSERT(!fieldIndexMap_.contains(sym));
    fieldIndexMap_.emplace(sym, fields_.size());
    fields_.push_back(sym);
}

void SymbolStruct::rebuildFieldIndexMap() noexcept
{
    fieldIndexMap_.clear();
    for (size_t i = 0; i < fields_.size(); ++i)
    {
        SymbolVariable* field = fields_[i];
        if (field)
            fieldIndexMap_.emplace(field, i);
    }
}

Result SymbolStruct::computeLayout(TaskContext& ctx)
{
    sizeInBytes_         = 0;
    alignment_           = 1;
    uint32_t structPack  = 0;
    uint32_t structAlign = 0;
    tryGetSwagLayoutAttributeValue(structPack, ctx, attributes(), "Pack");
    tryGetSwagLayoutAttributeValue(structAlign, ctx, attributes(), "Align");

    for (SymbolVariable* field : fields_)
    {
        auto&       symVar = field->cast<SymbolVariable>();
        const auto& type   = symVar.typeInfo(ctx);

        const uint64_t sizeOf  = type.sizeOf(ctx);
        const uint32_t alignOf = effectiveFieldAlignment(ctx, *this, symVar, structPack);
        alignment_             = std::max(alignment_, alignOf);

        if (isUnion())
        {
            symVar.setOffset(0);
            sizeInBytes_ = std::max(sizeInBytes_, sizeOf);
        }
        else
        {
            std::string_view      offsetTargetName;
            const SymbolVariable* offsetTarget = nullptr;
            uint64_t              fieldOffset  = sizeInBytes_;
            if (tryGetFieldOffsetAttributeValue(offsetTargetName, ctx, *this, symVar))
            {
                offsetTarget = findOffsetTargetField(ctx, *this, symVar, offsetTargetName);
                SWC_ASSERT(offsetTarget != nullptr);
                if (offsetTarget)
                    fieldOffset = offsetTarget->offset();
            }
            else
            {
                const uint64_t padding = (alignOf - (sizeInBytes_ % alignOf)) % alignOf;
                fieldOffset            = sizeInBytes_ + padding;
            }

            symVar.setOffset(static_cast<uint32_t>(fieldOffset));
            sizeInBytes_ = std::max(sizeInBytes_, fieldOffset + sizeOf);
        }
    }

    if (structAlign != 0)
        alignment_ = std::max(alignment_, structAlign);

    if (alignment_ > 0)
    {
        const uint64_t padding = (alignment_ - (sizeInBytes_ % alignment_)) % alignment_;
        sizeInBytes_ += padding;
    }

    sizeInBytes_ = std::max(sizeInBytes_, 1ULL);

    return Result::Continue;
}

SmallVector<SymbolFunction*> SymbolStruct::getSpecOp(IdentifierRef identifierRef) const
{
    SmallVector<SymbolFunction*> result;

    const std::shared_lock lk(mutexSpecOps_);
    for (SymbolFunction* symFunc : specOps_)
    {
        if (symFunc->idRef() == identifierRef)
            result.push_back(symFunc);
    }

    return result;
}

Result SymbolStruct::registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind)
{
    const std::unique_lock lk(mutexSpecOps_);
    if (!specOpsSet_.insert(&symFunc).second)
        return Result::Continue;
    specOps_.push_back(&symFunc);

    switch (kind)
    {
        case SpecOpKind::OpDrop:
            SWC_ASSERT(!opDrop_);
            opDrop_ = &symFunc;
            break;
        case SpecOpKind::OpPostCopy:
            SWC_ASSERT(!opPostCopy_);
            opPostCopy_ = &symFunc;
            break;
        case SpecOpKind::OpPostMove:
            SWC_ASSERT(!opPostMove_);
            opPostMove_ = &symFunc;
            break;
        default:
            break;
    }

    return Result::Continue;
}

const SymbolFunction* SymbolStruct::effectiveOpInit(const TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    return findGeneratedInitWrapper(ctx, *this);
}

const SymbolFunction* SymbolStruct::effectiveOpDrop(const TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpDrop))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpDrop);
}

const SymbolFunction* SymbolStruct::effectiveOpPostCopy(const TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpPostCopy))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpPostCopy);
}

const SymbolFunction* SymbolStruct::effectiveOpPostMove(const TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* wrapper = findGeneratedLifecycleWrapper(ctx, *this, SpecOpKind::OpPostMove))
        return wrapper;

    return resolvedLifecycleFunction(ctx, *this, SpecOpKind::OpPostMove);
}

void SymbolStruct::setGenericRoot(bool value) noexcept
{
    if (value)
        addExtraFlag(SymbolStructFlagsE::GenericRoot);
    else
        removeExtraFlag(SymbolStructFlagsE::GenericRoot);
}

void SymbolStruct::setGenericInstance(SymbolStruct* root) noexcept
{
    if (root)
    {
        addExtraFlag(SymbolStructFlagsE::GenericInstance);
        ensureGenericData().rootSym = root;
    }
    else
    {
        removeExtraFlag(SymbolStructFlagsE::GenericInstance);
        if (auto* data = genericData())
            data->rootSym = nullptr;
    }
}

bool SymbolStruct::sameGenericFamily(const SymbolStruct& other) const noexcept
{
    if (this == &other)
        return true;

    return genericRootOrSelf() == other.genericRootOrSelf();
}

SymbolStruct* SymbolStruct::genericRootOrSelf() noexcept
{
    SymbolStruct* root = genericRootSym();
    SWC_ASSERT(root != nullptr || !isGenericInstance());
    return root ? root : this;
}

const SymbolStruct* SymbolStruct::genericRootOrSelf() const noexcept
{
    const SymbolStruct* root = genericRootSym();
    SWC_ASSERT(root != nullptr || !isGenericInstance());
    return root ? root : this;
}

SymbolStruct* SymbolStruct::genericRootSym() noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

const SymbolStruct* SymbolStruct::genericRootSym() const noexcept
{
    if (const auto* data = genericData())
        return data->rootSym;
    return nullptr;
}

SymbolStruct::GenericData* SymbolStruct::genericData() const noexcept
{
    return genericData_.load(std::memory_order_acquire);
}

SymbolStruct::GenericData& SymbolStruct::ensureGenericData() const noexcept
{
    if (auto* data = genericData())
        return *data;

    auto* newData  = heapNew<GenericData>();
    auto* expected = static_cast<GenericData*>(nullptr);
    if (!genericData_.compare_exchange_strong(expected, newData, std::memory_order_acq_rel, std::memory_order_acquire))
    {
        heapDelete(newData);
        return *expected;
    }

    return *newData;
}

GenericInstanceStorage& SymbolStruct::genericInstanceStorage() noexcept
{
    return ensureGenericData().instances;
}

const GenericInstanceStorage& SymbolStruct::genericInstanceStorage() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    return data->instances;
}

bool SymbolStruct::tryGetGenericInstanceArgs(const SymbolStruct& instance, SmallVector<GenericInstanceKey>& outArgs) const
{
    if (const auto* data = genericData())
        return data->instances.tryGetArgs(instance, outArgs);
    return false;
}

bool SymbolStruct::tryGetGenericInstanceArgs(SmallVector<GenericInstanceKey>& outArgs) const
{
    if (!isGenericInstance())
        return false;

    const SymbolStruct* root = genericRootSym();
    SWC_ASSERT(root != nullptr);
    return root && root->tryGetGenericInstanceArgs(*this, outArgs);
}

void SymbolStruct::setGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    auto&              data     = ensureGenericData();
    const TaskContext* expected = nullptr;
    const bool         done     = data.completionOwner.compare_exchange_strong(expected, &ctx, std::memory_order_acq_rel);
    SWC_ASSERT(done || expected == &ctx);
}

bool SymbolStruct::isGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    const auto* data = genericData();
    return data && data->completionOwner.load(std::memory_order_acquire) == &ctx;
}

bool SymbolStruct::tryStartGenericCompletion(const TaskContext& ctx) const noexcept
{
    SWC_ASSERT(isGenericCompletionOwner(ctx));
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousState = data->completionState.fetch_add(1, std::memory_order_acq_rel);
    SWC_ASSERT((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != K_GENERIC_COMPLETION_DEPTH_MASK);
    if ((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != 0)
    {
        data->completionState.fetch_sub(1, std::memory_order_acq_rel);
        return false;
    }

    return true;
}

void SymbolStruct::finishGenericCompletion() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    const auto previousState = data->completionState.fetch_sub(1, std::memory_order_acq_rel);
    SWC_ASSERT((previousState & K_GENERIC_COMPLETION_DEPTH_MASK) != 0);
}

bool SymbolStruct::isGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    return data && (data->completionState.load(std::memory_order_acquire) & K_GENERIC_NODE_COMPLETED_MASK) != 0;
}

void SymbolStruct::setGenericNodeCompleted() const noexcept
{
    const auto* data = genericData();
    SWC_ASSERT(data != nullptr);
    data->completionState.fetch_or(K_GENERIC_NODE_COMPLETED_MASK, std::memory_order_acq_rel);
}

bool SymbolStruct::tryMarkGeneratedLifecycleFunctions() const noexcept
{
    bool expected = false;
    return generatedLifecycleDone_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

bool SymbolStruct::tryMarkGeneratedOperators() const noexcept
{
    bool expected = false;
    return generatedOperatorsDone_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

SWC_END_NAMESPACE();
