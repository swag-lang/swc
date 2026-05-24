#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool intLikeConstantFitsType(const ConstantValue& cst, const TypeInfo& targetType)
    {
        SWC_ASSERT(targetType.isIntLike());

        const ApsInt   value      = cst.getIntLike();
        const uint32_t targetBits = targetType.payloadIntLikeBits();
        const uint32_t valueBits  = value.bitWidth();
        const uint32_t checkBits  = (valueBits > targetBits + 1) ? valueBits : (targetBits + 1);
        const bool     isUnsigned = targetType.isIntLikeUnsigned();

        if (isUnsigned)
        {
            if (!value.isUnsigned() && value.isNegative())
                return false;

            ApsInt vCheck = value;
            if (!vCheck.isUnsigned())
                vCheck.setUnsigned(true);
            vCheck.resize(checkBits);

            ApsInt maxCheck = ApsInt::maxValue(targetBits, true);
            maxCheck.resize(checkBits);
            return !vCheck.gt(maxCheck);
        }

        const ApsInt minSigned = ApsInt::minValue(targetBits, false);
        const ApsInt maxSigned = ApsInt::maxValue(targetBits, false);
        if (!value.isUnsigned())
        {
            ApsInt vCheck = value;
            vCheck.resize(checkBits);

            ApsInt minCheck = minSigned;
            ApsInt maxCheck = maxSigned;
            minCheck.resize(checkBits);
            maxCheck.resize(checkBits);
            return !vCheck.lt(minCheck) && !vCheck.gt(maxCheck);
        }

        ApsInt vCheck = value;
        vCheck.resize(checkBits);

        ApsInt maxBits = ApsInt::maxValue(targetBits, true);
        maxBits.resize(checkBits);
        if (vCheck.gt(maxBits))
            return false;

        ApsInt maxSignedU = maxSigned;
        if (!maxSignedU.isUnsigned())
            maxSignedU.setUnsigned(true);
        maxSignedU.resize(checkBits);
        return !vCheck.gt(maxSignedU);
    }

    TypeRef deduceConcretizedAggregateArrayElementType(Sema& sema, std::span<const TypeRef> elemTypes, const std::vector<ConstantRef>* values);
    TypeRef deduceConcretizedAggregateStructType(Sema& sema, TypeRef typeRef, ConstantRef cstRef);

    void tryMaterializeAggregateLiteralConstant(Sema& sema, SemaNodeView& defaultView)
    {
        if (defaultView.cstRef().isValid() || defaultView.typeRef().isInvalid())
            return;

        const TypeInfo& typeInfo = sema.typeMgr().get(defaultView.typeRef());
        if (!typeInfo.isAggregateArray() && !typeInfo.isAggregateStruct())
            return;

        SmallVector<AstNodeRef> children;
        sema.node(defaultView.nodeRef()).collectChildrenFromAst(children, sema.ast());
        if (children.empty())
            return;

        SmallVector<ConstantRef> values;
        values.reserve(children.size());

        for (const AstNodeRef childRef : children)
        {
            if (childRef.isInvalid())
                return;

            const SemaNodeView childView = sema.viewTypeConstant(childRef);
            if (childView.cstRef().isInvalid())
                return;
            values.push_back(childView.cstRef());
        }

        SmallVector<IdentifierRef> names;
        if (typeInfo.isAggregateStruct())
        {
            names.reserve(typeInfo.payloadAggregate().names.size());
            for (const IdentifierRef name : typeInfo.payloadAggregate().names)
                names.push_back(name);
        }

        ConstantValue cst = typeInfo.isAggregateArray() ? ConstantValue::makeAggregateArray(sema.ctx(), values) : ConstantValue::makeAggregateStruct(sema.ctx(), names, values);
        sema.setConstant(defaultView.nodeRef(), sema.cstMgr().addConstant(sema.ctx(), cst));
        defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
    }

    bool isAggregateTypeLikeElement(Sema& sema, TypeRef typeRef)
    {
        return SemaHelpers::isTypeLikeTypeRef(sema.ctx(), typeRef);
    }

    TypeRef normalizeAggregateTypeLikeElementType(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
    {
        if (!isAggregateTypeLikeElement(sema, typeRef))
            return typeRef;
        return SemaHelpers::normalizeTypeLikeValueTypeRef(sema, typeRef, cstRef, sema.ctx().state().nodeRef);
    }

    Result normalizeDefaultValueView(Sema& sema, SemaNodeView& defaultView, TypeRef targetTypeRef, TypeRef* outResolvedTypeRef = nullptr)
    {
        tryMaterializeAggregateLiteralConstant(sema, defaultView);

        if (defaultView.typeRef().isInvalid() && defaultView.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, defaultView.nodeRef(), defaultView.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(defaultView.nodeRef(), newCstRef);
            defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

        TypeRef resolvedTypeRef = defaultView.typeRef();
        if (targetTypeRef.isValid())
        {
            if (defaultView.typeRef().isValid())
            {
                SWC_RESULT(Cast::cast(sema, defaultView, targetTypeRef, CastKind::Initialization));
                defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            }
            resolvedTypeRef = targetTypeRef;
            if (outResolvedTypeRef)
                *outResolvedTypeRef = resolvedTypeRef;
            return Result::Continue;
        }

        const TypeRef concretizedTypeRef = SemaHelpers::deduceConcretizedAggregateLiteralType(sema, defaultView.typeRef(), defaultView.cstRef());
        if (concretizedTypeRef.isValid() && concretizedTypeRef != defaultView.typeRef())
        {
            SWC_RESULT(Cast::cast(sema, defaultView, concretizedTypeRef, CastKind::Initialization));
            defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            resolvedTypeRef = concretizedTypeRef;
        }

        if (resolvedTypeRef.isValid() && sema.typeMgr().get(resolvedTypeRef).isInt())
        {
            const TypeRef promotedTypeRef = sema.typeMgr().promote(resolvedTypeRef, resolvedTypeRef, false);
            SWC_RESULT(Cast::cast(sema, defaultView, promotedTypeRef, CastKind::Implicit));
            defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
            resolvedTypeRef = promotedTypeRef;
        }

        if (resolvedTypeRef.isValid() && isAggregateTypeLikeElement(sema, resolvedTypeRef))
            resolvedTypeRef = normalizeAggregateTypeLikeElementType(sema, resolvedTypeRef, defaultView.cstRef());

        if (outResolvedTypeRef)
            *outResolvedTypeRef = resolvedTypeRef;
        return Result::Continue;
    }

    TypeRef runtimeTypeRefOrDeclaredSymbolTypeRef(Sema& sema, IdentifierManager::PredefinedName name)
    {
        const TypeRef typeRef = sema.typeMgr().runtimeType(name);
        if (typeRef.isValid())
            return typeRef;

        const IdentifierRef        swagIdRef   = sema.idMgr().predefined(IdentifierManager::PredefinedName::Swag);
        const IdentifierRef        targetIdRef = sema.idMgr().predefined(name);
        std::vector<const Symbol*> moduleSymbols;
        sema.moduleNamespace().getAllSymbols(moduleSymbols);
        for (const Symbol* moduleSym : moduleSymbols)
        {
            if (!moduleSym || !moduleSym->isNamespace() || moduleSym->idRef() != swagIdRef)
                continue;

            std::vector<const Symbol*> namespaceSymbols;
            moduleSym->asSymMap()->getAllSymbols(namespaceSymbols);
            for (const Symbol* candidate : namespaceSymbols)
            {
                if (candidate && candidate->idRef() == targetIdRef && candidate->typeRef().isValid())
                    return candidate->typeRef();
            }
        }

        return TypeRef::invalid();
    }

    TypeRef specializedTypeInfoStructTypeRef(Sema& sema, TypeRef representedTypeRef)
    {
        using Pn                   = IdentifierManager::PredefinedName;
        const TypeManager& typeMgr = sema.typeMgr();
        if (!representedTypeRef.isValid())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfo);

        const TypeInfo& representedType = typeMgr.get(representedTypeRef);
        if (representedType.isArray() || representedType.isAggregateArray())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoArray);
        if (representedType.isStruct() || representedType.isAggregateStruct())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoStruct);
        if (representedType.isEnum())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoEnum);
        if (representedType.isFunction())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoFunc);
        if (representedType.isSlice())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoSlice);
        if (representedType.isAnyPointer())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoPointer);
        if (representedType.isAlias())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoAlias);
        if (representedType.isAnyVariadic())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoVariadic);
        if (representedType.isCodeBlock())
            return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfoCodeBlock);
        return runtimeTypeRefOrDeclaredSymbolTypeRef(sema, Pn::TypeInfo);
    }

    TypeRef specializedTypeInfoPointerTypeRef(Sema& sema, TypeRef representedTypeRef)
    {
        const TypeRef structTypeRef = specializedTypeInfoStructTypeRef(sema, representedTypeRef);
        if (!structTypeRef.isValid())
            return TypeRef::invalid();

        return sema.typeMgr().addType(TypeInfo::makeValuePointer(structTypeRef, TypeInfoFlagsE::Const));
    }

    TypeRef deduceConcretizedAggregateLiteralTypeImpl(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (typeInfo.isAggregateArray())
            return SemaHelpers::deduceConcretizedAggregateArrayType(sema, typeRef, cstRef);
        if (typeInfo.isAggregateStruct())
            return deduceConcretizedAggregateStructType(sema, typeRef, cstRef);

        if (cstRef.isValid())
        {
            const ConstantValue& cst     = sema.cstMgr().get(cstRef);
            const TypeInfo&      cstType = sema.typeMgr().get(cst.typeRef());
            if (typeInfo.isIntUnsized() || cstType.isIntUnsized())
            {
                TypeInfo::Sign sign = typeInfo.isIntUnsized() ? typeInfo.payloadIntSign() : cstType.payloadIntSign();
                if (sign == TypeInfo::Sign::Unknown)
                    sign = TypeInfo::Sign::Signed;

                bool           overflow = false;
                const uint32_t destBits = TypeManager::chooseConcreteScalarWidth(cst.getIntLike().minBits(), overflow);
                if (!overflow)
                    return sema.typeMgr().typeInt(destBits, sign);
            }
            else if (typeInfo.isFloatUnsized() || cstType.isFloatUnsized())
            {
                bool           overflow = false;
                const uint32_t destBits = TypeManager::chooseConcreteScalarWidth(cst.getFloat().minBits(), overflow);
                if (!overflow)
                    return sema.typeMgr().typeFloat(destBits);
            }
        }

        if (typeInfo.isIntUnsized())
        {
            TypeInfo::Sign sign = typeInfo.payloadIntSign();
            if (sign == TypeInfo::Sign::Unknown)
                sign = TypeInfo::Sign::Signed;
            return sema.typeMgr().typeInt(32, sign);
        }

        if (typeInfo.isFloatUnsized())
            return sema.typeMgr().typeF64();

        return typeRef;
    }

    TypeRef deduceConcretizedAggregateStructType(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
    {
        TypeManager&    typeMgr    = sema.typeMgr();
        const TypeInfo& typeInfo   = typeMgr.get(typeRef);
        const auto&     aggregate  = typeInfo.payloadAggregate();
        const auto&     fieldTypes = aggregate.types;
        const auto*     values     = static_cast<const std::vector<ConstantRef>*>(nullptr);

        if (cstRef.isValid())
        {
            const ConstantValue& cst = sema.cstMgr().get(cstRef);
            if (cst.isAggregateStruct())
                values = &cst.getAggregateStruct();
        }

        bool                 changed = false;
        SmallVector<TypeRef> concreteFieldTypes;
        concreteFieldTypes.reserve(fieldTypes.size());

        for (size_t i = 0; i < fieldTypes.size(); ++i)
        {
            const ConstantRef fieldCstRef  = values && i < values->size() ? (*values)[i] : ConstantRef::invalid();
            const TypeRef     fieldTypeRef = normalizeAggregateTypeLikeElementType(sema, deduceConcretizedAggregateLiteralTypeImpl(sema, fieldTypes[i], fieldCstRef), fieldCstRef);
            concreteFieldTypes.push_back(fieldTypeRef);
            changed = changed || fieldTypeRef != fieldTypes[i];
        }

        if (!changed)
            return typeRef;

        SmallVector<IdentifierRef> fieldNames;
        fieldNames.reserve(aggregate.names.size());
        for (const IdentifierRef fieldName : aggregate.names)
            fieldNames.push_back(fieldName);

        return typeMgr.addType(TypeInfo::makeAggregateStruct(fieldNames, concreteFieldTypes));
    }

    bool constantFitsArrayTarget(Sema& sema, ConstantRef cstRef, std::span<const uint64_t> dims, TypeRef elementTypeRef);

    bool constantFitsTargetType(Sema& sema, ConstantRef cstRef, TypeRef targetTypeRef)
    {
        if (!cstRef.isValid() || !targetTypeRef.isValid())
            return false;

        const TypeManager&   typeMgr    = sema.typeMgr();
        const ConstantValue& cst        = sema.cstMgr().get(cstRef);
        const TypeInfo&      targetType = typeMgr.get(targetTypeRef);
        const TypeInfo&      cstType    = typeMgr.get(cst.typeRef());

        if (targetTypeRef == cst.typeRef())
            return true;

        if (targetType.isArray())
            return constantFitsArrayTarget(sema, cstRef, targetType.payloadArrayDims(), targetType.payloadArrayElemTypeRef());

        if (targetType.isIntLike() && cstType.isIntLike())
            return intLikeConstantFitsType(cst, targetType);

        if (targetType.isFloat() && cstType.isScalarNumeric())
        {
            const TypeRef concreteTypeRef = deduceConcretizedAggregateLiteralTypeImpl(sema, cst.typeRef(), cstRef);
            return typeMgr.promote(targetTypeRef, concreteTypeRef, false) == targetTypeRef;
        }

        return false;
    }

    bool constantFitsArrayTarget(Sema& sema, ConstantRef cstRef, std::span<const uint64_t> dims, TypeRef elementTypeRef)
    {
        if (!cstRef.isValid() || dims.empty())
            return false;

        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (!cst.isAggregateArray() || cst.getAggregateArray().size() != dims[0])
            return false;

        for (const ConstantRef valueRef : cst.getAggregateArray())
        {
            if (dims.size() == 1)
            {
                if (!constantFitsTargetType(sema, valueRef, elementTypeRef))
                    return false;
                continue;
            }

            if (!constantFitsArrayTarget(sema, valueRef, dims.subspan(1), elementTypeRef))
                return false;
        }

        return true;
    }

    TypeRef deduceConcretizedAggregateStructArrayElementType(Sema& sema, std::span<const TypeRef> elemTypes, const std::vector<ConstantRef>* values)
    {
        if (elemTypes.empty())
            return TypeRef::invalid();

        TypeManager&    typeMgr         = sema.typeMgr();
        const TypeInfo& firstStructType = typeMgr.get(elemTypes.front());
        if (!firstStructType.isAggregateStruct())
            return TypeRef::invalid();

        const auto& firstAggregate = firstStructType.payloadAggregate();
        SmallVector<IdentifierRef> mergedFieldNames;
        mergedFieldNames.reserve(firstAggregate.names.size());
        for (const IdentifierRef fieldName : firstAggregate.names)
            mergedFieldNames.push_back(fieldName);

        bool namesChanged = false;
        for (size_t i = 1; i < elemTypes.size(); ++i)
        {
            const TypeInfo& structType = typeMgr.get(elemTypes[i]);
            if (!structType.isAggregateStruct())
                return TypeRef::invalid();

            const auto& aggregate = structType.payloadAggregate();
            if (aggregate.names.size() != firstAggregate.names.size() || aggregate.types.size() != firstAggregate.types.size())
                return TypeRef::invalid();

            for (size_t fieldIndex = 0; fieldIndex < aggregate.names.size(); ++fieldIndex)
            {
                const IdentifierRef incomingName = aggregate.names[fieldIndex];
                const IdentifierRef mergedName   = mergedFieldNames[fieldIndex];
                if (mergedName.isValid() && incomingName.isValid() && incomingName != mergedName)
                    return TypeRef::invalid();
                if (!mergedName.isValid() && incomingName.isValid())
                {
                    mergedFieldNames[fieldIndex] = incomingName;
                    namesChanged                 = true;
                }
            }
        }

        SmallVector<TypeRef> mergedFieldTypes;
        mergedFieldTypes.reserve(firstAggregate.types.size());
        bool changed = false;

        for (size_t fieldIndex = 0; fieldIndex < firstAggregate.types.size(); ++fieldIndex)
        {
            SmallVector<TypeRef> fieldTypes;
            fieldTypes.reserve(elemTypes.size());

            SmallVector<ConstantRef> fieldValues;
            bool                     hasFieldValues = values != nullptr;
            if (values)
                fieldValues.reserve(elemTypes.size());

            for (size_t elemIndex = 0; elemIndex < elemTypes.size(); ++elemIndex)
            {
                const TypeInfo& aggregateType = typeMgr.get(elemTypes[elemIndex]);
                fieldTypes.push_back(aggregateType.payloadAggregate().types[fieldIndex]);

                if (!values)
                    continue;

                const ConstantRef elemCstRef = elemIndex < values->size() ? (*values)[elemIndex] : ConstantRef::invalid();
                if (!elemCstRef.isValid())
                {
                    hasFieldValues = false;
                    continue;
                }

                const ConstantValue& elemCst = sema.cstMgr().get(elemCstRef);
                if (!elemCst.isAggregateStruct() || fieldIndex >= elemCst.getAggregateStruct().size())
                {
                    hasFieldValues = false;
                    continue;
                }

                fieldValues.push_back(elemCst.getAggregateStruct()[fieldIndex]);
            }

            const std::vector<ConstantRef>* fieldValuesPtr = nullptr;
            std::vector<ConstantRef>        fieldValuesStorage;
            if (values && hasFieldValues && fieldValues.size() == elemTypes.size())
            {
                fieldValuesStorage.assign(fieldValues.begin(), fieldValues.end());
                fieldValuesPtr = &fieldValuesStorage;
            }

            const TypeRef mergedFieldTypeRef = deduceConcretizedAggregateArrayElementType(sema, fieldTypes.span(), fieldValuesPtr);
            if (!mergedFieldTypeRef.isValid())
                return TypeRef::invalid();

            mergedFieldTypes.push_back(mergedFieldTypeRef);
            changed = changed || mergedFieldTypeRef != firstAggregate.types[fieldIndex];
        }

        if (!changed && !namesChanged)
            return elemTypes.front();

        return typeMgr.addType(TypeInfo::makeAggregateStruct(mergedFieldNames, mergedFieldTypes));
    }

    bool sameArrayDimensions(std::span<const uint64_t> leftDims, std::span<const uint64_t> rightDims)
    {
        if (leftDims.size() != rightDims.size())
            return false;

        for (size_t i = 0; i < leftDims.size(); ++i)
        {
            if (leftDims[i] != rightDims[i])
                return false;
        }

        return true;
    }

    TypeRef mergeConcretizedArrayTypes(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (!leftTypeRef.isValid() || !rightTypeRef.isValid())
            return TypeRef::invalid();

        TypeManager&    typeMgr   = sema.typeMgr();
        const TypeInfo& leftType  = typeMgr.get(leftTypeRef);
        const TypeInfo& rightType = typeMgr.get(rightTypeRef);
        if (!leftType.isArray() || !rightType.isArray())
            return TypeRef::invalid();
        if (!sameArrayDimensions(leftType.payloadArrayDims(), rightType.payloadArrayDims()))
            return TypeRef::invalid();

        const std::array elementTypes      = {leftType.payloadArrayElemTypeRef(), rightType.payloadArrayElemTypeRef()};
        const TypeRef    mergedElemTypeRef = deduceConcretizedAggregateArrayElementType(sema, elementTypes, nullptr);
        if (!mergedElemTypeRef.isValid())
            return TypeRef::invalid();

        SmallVector<uint64_t> dims;
        dims.reserve(leftType.payloadArrayDims().size());
        for (const uint64_t dim : leftType.payloadArrayDims())
            dims.push_back(dim);
        return typeMgr.addType(TypeInfo::makeArray(dims.span(), mergedElemTypeRef));
    }

    TypeRef deduceConcretizedAggregateArrayElementType(Sema& sema, std::span<const TypeRef> elemTypes, const std::vector<ConstantRef>* values)
    {
        const TypeManager&   typeMgr = sema.typeMgr();
        SmallVector<TypeRef> concreteElemTypes;
        concreteElemTypes.reserve(elemTypes.size());

        TypeRef resultTypeRef = TypeRef::invalid();
        for (size_t i = 0; i < elemTypes.size(); ++i)
        {
            const ConstantRef elemCstRef  = values && i < values->size() ? (*values)[i] : ConstantRef::invalid();
            const TypeRef     elemTypeRef = normalizeAggregateTypeLikeElementType(sema, deduceConcretizedAggregateLiteralTypeImpl(sema, elemTypes[i], elemCstRef), elemCstRef);
            concreteElemTypes.push_back(elemTypeRef);

            const TypeInfo& originalType = typeMgr.get(elemTypes[i]);
            if (!originalType.isScalarNumeric() || originalType.isScalarUnsized())
                continue;

            if (!resultTypeRef.isValid())
            {
                resultTypeRef = elemTypeRef;
                continue;
            }

            resultTypeRef = typeMgr.promote(resultTypeRef, elemTypeRef, false);
        }

        if (!resultTypeRef.isValid() && !concreteElemTypes.empty())
            resultTypeRef = concreteElemTypes[0];

        const TypeRef mergedAggregateStructTypeRef = deduceConcretizedAggregateStructArrayElementType(sema, concreteElemTypes.span(), values);
        if (mergedAggregateStructTypeRef.isValid())
            return mergedAggregateStructTypeRef;

        for (size_t i = 0; i < elemTypes.size(); ++i)
        {
            const ConstantRef elemCstRef  = values && i < values->size() ? (*values)[i] : ConstantRef::invalid();
            const TypeRef     elemTypeRef = concreteElemTypes[i];
            if (!resultTypeRef.isValid())
            {
                resultTypeRef = elemTypeRef;
                continue;
            }

            if (elemTypeRef == resultTypeRef)
                continue;

            const TypeInfo& resultType = typeMgr.get(resultTypeRef);
            const TypeInfo& elemType   = typeMgr.get(elemTypeRef);
            if (isAggregateTypeLikeElement(sema, resultTypeRef) && isAggregateTypeLikeElement(sema, elemTypeRef))
            {
                if (resultType.isAnyTypeInfo(sema.ctx()))
                    continue;

                if (elemType.isAnyTypeInfo(sema.ctx()))
                {
                    resultTypeRef = elemTypeRef;
                    continue;
                }

                resultTypeRef = typeMgr.typeTypeInfo();
                continue;
            }

            if (!resultType.isScalarNumeric() || !elemType.isScalarNumeric())
            {
                if (constantFitsTargetType(sema, elemCstRef, resultTypeRef))
                    continue;

                const TypeRef mergedArrayTypeRef = mergeConcretizedArrayTypes(sema, resultTypeRef, elemTypeRef);
                if (mergedArrayTypeRef.isValid())
                {
                    resultTypeRef = mergedArrayTypeRef;
                    continue;
                }

                return TypeRef::invalid();
            }

            if (constantFitsTargetType(sema, elemCstRef, resultTypeRef))
                continue;

            resultTypeRef = typeMgr.promote(resultTypeRef, elemTypeRef, false);
        }

        return resultTypeRef;
    }
}

TypeRef SemaHelpers::deduceConcretizedAggregateLiteralType(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
{
    return deduceConcretizedAggregateLiteralTypeImpl(sema, typeRef, cstRef);
}

TypeRef SemaHelpers::deduceConcretizedAggregateArrayType(Sema& sema, TypeRef typeRef, ConstantRef cstRef)
{
    TypeManager& typeMgr = sema.typeMgr();
    SWC_ASSERT(typeRef.isValid());
    SWC_ASSERT(typeMgr.get(typeRef).isAggregateArray());

    const auto& elemTypes = typeMgr.get(typeRef).payloadAggregate().types;
    if (elemTypes.empty())
        return typeRef;

    const std::vector<ConstantRef>* values = nullptr;
    if (cstRef.isValid())
    {
        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (cst.isAggregateArray())
            values = &cst.getAggregateArray();
    }

    const TypeRef elemTypeRef = deduceConcretizedAggregateArrayElementType(sema, elemTypes, values);
    if (elemTypeRef.isInvalid())
        return typeRef;

    if (typeMgr.get(elemTypeRef).isAggregateArray())
        return typeRef;

    SmallVector4<uint64_t> outerDim;
    outerDim.push_back(elemTypes.size());
    return typeMgr.addType(TypeInfo::makeArray(outerDim, elemTypeRef));
}

bool SemaHelpers::isTypeLikeTypeRef(const TaskContext& ctx, TypeRef typeRef)
{
    if (!typeRef.isValid())
        return false;

    const TypeInfo& typeInfo = ctx.typeMgr().get(typeRef);
    return typeInfo.isTypeValue() || typeInfo.isAnyTypeInfo(ctx) || ctx.typeMgr().isRuntimeTypeInfoPointer(ctx, typeRef);
}

TypeRef SemaHelpers::resolveRepresentedTypeRef(Sema& sema, const SemaNodeView& view)
{
    if (view.type() && view.type()->isTypeValue())
        return view.type()->payloadTypeRef();
    if (!view.cstRef().isValid())
        return TypeRef::invalid();

    return sema.cstMgr().makeTypeValue(sema, view.cstRef());
}

TypeRef SemaHelpers::normalizeTypeLikeValueTypeRef(Sema& sema, TypeRef typeRef, ConstantRef cstRef, AstNodeRef ownerNodeRef)
{
    if (!isTypeLikeTypeRef(sema.ctx(), typeRef))
        return typeRef;

    if (cstRef.isValid())
    {
        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), cst.typeRef()))
            return cst.typeRef();

        TypeRef representedTypeRef = TypeRef::invalid();
        if (cst.isTypeValue())
            representedTypeRef = cst.getTypeValue();
        else
            representedTypeRef = sema.cstMgr().makeTypeValue(sema, cstRef);

        if (representedTypeRef.isValid())
        {
            const TypeRef specializedTypeRef = specializedTypeInfoPointerTypeRef(sema, representedTypeRef);
            if (specializedTypeRef.isValid())
                return specializedTypeRef;
        }

        ConstantRef normalizedCstRef = cstRef;
        if (normalizeTypeInfoConstantRef(sema, normalizedCstRef, ownerNodeRef) == Result::Continue && normalizedCstRef.isValid())
            return sema.cstMgr().get(normalizedCstRef).typeRef();
    }

    if (sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), typeRef))
        return typeRef;

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    if (typeInfo.isTypeValue())
    {
        const TypeRef specializedTypeRef = specializedTypeInfoPointerTypeRef(sema, typeInfo.payloadTypeRef());
        if (specializedTypeRef.isValid())
            return specializedTypeRef;
    }

    return typeInfo.isAnyTypeInfo(sema.ctx()) ? typeRef : sema.typeMgr().typeTypeInfo();
}

TypeRef SemaHelpers::preciseAnyBoxedValueTypeRef(Sema& sema, TypeRef valueTypeRef, ConstantRef valueCstRef, AstNodeRef ownerNodeRef)
{
    if (!valueTypeRef.isValid())
        return TypeRef::invalid();

    const TaskContext& ctx = sema.ctx();
    if (ownerNodeRef.isValid())
    {
        const SemaNodeView ownerView = sema.viewTypeConstant(ownerNodeRef);
        if (ownerView.typeRef().isValid() && sema.typeMgr().isRuntimeTypeInfoPointer(ctx, ownerView.typeRef()))
            return ownerView.typeRef();

        if (isTypeLikeTypeRef(ctx, ownerView.typeRef()))
        {
            const TypeRef representedTypeRef = resolveRepresentedTypeRef(sema, ownerView);
            if (representedTypeRef.isValid())
            {
                ConstantRef typeInfoCstRef = ConstantRef::invalid();
                if (sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, representedTypeRef, ownerNodeRef) == Result::Continue && typeInfoCstRef.isValid())
                    return sema.cstMgr().get(typeInfoCstRef).typeRef();
            }
        }
    }

    if (valueCstRef.isValid() && isTypeLikeTypeRef(ctx, valueTypeRef))
    {
        ConstantRef normalizedCstRef = valueCstRef;
        if (normalizeTypeInfoConstantRef(sema, normalizedCstRef, ownerNodeRef) == Result::Continue && normalizedCstRef.isValid())
            return sema.cstMgr().get(normalizedCstRef).typeRef();
    }

    return valueTypeRef;
}

Result SemaHelpers::normalizeTypeInfoConstantRef(Sema& sema, ConstantRef& ioCstRef, AstNodeRef ownerNodeRef)
{
    if (!ioCstRef.isValid())
        return Result::Continue;

    TypeRef valueTypeRef = TypeRef::invalid();
    if (ownerNodeRef.isValid())
        valueTypeRef = resolveRepresentedTypeRef(sema, sema.viewTypeConstant(ownerNodeRef));

    const ConstantValue& cst = sema.cstMgr().get(ioCstRef);
    if (!valueTypeRef.isValid())
        valueTypeRef = cst.isTypeValue() ? cst.getTypeValue() : sema.cstMgr().makeTypeValue(sema, ioCstRef);
    if (!valueTypeRef.isValid())
        return Result::Continue;

    ConstantRef typeInfoCstRef = ConstantRef::invalid();
    SWC_RESULT(sema.cstMgr().makeTypeInfo(sema, typeInfoCstRef, valueTypeRef, ownerNodeRef));
    SWC_ASSERT(typeInfoCstRef.isValid());
    ioCstRef = typeInfoCstRef;
    return Result::Continue;
}

Result SemaHelpers::deduceDefaultValueType(Sema& sema, AstNodeRef defaultValueRef, TypeRef& outTypeRef)
{
    outTypeRef = TypeRef::invalid();
    if (defaultValueRef.isInvalid())
        return Result::Continue;

    SemaNodeView defaultView = sema.viewNodeTypeConstant(defaultValueRef);
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, defaultView));
    SWC_RESULT(normalizeDefaultValueView(sema, defaultView, TypeRef::invalid(), &outTypeRef));

    return Result::Continue;
}

Result SemaHelpers::finalizeDefaultValue(Sema& sema, AstNodeRef defaultValueRef, SymbolVariable& symVar)
{
    if (defaultValueRef.isInvalid())
        return Result::Continue;

    SemaNodeView defaultView = sema.viewNodeTypeConstant(defaultValueRef);
    SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, defaultView));

    const TypeInfo& paramType = sema.typeMgr().get(symVar.typeRef());
    if (!paramType.isCodeBlock())
        SWC_RESULT(normalizeDefaultValueView(sema, defaultView, symVar.typeRef()));

    const bool isCallerLocation = isCallerLocationDefaultInitializer(sema, defaultValueRef);
    if (!paramType.isCodeBlock() && !isCallerLocation && defaultView.cstRef().isInvalid())
        return SemaError::raiseExprNotConst(sema, defaultView.nodeRef());

    if (defaultView.cstRef().isValid())
        symVar.setDefaultValueRef(defaultView.cstRef());
    if (isCallerLocation)
        symVar.addExtraFlag(SymbolVariableFlagsE::CallerLocationDefault);
    symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
    return Result::Continue;
}

namespace
{
    TypeRef normalizeBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    IdentifierRef namedArgumentIdentifier(Sema& sema, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (childNode.isNot(AstNodeId::NamedArgument))
            return IdentifierRef::invalid();

        return sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
    }

    template<typename T>
    bool resolveAggregateChildIndex(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, size_t memberCount, const T& resolveNamedIndex, size_t& outIndex)
    {
        outIndex = 0;
        if (!memberCount)
            return false;

        std::vector<uint8_t> assigned(memberCount, 0);
        size_t               nextPos = 0;

        for (const AstNodeRef currentChildRef : children)
        {
            const IdentifierRef namedIdRef = namedArgumentIdentifier(sema, currentChildRef);
            if (namedIdRef.isValid())
            {
                size_t namedIndex = 0;
                if (!resolveNamedIndex(namedIdRef, namedIndex) || namedIndex >= memberCount)
                {
                    if (currentChildRef == childRef)
                        return false;
                    continue;
                }

                if (currentChildRef == childRef)
                {
                    outIndex = namedIndex;
                    return true;
                }

                assigned[namedIndex] = 1;
                continue;
            }

            while (nextPos < memberCount && assigned[nextPos])
                ++nextPos;

            if (currentChildRef == childRef)
            {
                if (nextPos >= memberCount)
                    return false;

                outIndex = nextPos;
                return true;
            }

            if (nextPos < memberCount)
            {
                assigned[nextPos] = 1;
                ++nextPos;
            }
        }

        return false;
    }

    bool resolveStructFieldIndex(std::span<const SymbolVariable* const> fields, const IdentifierRef idRef, size_t& outIndex)
    {
        for (size_t i = 0; i < fields.size(); ++i)
        {
            if (fields[i] && fields[i]->idRef() == idRef)
            {
                outIndex = i;
                return true;
            }
        }

        return false;
    }

    struct StructFieldIndexResolver
    {
        std::span<const SymbolVariable* const> fields;

        bool operator()(const IdentifierRef idRef, size_t& outIndex) const
        {
            return resolveStructFieldIndex(fields, idRef, outIndex);
        }
    };

    struct AggregateMemberIndexResolver
    {
        Sema*           sema       = nullptr;
        const TypeInfo* targetType = nullptr;

        bool operator()(const IdentifierRef idRef, size_t& outIndex) const
        {
            SWC_ASSERT(sema != nullptr);
            SWC_ASSERT(targetType != nullptr);
            return SemaHelpers::resolveAggregateMemberIndex(*sema, *targetType, idRef, outIndex);
        }
    };
}

Result SemaHelpers::finalizeAggregateStruct(Sema& sema, const SmallVector<AstNodeRef>& children, bool autoNameFromIdentifiers)
{
    SmallVector<TypeRef>       memberTypes;
    SmallVector<IdentifierRef> memberNames;
    memberTypes.reserve(children.size());
    memberNames.reserve(children.size());

    bool                     allConstant = true;
    SmallVector<ConstantRef> values;
    values.reserve(children.size());

    for (const AstNodeRef& child : children)
    {
        const AstNode& childNode = sema.node(child);
        if (childNode.is(AstNodeId::NamedArgument))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else if (autoNameFromIdentifiers && childNode.is(AstNodeId::Identifier))
            memberNames.push_back(sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef()));
        else
            memberNames.push_back(IdentifierRef::invalid());

        SemaNodeView view = sema.viewTypeConstant(child);
        SWC_ASSERT(view.typeRef().isValid());
        memberTypes.push_back(view.typeRef());
        allConstant = allConstant && view.cstRef().isValid();
        values.push_back(view.cstRef());
    }

    if (allConstant)
    {
        const auto val = ConstantValue::makeAggregateStruct(sema.ctx(), memberNames, values);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), val));
    }
    else
    {
        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAggregateStruct(memberNames, memberTypes));
        sema.setType(sema.curNodeRef(), typeRef);
    }

    sema.setIsValue(sema.curNodeRef());
    return Result::Continue;
}

Result SemaHelpers::resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = normalizeBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    const TypeInfo& targetType = sema.typeMgr().get(targetRef);
    size_t          fieldIndex = 0;

    if (targetType.isStruct())
    {
        SWC_RESULT(sema.waitSemaCompleted(&targetType, childRef));
        const auto&                    fields = targetType.payloadSymStruct().fields();
        const StructFieldIndexResolver findFieldIndex{fields};
        const bool                     found = resolveAggregateChildIndex(sema, children, childRef, fields.size(), findFieldIndex, fieldIndex);
        if (!found || fieldIndex >= fields.size() || !fields[fieldIndex])
            return Result::Continue;

        outTypeRef = fields[fieldIndex]->typeRef();
        return Result::Continue;
    }

    if (!targetType.isAggregateStruct())
        return Result::Continue;

    const auto&                        aggregate = targetType.payloadAggregate();
    const AggregateMemberIndexResolver resolveMemberIndex{.sema = &sema, .targetType = &targetType};
    const bool                         found = resolveAggregateChildIndex(sema, children, childRef, aggregate.types.size(), resolveMemberIndex, fieldIndex);
    if (!found || fieldIndex >= aggregate.types.size())
        return Result::Continue;

    outTypeRef = aggregate.types[fieldIndex];
    return Result::Continue;
}

Result SemaHelpers::resolveArrayLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = normalizeBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    size_t childIndex = 0;
    bool   found      = false;
    for (const AstNodeRef currentChildRef : children)
    {
        if (currentChildRef == childRef)
        {
            found = true;
            break;
        }

        ++childIndex;
    }

    if (!found)
        return Result::Continue;

    const TypeInfo& targetType = sema.typeMgr().get(targetRef);
    if (targetType.isArray())
    {
        outTypeRef = targetType.payloadArrayElemTypeRef();
        return Result::Continue;
    }

    if (targetType.isSlice() || targetType.isTypedVariadic())
    {
        outTypeRef = targetType.payloadTypeRef();
        return Result::Continue;
    }

    if (!targetType.isAggregateArray())
        return Result::Continue;

    const auto& elementTypes = targetType.payloadAggregate().types;
    if (childIndex >= elementTypes.size())
        return Result::Continue;

    outTypeRef = elementTypes[childIndex];
    return Result::Continue;
}

bool SemaHelpers::resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex)
{
    if (!aggregateType.isAggregateStruct())
        return false;

    const auto&            names  = aggregateType.payloadAggregate().names;
    const std::string_view idName = sema.idMgr().get(idRef).name;
    for (size_t i = 0; i < names.size(); ++i)
    {
        if (names[i].isValid() && names[i] == idRef)
        {
            outIndex = i;
            return true;
        }

        if (!names[i].isValid() && idName == ("item" + std::to_string(i)))
        {
            outIndex = i;
            return true;
        }
    }

    return false;
}

SWC_END_NAMESPACE();
