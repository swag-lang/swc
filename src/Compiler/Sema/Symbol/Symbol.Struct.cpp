#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/GenericInstanceStorage.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Interface.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/SymbolGenericData.h"
#include "Compiler/Sema/Symbol/SymbolOrder.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/PointerSet.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isConcreteStructLayoutPending(const SymbolStruct& symbolStruct)
    {
        return !symbolStruct.isGenericRoot() || symbolStruct.isGenericInstance();
    }

    // Concrete structs must have nonzero layout values after layout completes.
    // Generic roots legitimately report zero.
    uint64_t checkedStructLayoutValue(const SymbolStruct& symbolStruct, const uint64_t value, const char* what)
    {
        if (!isConcreteStructLayoutPending(symbolStruct))
            return 0;

#if SWC_DEV_MODE
        // The detail below is tuned for races and missing waits in the sema pipeline.
        if (!value)
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
            swcAssertDetail(what, __FILE__, __LINE__, detail.view());
        }
#else
        SWC_UNUSED(what);
#endif

        SWC_ASSERT(value != 0);
        return value;
    }

    uint64_t checkedStructLayoutSize(const SymbolStruct& symbolStruct, const uint64_t sizeInBytes)
    {
        return checkedStructLayoutValue(symbolStruct, sizeInBytes, "sizeInBytes != 0");
    }

    uint32_t checkedStructLayoutAlignment(const SymbolStruct& symbolStruct, const uint32_t alignment)
    {
        return static_cast<uint32_t>(checkedStructLayoutValue(symbolStruct, alignment, "alignment != 0"));
    }

    bool isRuntimeReflectedMethod(const SymbolFunction& symFunc)
    {
        // Publish only callable, concrete methods so reflection cannot expose dangling
        // entries or incomplete signatures.
        if (symFunc.isIgnored() || symFunc.isAttribute() || symFunc.isEmpty())
            return false;

        // Check atomic completion flags before reading attributes, which may still be
        // changing during semantic analysis.
        if (!symFunc.isDeclared() || !symFunc.isTyped())
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

    bool isSwagAttribute(const TaskContext& ctx, const AttributeInstance& attribute, const std::string_view attrName)
    {
        return attribute.symbol && attribute.symbol->inSwagNamespace(ctx) && attribute.symbol->name(ctx) == attrName;
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

        // Generated wrappers may register before explicit methods complete. Prefer a
        // completed user-visible overload before falling back to the registered pointer.
        for (const SymbolFunction* symFunc : ownerStruct.declaredMethods())
        {
            if (!symFunc || symFunc->isIgnored())
                continue;

            // Attributes and the declaration context are published by semantic completion.
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;

            if (symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
                continue;
            if (const SymbolImpl* symImpl = symFunc->declImplContext(); symImpl && symImpl->isForInterface())
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

            // The completion flags are atomic and gate the rest: a method whose sema is still
            // running may have its attribute list mutated concurrently, so it must not be read.
            if (!symFunc->isDeclared() || !symFunc->isTyped() || !symFunc->isSemaCompleted())
                continue;

            if (!symFunc->attributes().hasRtFlag(RtAttributeFlagsE::Implicit))
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
        MixedRequiringInit,
        AllZero,
        RequiresInit,
    };

    ImplicitDefaultKind classifyTypeImplicitDefault(Sema& sema, TypeRef typeRef);
    ImplicitDefaultKind classifyConstantImplicitDefault(Sema& sema, TypeRef typeRef, ConstantRef cstRef);

    Result waitTypeImplicitDefaultReadyRec(Sema& sema, TypeRef typeRef, AstNodeRef waitNodeRef, WalkPath<TypeRef>& visited)
    {
        if (typeRef.isInvalid() || !visited.insert(typeRef))
            return Result::Continue;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isNonNullable())
        {
            visited.erase(typeRef);
            return Result::Continue;
        }

        auto result = Result::Continue;
        if (type.isAlias())
        {
            result = sema.waitSemaCompleted(&type, waitNodeRef);
            if (result == Result::Continue)
                result = waitTypeImplicitDefaultReadyRec(sema, type.payloadSymAlias().underlyingTypeRef(), waitNodeRef, visited);
        }
        else if (type.isEnum())
        {
            result = sema.waitSemaCompleted(&type, waitNodeRef);
            if (result == Result::Continue)
                result = waitTypeImplicitDefaultReadyRec(sema, type.payloadSymEnum().underlyingTypeRef(), waitNodeRef, visited);
        }
        else if (type.isStruct())
            result = sema.waitSemaCompleted(&type, waitNodeRef);
        else if (type.isArray())
            result = waitTypeImplicitDefaultReadyRec(sema, type.payloadArrayElemTypeRef(), waitNodeRef, visited);
        else if (type.isAggregate())
        {
            for (const TypeRef childTypeRef : type.payloadAggregate().types)
            {
                result = waitTypeImplicitDefaultReadyRec(sema, childTypeRef, waitNodeRef, visited);
                if (result != Result::Continue)
                    break;
            }
        }

        visited.erase(typeRef);
        return result;
    }

    bool implicitDefaultKindRequiresInit(const ImplicitDefaultKind kind)
    {
        return kind == ImplicitDefaultKind::RequiresInit || kind == ImplicitDefaultKind::MixedRequiringInit;
    }

    struct ImplicitDefaultSummary
    {
        bool allZero      = true;
        bool requiresInit = false;

        ImplicitDefaultKind lastKind = ImplicitDefaultKind::AllZero;

        void add(ImplicitDefaultKind childKind)
        {
            allZero &= childKind == ImplicitDefaultKind::AllZero;
            requiresInit |= implicitDefaultKindRequiresInit(childKind);
            lastKind = childKind;
        }

        ImplicitDefaultKind result(size_t childCount) const
        {
            if (allZero)
                return ImplicitDefaultKind::AllZero;

            if (requiresInit)
                return childCount == 1 && lastKind == ImplicitDefaultKind::RequiresInit ? ImplicitDefaultKind::RequiresInit : ImplicitDefaultKind::MixedRequiringInit;

            return ImplicitDefaultKind::Mixed;
        }
    };

    ImplicitDefaultKind classifyConstantChildrenImplicitDefault(Sema& sema, const std::span<const ConstantRef> childValues, const std::span<const TypeRef> childTypes)
    {
        if (childValues.size() != childTypes.size())
            return ImplicitDefaultKind::Mixed;

        ImplicitDefaultSummary summary;

        for (size_t i = 0; i < childValues.size(); ++i)
            summary.add(classifyConstantImplicitDefault(sema, childTypes[i], childValues[i]));

        return summary.result(childValues.size());
    }

    ImplicitDefaultKind classifyRepeatedConstantImplicitDefault(Sema& sema, const std::span<const ConstantRef> childValues, const TypeRef childTypeRef)
    {
        ImplicitDefaultSummary summary;

        for (const ConstantRef childValueRef : childValues)
            summary.add(classifyConstantImplicitDefault(sema, childTypeRef, childValueRef));

        return summary.result(childValues.size());
    }

    ImplicitDefaultKind classifyConstantImplicitDefault(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
    {
        if (cstRef.isInvalid())
            return ImplicitDefaultKind::Mixed;

        const ConstantValue& cst  = sema.cstMgr().get(cstRef);
        const TypeInfo&      type = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef);

        if (cst.isEnumValue())
        {
            if (!type.isIntLike())
                return ImplicitDefaultKind::Mixed;

            return classifyConstantImplicitDefault(sema, type.typeRef(), cst.getEnumValue());
        }

        if (cst.isStruct())
            return std::ranges::all_of(cst.getStruct(), [](const std::byte value) { return value == std::byte{}; }) ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (cst.isArray())
            return std::ranges::all_of(cst.getArray(), [](const std::byte value) { return value == std::byte{}; }) ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (!type.sizeOf(sema.ctx()))
            return ImplicitDefaultKind::AllZero;

        if (cst.isNull())
        {
            if (type.isPointerOrReference() || type.isAnyString() || type.isSlice() || type.isAny() || type.isInterface() ||
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
            return cst.isSlice() && cst.getSliceCount() == 0 && !cst.getSlice().data() ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

        if (type.isPointerOrReference() || type.isTypeInfo() || type.isFunction())
        {
            if (cst.isValuePointer())
                return cst.getValuePointer() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

            if (cst.isBlockPointer())
                return cst.getBlockPointer() == 0 ? ImplicitDefaultKind::AllZero : ImplicitDefaultKind::Mixed;

            return ImplicitDefaultKind::Mixed;
        }

        if (type.isArray() && cst.isAggregateArray())
        {
            uint64_t totalCount = type.arrayTotalElementCount();
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
        ImplicitDefaultSummary summary;

        for (const TypeRef childTypeRef : childTypes)
            summary.add(classifyTypeImplicitDefault(sema, childTypeRef));

        return summary.result(childTypes.size());
    }

    ImplicitDefaultKind classifyTypeImplicitDefault(Sema& sema, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return ImplicitDefaultKind::Mixed;

        const TypeInfo& declaredType = sema.typeMgr().get(typeRef);
        if (declaredType.isNonNullable())
            return ImplicitDefaultKind::RequiresInit;

        const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(sema.ctx());
        if (type.isNonNullable())
            return ImplicitDefaultKind::RequiresInit;

        if (type.isStruct())
        {
            const auto& symStruct = type.payloadSymStruct();
            symStruct.computeImplicitDefaultFlags(sema);

            if (symStruct.requiresExplicitInitialization())
                return ImplicitDefaultKind::MixedRequiringInit;
            if (symStruct.hasImplicitAllZeroDefault())
                return ImplicitDefaultKind::AllZero;

            return ImplicitDefaultKind::Mixed;
        }

        if (type.isArray())
        {
            if (std::ranges::any_of(type.payloadArrayDims(), [](const uint64_t dim) { return dim == 0; }))
                return ImplicitDefaultKind::AllZero;

            return classifyTypeImplicitDefault(sema, type.payloadArrayElemTypeRef());
        }

        if (type.isAggregate())
            return classifyAggregateTypeImplicitDefault(sema, type.payloadAggregate().types);

        return ImplicitDefaultKind::AllZero;
    }

    Result lowerTypeImplicitDefaultBytesRec(Sema& sema, std::span<std::byte> dstBytes, const TypeInfo& declaredType)
    {
        // Non-null types reached here are 'late' fields (fields requiring explicit
        // initialization were skipped by the caller): their default is the null
        // 'unset' state. The destination buffer is not always pre-zeroed.
        if (declaredType.isNonNullable())
        {
            if (!dstBytes.empty())
                std::memset(dstBytes.data(), 0, dstBytes.size());

            return Result::Continue;
        }

        const TypeInfo& type = declaredType.unwrapAliasEnumTypeOrSelf(sema.ctx());
        if (type.isNonNullable())
        {
            if (!dstBytes.empty())
                std::memset(dstBytes.data(), 0, dstBytes.size());

            return Result::Continue;
        }

        if (type.isStruct())
        {
            for (const SymbolVariable* field : type.payloadSymStruct().fields())
            {
                if (!field)
                    continue;
                if (SymbolStruct::fieldRequiresExplicitInitialization(sema, *field))
                    continue;

                const TypeRef   fieldTypeRef = field->typeRef();
                const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
                const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
                const uint64_t  fieldOffset  = field->offset();
                SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());

                const std::span<std::byte> fieldBytes = dstBytes.subspan(fieldOffset, fieldSize);
                if (const ConstantRef valueRef = field->defaultValueRef(); valueRef.isValid())
                {
                    SWC_RESULT(ConstantLower::lowerToBytes(sema, fieldBytes, valueRef, fieldType));
                }
                else if (fieldSize)
                {
                    SWC_RESULT(lowerTypeImplicitDefaultBytesRec(sema, fieldBytes, fieldType));
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

            uint64_t totalCount = type.arrayTotalElementCount();

            for (uint64_t idx = 0; idx < totalCount; ++idx)
                SWC_RESULT(lowerTypeImplicitDefaultBytesRec(sema, dstBytes.subspan(idx * elemSize, elemSize), elemType));

            return Result::Continue;
        }

        if (!dstBytes.empty())
            std::memset(dstBytes.data(), 0, dstBytes.size());

        return Result::Continue;
    }

    ImplicitDefaultKind classifyFieldImplicitDefault(Sema& sema, const SymbolVariable& field)
    {
        // A 'late' field is typed non-null but its storage legitimately starts
        // null: it never blocks default initialization.
        if (field.hasExtraFlag(SymbolVariableFlagsE::LateInit))
            return ImplicitDefaultKind::AllZero;

        const ConstantRef valueRef = field.defaultValueRef();
        if (valueRef.isValid())
            return classifyConstantImplicitDefault(sema, field.typeRef(), valueRef);

        return classifyTypeImplicitDefault(sema, field.typeRef());
    }

    void appendImplFunctions(std::vector<SymbolFunction*>& out, const SymbolImplList& implList)
    {
        std::vector<const Symbol*> symbols;
        for (const SymbolImpl* symImpl : implList)
        {
            if (!symImpl)
                continue;

            symImpl->getAllFunctions(symbols);

            for (const Symbol* symbol : symbols)
            {
                if (!symbol)
                    continue;

                out.push_back(const_cast<SymbolFunction*>(&symbol->cast<SymbolFunction>()));
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

    // The first constant parameter of a 'Swag' attribute named 'attrName' that 'accepts' takes.
    template<typename F>
    const ConstantValue* findSwagAttributeParam(TaskContext& ctx, std::span<const AttributeInstance> attributes, const std::string_view attrName, F&& accepts)
    {
        for (const AttributeInstance& attribute : attributes)
        {
            if (!isSwagAttribute(ctx, attribute, attrName))
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid())
                    continue;

                const ConstantValue& cst = ctx.cstMgr().get(param.valueCstRef);
                if (accepts(cst))
                    return &cst;
            }
        }

        return nullptr;
    }

    bool tryGetSwagLayoutAttributeValue(uint32_t& outValue, TaskContext& ctx, std::span<const AttributeInstance> attributes, const std::string_view attrName)
    {
        const ConstantValue* cst = findSwagAttributeParam(ctx, attributes, attrName, [](const ConstantValue& value) { return value.isInt(); });
        outValue                 = cst ? static_cast<uint32_t>(cst->getInt().as64()) : 0;
        return cst != nullptr;
    }

    bool tryGetFieldOffsetAttributeValue(std::string_view& outValue, TaskContext& ctx, std::span<const AttributeInstance> attributes)
    {
        const ConstantValue* cst = findSwagAttributeParam(ctx, attributes, "Offset", [](const ConstantValue& value) { return value.isString(); });
        outValue                 = cst ? cst->getString() : std::string_view{};
        return cst != nullptr;
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

    uint32_t effectiveFieldAlignment(TaskContext& ctx, const TypeInfo& fieldType, std::span<const AttributeInstance> fieldAttributes, const uint32_t structPack)
    {
        uint32_t alignOf = std::max<uint32_t>(fieldType.alignOf(ctx), 1);

        if (structPack != 0)
            alignOf = std::min(alignOf, structPack);

        uint32_t fieldAlign = 0;
        if (tryGetSwagLayoutAttributeValue(fieldAlign, ctx, fieldAttributes, "Align") && fieldAlign != 0)
            alignOf = std::max(alignOf, fieldAlign);

        return std::max<uint32_t>(alignOf, 1);
    }

    bool resolveUsingFieldPathRec(const TaskContext& ctx, const SymbolStruct& currentStruct, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps, PointerSet<const SymbolStruct>& visited)
    {
        SWC_ASSERT(&currentStruct != &targetStruct);
        if (!visited.insert(&currentStruct))
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
            if (usingTargetStruct == &targetStruct || resolveUsingFieldPathRec(ctx, *usingTargetStruct, targetStruct, outSteps, visited))
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
    if (impls_.append(sema.ctx(), symImpl, [&] { symImpl.setSymStruct(this); }))
        sema.compiler().notifyAlive();
}

std::vector<SymbolFunction*> SymbolStruct::declaredMethods() const
{
    std::vector<SymbolFunction*> result;
    appendImplFunctions(result, impls());
    appendImplFunctions(result, interfaces());
    std::ranges::sort(result, SymbolOrder::beforeToken);
    return result;
}

Result SymbolStruct::waitPendingImplMembers(Sema& sema, const SourceCodeRef& codeRef) const
{
    if (sema.compiler().pendingImplRegistrations(idRef()) != 0)
        return sema.waitImplRegistrations(idRef(), codeRef);

    // A completed struct has its impls registered, but their generated members may still
    // be pending. The current impl cannot wait for its own body to finish.
    const SymbolImpl* currentImpl = sema.frame().currentImpl();
    for (const SymbolImpl* symImpl : impls())
    {
        if (!symImpl || symImpl->isIgnored() || symImpl == currentImpl)
            continue;

        if (!symImpl->isSemaCompleted())
            return sema.waitSemaCompleted(symImpl, codeRef);
    }

    return Result::Continue;
}

std::vector<SymbolFunction*> SymbolStruct::methods() const
{
    // A generic root can be sema-complete before its impl methods are specialized.
    // Their signatures still depend on generic context and cannot be reflected safely.
    if (isGenericRoot() && !isGenericInstance())
        return {};

    std::vector<SymbolFunction*> result;
    for (SymbolFunction* symFunc : declaredMethods())
    {
        if (!symFunc || !isRuntimeReflectedMethod(*symFunc))
            continue;

        result.push_back(symFunc);
    }

    std::ranges::sort(result, SymbolOrder::beforeToken);
    return result;
}

bool SymbolStruct::exportsRuntimeMethods(const TaskContext& ctx) const
{
    for (const AttributeInstance& attribute : attributes().attributes)
    {
        if (isSwagAttribute(ctx, attribute, "ExportType"))
            return true;
    }

    return false;
}

void SymbolStruct::addInterface(SymbolImpl& symImpl)
{
    const std::unique_lock lk(mutexInterfaces_);
    if (!interfacesSet_.insert(&symImpl))
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

    // Publish the interface scope here so StructName.InterfaceName.Symbol resolves.
    const Symbol* inserted = addSingleSymbol(sema.ctx(), &symImpl);
    if (inserted != &symImpl)
        return SemaError::raiseAlreadyDefined(sema, &symImpl, inserted);

    symImpl.setSymStruct(this);
    interfaces_.push_back(&symImpl);
    interfacesSet_.insert(&symImpl);
    sema.compiler().notifyAlive();

    return Result::Continue;
}

SymbolImplList SymbolStruct::interfaces() const
{
    const std::shared_lock lock(mutexInterfaces_);
    SymbolImplList         result;
    result.assign(interfaces_.begin(), interfaces_.end());
    return result;
}

void SymbolStruct::removeIgnoredFields()
{
    // Re-entered on every post-node resume while readers may walk the published fields of a
    // typed struct: stay mutation-free when there is nothing to remove.
    if (std::erase_if(fields_, std::mem_fn(&Symbol::isIgnored)) != 0)
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

bool SymbolStruct::tryGetFieldIndexByName(size_t& outIndex, const IdentifierRef name) const noexcept
{
    const SymbolVariable* field = findFieldByName(name);
    return field && tryGetFieldIndex(outIndex, *field);
}

const SymbolVariable* SymbolStruct::findFieldByName(const IdentifierRef name) const noexcept
{
    if (fields_.size() > 32 && isSemaCompleted())
    {
        // Completed structs have removed ignored fields and checked duplicate names. Reuse
        // their symbol index, but keep the scan for homonyms or synthetic, unregistered fields.
        const Symbol* symbol = findFirstSymbol(name, true);
        const auto*   field  = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
        if (field && fieldIndexMap_.contains(field))
            return field;
    }

    for (const SymbolVariable* field : fields_)
    {
        if (field && field->idRef() == name)
            return field;
    }

    return nullptr;
}

const TypeInfo* SymbolStruct::dynamicStorageLeafType(const TaskContext& ctx, const TypeInfo& rootType)
{
    const TypeInfo* type = &rootType;
    while (true)
    {
        if (const TypeInfo* storageType = type->unwrapAliasEnumType(ctx))
            type = storageType;

        if (!type->isArray())
            break;

        type = &ctx.typeMgr().get(type->payloadArrayElemTypeRef());
    }

    return type->isStruct() && type->payloadSymStruct().hasDynamicStorage() ? type : nullptr;
}

Result SymbolStruct::prepareDynamicMetadata(Sema& sema, TypeRef typeRef)
{
    const TypeInfo* type = dynamicStorageLeafType(sema.ctx(), sema.typeMgr().get(typeRef));
    if (!type)
        return Result::Continue;

    const SymbolStruct& symStruct = type->payloadSymStruct();
    if (symStruct.isDynamic())
    {
        ConstantRef typeInfoRef = ConstantRef::invalid();
        SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoRef, type->typeRef(), sema.curNodeRef()));
    }

    for (const SymbolVariable* field : symStruct.fields())
        SWC_RESULT(prepareDynamicMetadata(sema, field->typeRef()));

    return Result::Continue;
}

Result SymbolStruct::initializeDynamicIdentityBytes(Sema& sema, std::span<std::byte> bytes, const TypeInfo& originalType)
{
    if (!typeHasDynamicStorage(sema.ctx(), originalType))
        return Result::Continue;

    const TypeInfo& type    = originalType.unwrapAliasEnumTypeOrSelf(sema.ctx());
    const TypeRef   typeRef = type.typeRef();
    if (type.isArray())
    {
        const TypeInfo& elementType = sema.typeMgr().get(type.payloadArrayElemTypeRef());
        const uint64_t  elementSize = elementType.sizeOf(sema.ctx());
        for (size_t offset = 0; elementSize && offset < bytes.size(); offset += elementSize)
            SWC_RESULT(initializeDynamicIdentityBytes(sema, bytes.subspan(offset, elementSize), elementType));

        return Result::Continue;
    }

    if (!type.isStruct() || !type.payloadSymStruct().hasDynamicStorage())
        return Result::Continue;

    const SymbolStruct& symStruct = type.payloadSymStruct();
    for (const SymbolVariable* field : symStruct.fields())
    {
        const TypeInfo& fieldType = field->typeInfo(sema.ctx());
        const uint64_t  fieldSize = fieldType.sizeOf(sema.ctx());
        SWC_RESULT(initializeDynamicIdentityBytes(sema, bytes.subspan(field->offset(), fieldSize), fieldType));
    }

    if (symStruct.isDynamic())
    {
        ConstantRef typeInfoRef = ConstantRef::invalid();
        SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoRef, typeRef, sema.curNodeRef()));

        const auto* runtimeType = reinterpret_cast<const Runtime::TypeInfoStruct*>(sema.cstMgr().get(typeInfoRef).getValuePointer());
        const auto  slots       = symStruct.dynamicSlotOffsets();
        SWC_ASSERT(runtimeType->dynamicSlots.count == slots.size());

        for (size_t i = 0; i < slots.size(); ++i)
        {
            const Runtime::DynamicStructInfo* descriptor = runtimeType->dynamicSlots.ptr + i;
            std::memcpy(bytes.data() + slots[i], &descriptor, sizeof(descriptor));
        }
    }

    return Result::Continue;
}

Result SymbolStruct::computeDefaultValue(Sema& sema, TypeRef typeRef, ConstantRef& outRef)
{
    outRef = ConstantRef::invalid();
    computeImplicitDefaultFlags(sema);
    if (requiresExplicitInitialization() || hasRuntimeImplicitDefault())
        return Result::Continue;

    if (hasImplicitAllZeroDefault())
    {
        outRef = sema.cstMgr().addZeroPayloadConstant(sema.ctx(), typeRef);
        return Result::Continue;
    }

    // Type-info generation can park. Complete it before entering the once-only
    // default publisher, whose callback must never retain a partially built value.
    SWC_RESULT(prepareDynamicMetadata(sema, typeRef));

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

        const TypeInfo& defaultType = ctx.typeMgr().get(typeRef);
        if (ConstantHelpers::typeHasUnionStorage(ctx, defaultType))
        {
            defaultStructCst_ = ConstantHelpers::materializeAggregateConstructionConstant(sema, typeRef);
            if (defaultStructCst_.isInvalid())
            {
                addExtraFlag(SymbolStructFlagsE::DefaultRuntime);
                return;
            }
        }
        else
        {
            std::vector     buffer(structSize, std::byte{0});
            const std::span bytes{buffer.data(), buffer.size()};
            SWC_INTERNAL_CHECK(lowerTypeImplicitDefaultBytesRec(sema, bytes, defaultType) == Result::Continue);
            SWC_INTERNAL_CHECK(initializeDynamicIdentityBytes(sema, bytes, defaultType) == Result::Continue);
            defaultStructCst_ = ConstantHelpers::materializeStaticPayloadConstant(sema, typeRef, std::span{bytes.data(), bytes.size()});
        }

        SWC_ASSERT(defaultStructCst_.isValid());
    });

    outRef = defaultStructCst_;
    return Result::Continue;
}

void SymbolStruct::computeImplicitDefaultFlags(Sema& sema) const
{
    std::call_once(implicitDefaultFlagsOnce_, [&] {
        auto* self = const_cast<SymbolStruct*>(this);
        self->addExtraFlag(SymbolStructFlagsE::DefaultClassified);

        for (const AttributeInstance& attribute : attributes().attributes)
        {
            if (!isSwagAttribute(sema.ctx(), attribute, "Opaque"))
                continue;

            for (const AttributeParamInstance& param : attribute.params)
            {
                if (!param.valueCstRef.isValid() || !sema.cstMgr().get(param.valueCstRef).getBool())
                    continue;

                if (param.nameIdRef == sema.idMgr().addIdentifier("runtimeDefault"))
                    self->addExtraFlag(SymbolStructFlagsE::DefaultRuntime);
                if (param.nameIdRef == sema.idMgr().addIdentifier("requiresInit"))
                    self->addExtraFlag(SymbolStructFlagsE::DefaultRequiresInit);
            }
        }

        // No case is the natural one: a tagged union is always built from a named case, so a
        // default can only come from the declaration that holds it.
        if (isTagged())
        {
            self->addExtraFlag(SymbolStructFlagsE::DefaultRequiresInit);
            return;
        }

        if (fields_.empty() && !isDynamic() && !hasRuntimeImplicitDefault() && !requiresExplicitInitialization())
        {
            self->addExtraFlag(SymbolStructFlagsE::DefaultAllZero);
            return;
        }

        bool allZero      = !isDynamic() && !hasRuntimeImplicitDefault() && !requiresExplicitInitialization();
        bool requiresInit = requiresExplicitInitialization();

        for (const SymbolVariable* field : fields_)
        {
            if (!field)
                continue;

            const ImplicitDefaultKind fieldKind = classifyFieldImplicitDefault(sema, *field);

            allZero &= fieldKind == ImplicitDefaultKind::AllZero;
            requiresInit |= implicitDefaultKindRequiresInit(fieldKind);
            if (field->defaultValueRef().isInvalid() && typeHasRuntimeImplicitDefault(sema, field->typeRef()))
            {
                self->addExtraFlag(SymbolStructFlagsE::DefaultRuntime);
                allZero = false;
            }
        }

        if (allZero)
            self->addExtraFlag(SymbolStructFlagsE::DefaultAllZero);

        if (requiresInit)
            self->addExtraFlag(SymbolStructFlagsE::DefaultRequiresInit);
    });
}

bool SymbolStruct::typeHasRuntimeImplicitDefault(Sema& sema, TypeRef typeRef)
{
    const TypeInfo& type = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef);
    if (type.isArray())
    {
        if (std::ranges::any_of(type.payloadArrayDims(), [](uint64_t count) { return count == 0; }))
            return false;

        return typeHasRuntimeImplicitDefault(sema, type.payloadArrayElemTypeRef());
    }

    if (!type.isStruct())
        return false;

    const SymbolStruct& symStruct = type.payloadSymStruct();
    symStruct.computeImplicitDefaultFlags(sema);
    return symStruct.hasRuntimeImplicitDefault();
}

bool SymbolStruct::typeRequiresExplicitInitialization(Sema& sema, TypeRef typeRef)
{
    return implicitDefaultKindRequiresInit(classifyTypeImplicitDefault(sema, typeRef));
}

bool SymbolStruct::typeHasCompleteImplicitDefault(Sema& sema, TypeRef typeRef)
{
    const ImplicitDefaultKind kind = classifyTypeImplicitDefault(sema, typeRef);
    return !implicitDefaultKindRequiresInit(kind);
}

Result SymbolStruct::waitTypeImplicitDefaultReady(Sema& sema, const TypeRef typeRef, const AstNodeRef waitNodeRef)
{
    WalkPath<TypeRef> visited;
    return waitTypeImplicitDefaultReadyRec(sema, typeRef, waitNodeRef, visited);
}

bool SymbolStruct::typeHasAllZeroImplicitDefault(Sema& sema, const TypeRef typeRef)
{
    return classifyTypeImplicitDefault(sema, typeRef) == ImplicitDefaultKind::AllZero;
}

bool SymbolStruct::fieldRequiresExplicitInitialization(Sema& sema, const SymbolVariable& field)
{
    return implicitDefaultKindRequiresInit(classifyFieldImplicitDefault(sema, field));
}

Result SymbolStruct::lowerTypeImplicitDefaultBytes(Sema& sema, const std::span<std::byte> dstBytes, const TypeRef typeRef)
{
    const TypeInfo& type = sema.typeMgr().get(typeRef);
    SWC_RESULT(lowerTypeImplicitDefaultBytesRec(sema, dstBytes, type));
    return initializeDynamicIdentityBytes(sema, dstBytes, type);
}

Result SymbolStruct::resolveImplicitDefaultValueRef(Sema& sema, TypeRef typeRef, ConstantRef& outRef) const
{
    return const_cast<SymbolStruct*>(this)->computeDefaultValue(sema, typeRef, outRef);
}

namespace
{
    constexpr uint32_t K_GENERIC_COMPLETION_DEPTH_MASK = 0x7FFFFFFFu;
    constexpr uint32_t K_GENERIC_NODE_COMPLETED_MASK   = 1u << 31;
}

struct SymbolStruct::GenericData
{
    // Keep generic-only state off the main symbol so non-generic structs stay compact.
    GenericInstanceOrigin  origin;
    GenericInstanceStorage instances;

    std::atomic<const TaskContext*> completionOwner = nullptr;
    mutable std::atomic<uint32_t>   completionState = 0;

    SymbolStruct* rootSym = nullptr;

    mutable std::recursive_mutex                  evalRunMutex;
    mutable std::shared_mutex                     evalCacheMutex;
    std::vector<SymbolInternal::GenericEvalEntry> evalCache;
};

const SymbolImpl* SymbolStruct::findInterfaceImpl(IdentifierRef interfaceIdRef) const
{
    const std::shared_lock lk(mutexInterfaces_);
    for (const auto* itfImpl : interfaces_)
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
    return findInterfaceImplOrUsingFields(sema.ctx(), itf) != nullptr;
}

const SymbolImpl* SymbolStruct::findInterfaceImplOrUsingFields(const TaskContext& ctx, const SymbolInterface& itf) const
{
    if (const SymbolImpl* impl = findInterfaceImpl(itf.idRef()))
        return impl;

    if (!mayHaveUsingField())
        return nullptr;

    for (const Symbol* field : fields_)
    {
        if (!field)
            continue;

        const auto& symVar = field->cast<SymbolVariable>();
        if (!symVar.isUsingField())
            continue;

        const SymbolStruct* targetStruct = symVar.usingTargetStruct(ctx);
        if (targetStruct)
        {
            if (const SymbolImpl* impl = targetStruct->findInterfaceImpl(itf.idRef()))
                return impl;
        }
    }

    return nullptr;
}

uint64_t SymbolStruct::sizeOf() const
{
    return checkedStructLayoutSize(*this, sizeInBytes_.load(std::memory_order_acquire));
}

bool SymbolStruct::hasConcreteLayout() const noexcept
{
    if (!isConcreteStructLayoutPending(*this))
        return true;

    return sizeInBytes_.load(std::memory_order_acquire) != 0 && alignment_.load(std::memory_order_acquire) != 0;
}

uint32_t SymbolStruct::alignment() const
{
    return checkedStructLayoutAlignment(*this, alignment_.load(std::memory_order_acquire));
}

bool SymbolStruct::resolveUsingFieldPath(const TaskContext& ctx, const SymbolStruct& targetStruct, SmallVector<SymbolStructUsingPathStep>& outSteps) const
{
    outSteps.clear();
    if (this == &targetStruct)
        return true;

    PointerSet<const SymbolStruct> visited;
    return resolveUsingFieldPathRec(ctx, *this, targetStruct, outSteps, visited);
}

// A struct starts with 'base' when it is 'base' or embeds it by value through first fields only:
// a pointer to it is then a pointer to 'base', unchanged. Needs the layout of both.
bool SymbolStruct::startsWith(const TaskContext& ctx, const SymbolStruct& base) const
{
    SmallVector<SymbolStructUsingPathStep> usingPath;
    if (!resolveUsingFieldPath(ctx, base, usingPath))
        return false;

    for (const SymbolStructUsingPathStep& step : usingPath)
    {
        if (step.isPointer || step.field->offset() != 0)
            return false;
    }

    return true;
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

        // Function values have pointer/closure storage; signature types do not affect
        // this layout. Waiting for func(Self) would create a false dependency cycle.
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

    // Published before the field so a reader that sees the field also sees the flag.
    if (sym->isUsingField())
        addExtraFlag(SymbolStructFlagsE::UsingField);

    [[maybe_unused]] const bool inserted = fieldIndexMap_.emplace(sym, fields_.size()).second;
    SWC_ASSERT(inserted);
    fields_.push_back(sym);
}

uint32_t SymbolStruct::taggedTagSize(TaskContext& ctx) const
{
    SWC_ASSERT(isTagged());
    return static_cast<uint32_t>(ctx.typeMgr().get(taggedTypeRef_).sizeOf(ctx));
}

void SymbolStruct::addTaggedCase(const SymbolVariable& member, std::span<ConstantRef> values)
{
    // A replayed body declares the same member again.
    for (SymbolStructTaggedCase& taggedCase : taggedCases_)
    {
        if (taggedCase.member == &member)
        {
            taggedCase.values = values;
            return;
        }
    }

    taggedCases_.push_back({.member = &member, .values = values});
}

std::span<const ConstantRef> SymbolStruct::taggedCaseValues(const SymbolVariable& member) const noexcept
{
    for (const SymbolStructTaggedCase& taggedCase : taggedCases_)
    {
        if (taggedCase.member == &member)
            return taggedCase.values;
    }

    return {};
}

const SymbolVariable* SymbolStruct::taggedCaseMember(ConstantRef value) const noexcept
{
    for (const SymbolStructTaggedCase& taggedCase : taggedCases_)
    {
        if (std::ranges::find(taggedCase.values, value) != taggedCase.values.end())
            return taggedCase.member;
    }

    return nullptr;
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
    if (hasConcreteLayout())
        return Result::Continue;

    // Post-node semantic analysis can resume after waiting for impl registrations,
    // while other jobs already read the published layout. Compute locally and publish
    // only at the end so readers never observe partial sizes or transient zeroes.
    uint64_t sizeInBytes = 0;
    uint32_t alignment   = 1;

    uint32_t structPack  = 0;
    uint32_t structAlign = 0;

    tryGetSwagLayoutAttributeValue(structPack, ctx, attributes().attributes, "Pack");
    tryGetSwagLayoutAttributeValue(structAlign, ctx, attributes().attributes, "Align");

    SmallVector<uint64_t> fieldOffsets;
    fieldOffsets.reserve(fields_.size());
    std::vector<uint32_t> dynamicSlotOffsets;

    // The tag comes first. Every member then starts at the first offset that suits the most
    // demanding one, so the members overlap after the tag the way union members overlap at zero.
    uint64_t payloadOffset = 0;
    if (isTagged())
    {
        const TypeInfo& tagType = ctx.typeMgr().get(taggedTypeRef_);
        payloadOffset           = tagType.sizeOf(ctx);
        alignment               = std::max(alignment, tagType.alignOf(ctx));

        uint32_t payloadAlignment = 1;
        for (const SymbolVariable* field : fields_)
        {
            const AttributeList& fieldAttributes = field->attributes();
            const auto           ownAttributes   = std::span{fieldAttributes.attributes}.subspan(inheritedAttributePrefixCount(fieldAttributes, attributes()));
            payloadAlignment                     = std::max(payloadAlignment, effectiveFieldAlignment(ctx, field->typeInfo(ctx), ownAttributes, structPack));
        }

        payloadOffset += (payloadAlignment - (payloadOffset % payloadAlignment)) % payloadAlignment;
        sizeInBytes = payloadOffset;
    }

    for (SymbolVariable* field : fields_)
    {
        auto&       symVar = field->cast<SymbolVariable>();
        const auto& type   = symVar.typeInfo(ctx);

        const AttributeList& fieldAttributes = symVar.attributes();
        const auto           ownAttributes   = std::span{fieldAttributes.attributes}.subspan(inheritedAttributePrefixCount(fieldAttributes, attributes()));

        const uint64_t sizeOf  = type.sizeOf(ctx);
        const uint32_t alignOf = effectiveFieldAlignment(ctx, type, ownAttributes, structPack);

        alignment = std::max(alignment, alignOf);

        if (isUnion())
        {
            fieldOffsets.push_back(payloadOffset);
            sizeInBytes = std::max(sizeInBytes, payloadOffset + sizeOf);
        }
        else
        {
            std::string_view      offsetTargetName;
            const SymbolVariable* offsetTarget = nullptr;
            uint64_t              fieldOffset  = sizeInBytes;
            if (tryGetFieldOffsetAttributeValue(offsetTargetName, ctx, ownAttributes))
            {
                offsetTarget = findOffsetTargetField(ctx, *this, symVar, offsetTargetName);
                SWC_ASSERT(offsetTarget != nullptr);
                if (offsetTarget)
                {
                    size_t targetIndex = 0;
                    if (tryGetFieldIndex(targetIndex, *offsetTarget) && targetIndex < fieldOffsets.size())
                        fieldOffset = fieldOffsets[targetIndex];
                    else
                        fieldOffset = offsetTarget->offset();
                }
            }
            else
            {
                const uint64_t padding = (alignOf - (sizeInBytes % alignOf)) % alignOf;
                fieldOffset            = sizeInBytes + padding;
            }

            fieldOffsets.push_back(fieldOffset);
            sizeInBytes = std::max(sizeInBytes, fieldOffset + sizeOf);
        }
    }

    for (size_t i = 0; i < fields_.size(); ++i)
    {
        const SymbolVariable& field = *fields_[i];
        if (!field.isUsingField())
            continue;

        const TypeInfo& fieldType = ctx.typeMgr().unwrapAliasEnumTypeOrSelf(ctx, field.typeRef());
        if (!fieldType.isStruct())
            continue;

        for (const uint32_t slotOffset : fieldType.payloadSymStruct().dynamicSlotOffsets())
            dynamicSlotOffsets.push_back(static_cast<uint32_t>(fieldOffsets[i]) + slotOffset);
    }

    if (dynamicSlotOffsets.empty() && attributes().hasRtFlag(RtAttributeFlagsE::DynCast))
    {
        addExtraFlag(SymbolStructFlagsE::OwnDynamicSlot);
        const uint32_t slotAlignment = structPack ? std::min(structPack, static_cast<uint32_t>(alignof(void*))) : alignof(void*);

        alignment = std::max(alignment, slotAlignment);
        sizeInBytes += (slotAlignment - sizeInBytes % slotAlignment) % slotAlignment;
        dynamicSlotOffsets.push_back(static_cast<uint32_t>(sizeInBytes));
        sizeInBytes += sizeof(void*);
    }

    if (structAlign != 0)
        alignment = std::max(alignment, structAlign);

    const uint64_t padding = (alignment - (sizeInBytes % alignment)) % alignment;
    sizeInBytes            = std::max(sizeInBytes + padding, 1ULL);

    for (size_t i = 0; i < fields_.size(); ++i)
        fields_[i]->setOffset(static_cast<uint32_t>(fieldOffsets[i]));

    taggedPayloadOffset_ = static_cast<uint32_t>(payloadOffset);
    dynamicSlotOffsets_  = std::move(dynamicSlotOffsets);
    if (isDynamic())
        addExtraFlag(SymbolStructFlagsE::DynamicStorage);
    else
    {
        for (const SymbolVariable* field : fields_)
        {
            if (typeHasDynamicStorage(ctx, ctx.typeMgr().get(field->typeRef())))
            {
                addExtraFlag(SymbolStructFlagsE::DynamicStorage);
                break;
            }
        }
    }

    // Publish size last: hasConcreteLayout() uses it as the readiness gate.
    alignment_.store(alignment, std::memory_order_release);
    sizeInBytes_.store(sizeInBytes, std::memory_order_release);

    return Result::Continue;
}

SmallVector<SymbolFunction*> SymbolStruct::getSpecOp(IdentifierRef identifierRef) const
{
    SmallVector<SymbolFunction*> result;

    const std::shared_lock lk(mutexSpecOps_);
    for (SymbolFunction* symFunc : specOps_)
    {
        if (!symFunc->isIgnored() && symFunc->idRef() == identifierRef)
            result.push_back(symFunc);
    }

    return result;
}

// The 'opEquals' this struct answers '==' with. Only an overload taking a value of the struct's
// own type answers for the struct itself; one declared against another type sits beside it.
SymbolFunction* SymbolStruct::selfEqualsFunction(TaskContext& ctx) const
{
    const IdentifierRef idRef = ctx.idMgr().predefined(IdentifierManager::PredefinedName::OpEquals);
    for (SymbolFunction* symFunc : getSpecOp(idRef))
    {
        const auto& params = symFunc->parameters();
        if (params.size() >= 2 && SemaSpecOp::isOwnerStructType(ctx, *this, params[1]->typeRef()))
            return symFunc;
    }

    return nullptr;
}

Result SymbolStruct::registerSpecOp(SymbolFunction& symFunc, SpecOpKind kind)
{
    const std::unique_lock lk(mutexSpecOps_);
    if (!specOpsSet_.insert(&symFunc))
        return Result::Continue;

    specOps_.push_back(&symFunc);

    switch (kind)
    {
        case SpecOpKind::OpDrop:
            SWC_ASSERT(!opDrop());
            opDrop_.store(&symFunc, std::memory_order_release);
            break;
        case SpecOpKind::OpPostCopy:
            SWC_ASSERT(!opPostCopy());
            opPostCopy_.store(&symFunc, std::memory_order_release);
            break;
        case SpecOpKind::OpPostMove:
            SWC_ASSERT(!opPostMove());
            opPostMove_.store(&symFunc, std::memory_order_release);
            break;
        default:
            break;
    }

    return Result::Continue;
}

// Conditional methods can be registered before their branch is discarded.
// Every lifecycle consumer must observe the selected method set.
SymbolFunction* SymbolStruct::opDrop()
{
    auto* function = opDrop_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

const SymbolFunction* SymbolStruct::opDrop() const
{
    const auto* function = opDrop_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

SymbolFunction* SymbolStruct::opPostCopy()
{
    auto* function = opPostCopy_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

const SymbolFunction* SymbolStruct::opPostCopy() const
{
    const auto* function = opPostCopy_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

SymbolFunction* SymbolStruct::opPostMove()
{
    auto* function = opPostMove_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

const SymbolFunction* SymbolStruct::opPostMove() const
{
    const auto* function = opPostMove_.load(std::memory_order_acquire);
    return function && !function->isIgnored() ? function : nullptr;
}

const SymbolFunction* SymbolStruct::effectiveOpInit(const TaskContext& ctx) const
{
    if (isGenericRoot() && !isGenericInstance())
        return nullptr;

    if (const SymbolFunction* init = opaqueInit(ctx))
        return init;

    return findGeneratedInitWrapper(ctx, *this);
}

const SymbolFunction* SymbolStruct::opaqueInit(const TaskContext& ctx) const
{
    if (!attributes().hasRtFlag(RtAttributeFlagsE::Opaque))
        return nullptr;

    const SymbolFunction* function = findGeneratedImplicitMethod(ctx, *this, "swagOpaqueInit");
    return function && function->isForeign() ? function : nullptr;
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

const GenericInstanceOrigin* SymbolStruct::genericInstanceOrigin() const noexcept
{
    return SymbolGenericData::instanceOrigin(genericData());
}

void SymbolStruct::setGenericInstance(SymbolStruct* root, const GenericInstanceOrigin& origin) noexcept
{
    if (root)
    {
        addExtraFlag(SymbolStructFlagsE::GenericInstance);

        auto& data   = ensureGenericData();
        data.rootSym = root;
        data.origin  = origin;
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
    return SymbolGenericData::ensure(genericData_);
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
    SymbolGenericData::setCompletionOwner(ensureGenericData(), ctx);
}

bool SymbolStruct::isGenericCompletionOwner(const TaskContext& ctx) const noexcept
{
    return SymbolGenericData::isCompletionOwner(genericData(), ctx);
}

bool SymbolStruct::isGenericCompletionActive(const TaskContext& ctx) const noexcept
{
    const auto* data = genericData();
    return SymbolGenericData::isCompletionOwner(data, ctx) &&
           (data->completionState.load(std::memory_order_acquire) & K_GENERIC_COMPLETION_DEPTH_MASK) != 0;
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

bool SymbolStruct::tryMarkGeneratedEquality() const noexcept
{
    bool expected = false;
    return generatedEqualityDone_.compare_exchange_strong(expected, true, std::memory_order_acq_rel, std::memory_order_acquire);
}

SWC_END_NAMESPACE();
