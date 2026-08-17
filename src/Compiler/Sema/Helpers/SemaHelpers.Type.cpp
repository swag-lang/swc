#include "pch.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isTypeSyntaxNode(const AstNode& node)
    {
        switch (node.id())
        {
            case AstNodeId::BuiltinType:
            case AstNodeId::NamedType:
            case AstNodeId::QualifiedType:
            case AstNodeId::ArrayType:
            case AstNodeId::SliceType:
            case AstNodeId::MoveRefType:
            case AstNodeId::ValuePointerType:
            case AstNodeId::BlockPointerType:
            case AstNodeId::VariadicType:
            case AstNodeId::TypedVariadicType:
            case AstNodeId::CodeType:
            case AstNodeId::RetValType:
            case AstNodeId::LambdaType:
            case AstNodeId::CompilerTypeExpr:
                return true;

            default:
                return false;
        }
    }

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
        if (defaultView.cstRef().isInvalid() && defaultView.typeRef().isValid())
        {
            SWC_RESULT(SemaHelpers::tryMaterializeAggregateLiteralConstant(sema, defaultView.nodeRef(), defaultView.typeRef()));
            if (sema.viewConstant(defaultView.nodeRef()).hasConstant())
                defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

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

        const Symbol* candidate = SemaHelpers::findPredefinedRuntimeSymbol(sema, name);
        if (candidate && candidate->typeRef().isValid())
            return candidate->typeRef();

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

        const auto&                firstAggregate = firstStructType.payloadAggregate();
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
        if (leftType.payloadArrayIndexTypeRefs() != rightType.payloadArrayIndexTypeRefs())
            return TypeRef::invalid();

        const std::array elementTypes      = {leftType.payloadArrayElemTypeRef(), rightType.payloadArrayElemTypeRef()};
        const TypeRef    mergedElemTypeRef = deduceConcretizedAggregateArrayElementType(sema, elementTypes, nullptr);
        if (!mergedElemTypeRef.isValid())
            return TypeRef::invalid();

        SmallVector<uint64_t> dims;
        dims.reserve(leftType.payloadArrayDims().size());
        for (const uint64_t dim : leftType.payloadArrayDims())
            dims.push_back(dim);
        return typeMgr.addType(TypeInfo::makeArray(dims.span(), mergedElemTypeRef, TypeInfoFlagsE::Zero, leftType.payloadArrayIndexTypeRefs()));
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

void SemaHelpers::normalizeTypeOperandToConstant(Sema& sema, SemaNodeView& view)
{
    if (!view.typeRef().isValid() || view.cstRef().isValid())
        return;

    const AstNodeRef targetRef = view.nodeRef();
    if (targetRef.isInvalid())
        return;

    const AstNode& targetNode = sema.node(targetRef);
    bool           isTypeExpr = isTypeSyntaxNode(targetNode);
    if (!isTypeExpr)
    {
        if (const auto* ident = targetNode.safeCast<AstIdentifier>())
            if (ident->hasFlag(AstIdentifierFlagsE::GenericTypeBinding))
                isTypeExpr = true;

        if (!isTypeExpr)
        {
            const SemaNodeView symbolView = sema.viewNodeTypeSymbol(targetRef);
            isTypeExpr                    = symbolView.sym() && symbolView.sym()->isType();
        }
    }

    if (!isTypeExpr)
        return;

    TypeRef typeValueRef = view.typeRef();
    if (view.type() && view.type()->isTypeValue())
        typeValueRef = view.type()->payloadTypeRef();

    const ConstantRef cstRef = sema.cstMgr().addConstant(sema.ctx(), ConstantValue::makeTypeValue(sema.ctx(), typeValueRef));
    sema.setConstant(targetRef, cstRef);
    view.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
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

Result SemaHelpers::tryMaterializeAggregateLiteralConstant(Sema& sema, const AstNodeRef exprRef, const TypeRef typeRef)
{
    if (sema.viewConstant(exprRef).hasConstant())
        return Result::Continue;

    const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
    if (!typeInfo.isAggregateArray() && !typeInfo.isAggregateStruct())
        return Result::Continue;

    SmallVector<AstNodeRef> children;
    sema.node(exprRef).collectChildrenFromAst(children, sema.ast());
    if (children.empty())
        return Result::Continue;

    SmallVector<ConstantRef> values;
    values.reserve(children.size());
    for (const AstNodeRef childRef : children)
    {
        if (childRef.isInvalid())
            return Result::Continue;

        const SemaNodeView childView = sema.viewTypeConstant(childRef);
        if (childView.cstRef().isInvalid())
            return Result::Continue;
        values.push_back(childView.cstRef());
    }

    const ConstantValue cst = typeInfo.isAggregateArray() ? ConstantValue::makeAggregateArray(sema.ctx(), values) : ConstantValue::makeAggregateStruct(sema.ctx(), typeInfo.payloadAggregate().names, values);
    sema.setConstant(exprRef, sema.cstMgr().addConstant(sema.ctx(), cst));
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
    IdentifierRef namedArgumentIdentifier(Sema& sema, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (childNode.isNot(AstNodeId::NamedArgument))
            return IdentifierRef::invalid();

        return sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
    }

    bool resolveNamedMemberIndex(Sema& sema, const TypeInfo& targetType, IdentifierRef idRef, size_t& outIndex)
    {
        if (targetType.isStruct())
            return targetType.payloadSymStruct().tryGetFieldIndexByName(outIndex, idRef);
        return targetType.tryGetAggregateMemberIndexByName(outIndex, sema.ctx(), idRef);
    }

    // Walks the literal's children in order, assigning each one its slot: a named argument
    // takes the member it names, a positional one takes the next slot no name has claimed.
    bool resolveAggregateChildIndex(Sema& sema, const TypeInfo& targetType, std::span<const AstNodeRef> children, AstNodeRef childRef, size_t memberCount, size_t& outIndex)
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
                if (!resolveNamedMemberIndex(sema, targetType, namedIdRef, namedIndex) || namedIndex >= memberCount)
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

        // A child can still be untyped here when it is an auto-member (`.value`)
        // nested inside an aggregate literal that is itself a call argument: the
        // direct-argument deferral that would resolve it from the selected
        // overload's parameter type does not reach nested literal children. Emit
        // a clear diagnostic instead of asserting (the compiler must never assert).
        if (!view.typeRef().isValid())
            return SemaError::raise(sema, DiagnosticId::sema_err_cannot_infer_aggregate_field_type, child);

        // A bare type expression ('MyStruct') becomes a TypeValue constant, exactly
        // like in a scalar initialization, so it can later cast to a 'typeinfo' field.
        SWC_RESULT(SemaCheck::isValueOrType(sema, view));

        // A literal is materialized as a value, so a field cannot hand over storage: there is
        // no slot for the move to land in, and the moved source has nothing left to copy from.
        // Reported here rather than at the conversion, so the '#move' itself is what the
        // diagnostic points at.
        SWC_RESULT(SemaCheck::noMoveRefType(sema, view.typeRef(), sema.node(child).codeRef()));
        SWC_RESULT(SemaCheck::noCopyOfNonCopyable(sema, view.nodeRef(), view.typeRef(), view.typeRef(), AstModifierFlagsE::Zero, true));

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

Result SemaHelpers::resolveDestructuringFieldIndices(Sema& sema, SmallVector<size_t>& outIndices, TypeRef sourceTypeRef, SourceViewRef patternSrcViewRef, std::span<const TokenRef> fieldNameRefs)
{
    outIndices.clear();
    outIndices.reserve(fieldNameRefs.size());

    const TypeInfo& sourceType = sema.typeMgr().get(sourceTypeRef);
    SWC_ASSERT(sourceType.isStruct() || sourceType.isAggregateStruct());

    for (const TokenRef fieldNameRef : fieldNameRefs)
    {
        SWC_ASSERT(fieldNameRef.isValid());
        const SourceCodeRef fieldCodeRef{patternSrcViewRef, fieldNameRef};
        const IdentifierRef fieldIdRef = sema.idMgr().addIdentifier(sema.ctx(), fieldCodeRef);

        size_t     fieldIndex = 0;
        const bool found      = sourceType.isStruct()
                                    ? sourceType.payloadSymStruct().tryGetFieldIndexByName(fieldIndex, fieldIdRef)
                                    : sourceType.tryGetAggregateMemberIndexByName(fieldIndex, sema.ctx(), fieldIdRef);
        if (!found)
        {
            Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_unknown_field, fieldCodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, sourceTypeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(fieldIdRef).name);
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (std::ranges::find(outIndices, fieldIndex) != outIndices.end())
        {
            Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_duplicate_field, fieldCodeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, sema.idMgr().get(fieldIdRef).name);
            diag.report(sema.ctx());
            return Result::Error;
        }

        outIndices.push_back(fieldIndex);
    }

    return Result::Continue;
}

bool SemaHelpers::intrinsicInitTreatsArgsAsStructTuple(Sema& sema, TypeRef fillTypeRef, const SmallVector<AstNodeRef>& args)
{
    if (args.empty() || !fillTypeRef.isValid())
        return false;

    if (!sema.typeMgr().get(fillTypeRef).isStruct())
        return false;
    if (args.size() != 1)
        return true;

    const SemaNodeView argView = sema.viewType(args.front());
    if (!argView.type())
        return true;
    if (argView.typeRef() == fillTypeRef)
        return false;

    return !argView.type()->isStruct() && !argView.type()->isAggregateStruct();
}

Result SemaHelpers::checkDivideByZeroConstant(Sema& sema, TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView)
{
    const TokenId canonicalOp = Token::canonicalBinary(op);
    if (canonicalOp != TokenId::SymSlash && canonicalOp != TokenId::SymPercent)
        return Result::Continue;

    const TypeRef aliasTypeRef = sema.typeMgr().get(nodeRightView.typeRef()).unwrap(sema.ctx(), nodeRightView.typeRef(), TypeExpandE::Alias);
    SWC_ASSERT(aliasTypeRef.isValid());
    const TypeInfo& type = sema.typeMgr().get(aliasTypeRef);

    if (type.isFloat() && nodeRightView.cst()->getFloat().isZero())
        return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());
    if (type.isIntLike() && nodeRightView.cst()->getIntLike().isZero())
        return SemaError::raiseDivZero(sema, nodeRef, nodeRightView.nodeRef());

    return Result::Continue;
}

bool SemaHelpers::isAliasPreservingNumericIntrinsic(TokenId tokenId)
{
    switch (tokenId)
    {
        case TokenId::IntrinsicAbs:
        case TokenId::IntrinsicMin:
        case TokenId::IntrinsicMax:
        case TokenId::IntrinsicRol:
        case TokenId::IntrinsicRor:
        case TokenId::IntrinsicByteSwap:
        case TokenId::IntrinsicBitCountNz:
        case TokenId::IntrinsicBitCountTz:
        case TokenId::IntrinsicBitCountLz:
        case TokenId::IntrinsicAtomicAdd:
        case TokenId::IntrinsicAtomicAnd:
        case TokenId::IntrinsicAtomicOr:
        case TokenId::IntrinsicAtomicXor:
        case TokenId::IntrinsicAtomicXchg:
        case TokenId::IntrinsicAtomicCmpXchg:
            return true;

        default:
            return false;
    }
}

bool SemaHelpers::resolveAggregateChildSlot(Sema& sema, AggregateChildSlot& outSlot, const TypeInfo& targetType, std::span<const AstNodeRef> children, AstNodeRef childRef)
{
    outSlot = {};

    const bool isStruct = targetType.isStruct();
    if (!isStruct && !targetType.isAggregateStruct())
        return false;

    const size_t memberCount = isStruct ? targetType.payloadSymStruct().fields().size() : targetType.payloadAggregate().types.size();
    size_t       index       = 0;
    if (!resolveAggregateChildIndex(sema, targetType, children, childRef, memberCount, index) || index >= memberCount)
        return false;

    if (!isStruct)
    {
        outSlot.index   = index;
        outSlot.typeRef = targetType.payloadAggregate().types[index];
        return true;
    }

    const SymbolVariable* field = targetType.payloadSymStruct().fields()[index];
    if (!field)
        return false;

    outSlot.field   = field;
    outSlot.index   = index;
    outSlot.typeRef = field->typeRef();
    return true;
}

TypeRef SemaHelpers::structuralTypeRefFromTypeNode(Sema& sema, AstNodeRef typeNodeRef)
{
    if (typeNodeRef.isInvalid())
        return TypeRef::invalid();

    // Generic deduction and overload matching sometimes run on a declaration AST before the
    // regular semantic payload for that exact type node is available. Reconstruct the
    // structural type when the stored view has not been produced yet.
    const TypeRef typeRef = sema.viewType(typeNodeRef).typeRef();
    if (typeRef.isValid())
        return typeRef;

    TypeManager&   typeMgr  = sema.typeMgr();
    const AstNode& typeNode = sema.node(typeNodeRef);

    if (const auto* builtinType = typeNode.safeCast<AstBuiltinType>())
        return typeMgr.builtinType(sema.token(builtinType->codeRef()).id);

    if (const auto* codeType = typeNode.safeCast<AstCodeType>())
    {
        // Bare '#code' and '#code(params)' have no payload type node: void block.
        if (codeType->nodeTypeRef.isInvalid())
            return typeMgr.addType(TypeInfo::makeCodeBlock(typeMgr.typeVoid()));
        const TypeRef payloadTypeRef = structuralTypeRefFromTypeNode(sema, codeType->nodeTypeRef);
        return payloadTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeCodeBlock(payloadTypeRef)) : TypeRef::invalid();
    }

    if (typeNode.is(AstNodeId::VariadicType))
        return typeMgr.typeVariadic();

    if (const auto* typedVariadicType = typeNode.safeCast<AstTypedVariadicType>())
    {
        const TypeRef elementTypeRef = structuralTypeRefFromTypeNode(sema, typedVariadicType->nodeTypeRef);
        return elementTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeTypedVariadic(elementTypeRef)) : TypeRef::invalid();
    }

    if (const auto* moveRefType = typeNode.safeCast<AstMoveRefType>())
    {
        const TypeRef pointeeTypeRef = structuralTypeRefFromTypeNode(sema, moveRefType->nodePointeeTypeRef);
        return pointeeTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeMoveReference(pointeeTypeRef)) : TypeRef::invalid();
    }

    if (const auto* valuePtrType = typeNode.safeCast<AstValuePointerType>())
    {
        const TypeRef pointeeTypeRef = structuralTypeRefFromTypeNode(sema, valuePtrType->nodePointeeTypeRef);
        return pointeeTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeValuePointer(pointeeTypeRef)) : TypeRef::invalid();
    }

    if (const auto* blockPtrType = typeNode.safeCast<AstBlockPointerType>())
    {
        const TypeRef pointeeTypeRef = structuralTypeRefFromTypeNode(sema, blockPtrType->nodePointeeTypeRef);
        return pointeeTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeBlockPointer(pointeeTypeRef)) : TypeRef::invalid();
    }

    if (const auto* sliceType = typeNode.safeCast<AstSliceType>())
    {
        const TypeRef elementTypeRef = structuralTypeRefFromTypeNode(sema, sliceType->nodePointeeTypeRef);
        return elementTypeRef.isValid() ? typeMgr.addType(TypeInfo::makeSlice(elementTypeRef)) : TypeRef::invalid();
    }

    if (const auto* namedType = typeNode.safeCast<AstNamedType>())
    {
        const SemaNodeView identView = sema.viewNodeTypeSymbol(namedType->nodeIdentRef);
        if (identView.typeRef().isValid())
            return identView.typeRef();
        if (identView.sym() && identView.sym()->isType())
            return identView.sym()->typeRef();

        if (const auto* ident = sema.node(namedType->nodeIdentRef).safeCast<AstIdentifier>())
        {
            MatchContext lookUpCxt;
            lookUpCxt.codeRef         = ident->codeRef();
            lookUpCxt.noWaitOnEmpty   = true;
            const IdentifierRef idRef = resolveIdentifier(sema, ident->codeRef());
            if (Match::match(sema, lookUpCxt, idRef) == Result::Continue)
            {
                for (const Symbol* sym : lookUpCxt.symbols())
                {
                    if (sym && sym->isType() && sym->typeRef().isValid())
                        return sym->typeRef();
                }
            }
        }
    }

    return TypeRef::invalid();
}

Result SemaHelpers::resolveStructLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = unwrapBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    const TypeInfo& targetType = sema.typeMgr().get(targetRef);
    if (targetType.isStruct())
        SWC_RESULT(sema.waitSemaCompleted(&targetType, childRef));

    AggregateChildSlot slot;
    if (resolveAggregateChildSlot(sema, slot, targetType, children, childRef))
        outTypeRef = slot.typeRef;
    return Result::Continue;
}

Result SemaHelpers::resolveArrayLikeChildBindingType(Sema& sema, std::span<const AstNodeRef> children, AstNodeRef childRef, TypeRef targetTypeRef, TypeRef& outTypeRef)
{
    outTypeRef              = TypeRef::invalid();
    const TypeRef targetRef = unwrapBindingType(sema.ctx(), targetTypeRef);
    if (!targetRef.isValid())
        return Result::Continue;

    const auto childIt = std::ranges::find(children, childRef);
    if (childIt == children.end())
        return Result::Continue;

    const size_t    childIndex = static_cast<size_t>(std::distance(children.begin(), childIt));
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

SWC_END_NAMESPACE();
