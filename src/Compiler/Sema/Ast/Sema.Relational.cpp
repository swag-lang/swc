#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Math/Helpers.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool constantPointerAddress(uint64_t& result, const ConstantValue& cst) noexcept
    {
        if (cst.isNull())
        {
            result = 0;
            return true;
        }

        if (cst.isValuePointer())
        {
            result = cst.getValuePointer();
            return true;
        }

        if (cst.isBlockPointer())
        {
            result = cst.getBlockPointer();
            return true;
        }

        return false;
    }

    std::pair<uint64_t, uint64_t> constantPointerAddresses(const SemaNodeView& leftView, const SemaNodeView& rightView)
    {
        uint64_t   leftAddress     = 0;
        uint64_t   rightAddress    = 0;
        const bool hasLeftAddress  = constantPointerAddress(leftAddress, *leftView.cst());
        const bool hasRightAddress = constantPointerAddress(rightAddress, *rightView.cst());
        SWC_ASSERT(hasLeftAddress && hasRightAddress);

        return {leftAddress, rightAddress};
    }

    // Fold type values using the runtime hash exported as TypeInfo.crc. A stricter
    // identity check would disagree with generated comparisons and Swag.typeCmp.
    // This hash ignores nullable qualifiers at every nesting depth.
    bool sameTypeValuePayload(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (leftTypeRef == rightTypeRef)
            return true;
        if (!leftTypeRef.isValid() || !rightTypeRef.isValid())
            return false;

        const TypeInfo& leftType  = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = sema.typeMgr().get(rightTypeRef);
        return leftType.runtimeHash(sema.ctx()) == rightType.runtimeHash(sema.ctx());
    }

    bool sameTypeInfoIdentity(Sema& sema, ConstantRef leftCstRef, ConstantRef rightCstRef)
    {
        const TypeRef leftTypeRef  = sema.cstMgr().makeTypeValue(sema, leftCstRef);
        const TypeRef rightTypeRef = sema.cstMgr().makeTypeValue(sema, rightCstRef);
        if (leftTypeRef.isValid() && rightTypeRef.isValid())
            return sameTypeValuePayload(sema, leftTypeRef, rightTypeRef);

        const auto* leftTypeInfo  = reinterpret_cast<const Runtime::TypeInfo*>(sema.cstMgr().get(leftCstRef).getValuePointer());
        const auto* rightTypeInfo = reinterpret_cast<const Runtime::TypeInfo*>(sema.cstMgr().get(rightCstRef).getValuePointer());
        if (!leftTypeInfo || !rightTypeInfo)
            return leftTypeInfo == rightTypeInfo;

        return leftTypeInfo->crc == rightTypeInfo->crc;
    }

    const TypeInfo* scalarReferencePayloadType(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type())
            return nullptr;

        const TypeInfo& normalizedType = SemaHelpers::aliasEnumType(sema, view);
        if (!normalizedType.isReference())
            return nullptr;

        const TypeInfo& payloadType = sema.typeMgr().get(normalizedType.payloadTypeRef());
        return payloadType.isScalarNumeric() ? &payloadType : nullptr;
    }

    ConstantRef readScalarReferenceConstant(Sema& sema, ConstantRef cstRef, TypeRef payloadTypeRef)
    {
        if (cstRef.isInvalid())
            return ConstantRef::invalid();

        const ConstantValue& refCst = sema.cstMgr().get(cstRef);
        SWC_ASSERT(refCst.isValuePointer());
        SWC_ASSERT(refCst.getValuePointer() != 0);

        const ConstantValue valueCst = ConstantValue::make(sema.ctx(), reinterpret_cast<const void*>(refCst.getValuePointer()), payloadTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        SWC_ASSERT(valueCst.isValid());

        return sema.cstMgr().addConstant(sema.ctx(), valueCst);
    }

    SemaNodeView scalarReadView(Sema& sema, const SemaNodeView& view)
    {
        const TypeInfo* payloadType = scalarReferencePayloadType(sema, view);
        if (!payloadType)
            return view;

        const TypeRef payloadTypeRef = payloadType->typeRef();
        SemaNodeView  result         = view;

        result.typeRef() = payloadTypeRef;
        result.type()    = payloadType;

        const ConstantRef scalarCstRef = readScalarReferenceConstant(sema, view.cstRef(), payloadTypeRef);
        if (scalarCstRef.isValid())
        {
            result.cstRef() = scalarCstRef;
            result.cst()    = &sema.cstMgr().get(scalarCstRef);
        }

        return result;
    }

    bool hasAliasOperand(const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return (nodeLeftView.type() && nodeLeftView.type()->isAlias()) ||
               (nodeRightView.type() && nodeRightView.type()->isAlias());
    }

    const SymbolStruct* specialOpOwnerStruct(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type())
            return nullptr;

        const TypeInfo* type = view.type();
        if (type->isReference())
        {
            const TypeRef typeRef = type->payloadTypeRef();
            if (!typeRef.isValid())
                return nullptr;

            type = &sema.typeMgr().get(typeRef);
        }

        if (const TypeInfo* unwrappedType = type->unwrapAliasEnumType(sema.ctx()))
            type = unwrappedType;
        if (!type->isStruct())
            return nullptr;

        return &type->payloadSymStruct();
    }

    void addMissingRelationalSpecOpHelp(Sema& sema, Diagnostic& diag, const SemaNodeView& leftView, SpecOpKind kind)
    {
        const SymbolStruct* ownerStruct = specialOpOwnerStruct(sema, leftView);
        if (ownerStruct)
            SemaSpecOp::addMissingDeclarationHelp(sema, diag, *ownerStruct, kind);
    }

    bool isStringCompareOperands(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (!nodeLeftView.type() || !nodeRightView.type())
            return false;

        const TypeInfo& leftType  = SemaHelpers::aliasEnumType(sema, nodeLeftView);
        const TypeInfo& rightType = SemaHelpers::aliasEnumType(sema, nodeRightView);
        return leftType.isString() && rightType.isString();
    }

    // Aggregate comparisons may call __sliceCmp for string or slice fields.
    // Register that helper before lowering emits the content comparison.
    Result attachAggregateContentCompareHelper(Sema& sema, const TypeInfo& compareType, const SourceCodeRef& codeRef)
    {
        if (!SemaHelpers::isByValueAggregateType(compareType))
            return Result::Continue;

        bool needsContentHelper = false;
        SWC_RESULT(SemaSpecOp::typeCompareNeedsContentHelper(sema, needsContentHelper, compareType.typeRef()));
        if (!needsContentHelper)
            return Result::Continue;

        return SemaHelpers::attachRuntimeSliceCmpFunctionToNode(sema, sema.curNodeRef(), codeRef);
    }

    bool sameSliceContent(const ConstantValue& leftCst, const ConstantValue& rightCst)
    {
        if (leftCst.getSliceCount() != rightCst.getSliceCount())
            return false;

        const std::span<const std::byte> leftBytes  = leftCst.getSlice();
        const std::span<const std::byte> rightBytes = rightCst.getSlice();
        if (leftBytes.size() != rightBytes.size())
            return false;

        return std::equal(leftBytes.begin(), leftBytes.end(), rightBytes.begin());
    }

    bool hasNullComparableOperandConstant(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cst() && nodeLeftView.cst()->isNullValue(sema.ctx()))
            return true;
        if (nodeRightView.cst() && nodeRightView.cst()->isNullValue(sema.ctx()))
            return true;

        return false;
    }

    struct ConstantEquality
    {
        bool known = true;
        bool equal = true;
    };

    ConstantRef aggregateFieldConstant(Sema& sema, const ConstantValue& source, TypeRef fieldTypeRef, uint64_t offset, size_t index)
    {
        if (source.isAggregate())
            return source.getAggregate()[index];
        const uint64_t size = sema.typeMgr().get(fieldTypeRef).sizeOf(sema.ctx());
        if (!size)
            return sema.cstMgr().addZeroPayloadConstant(sema.ctx(), fieldTypeRef);
        const auto bytes = source.isStruct() ? source.getStruct() : source.getArray();
        SWC_ASSERT(offset + size <= bytes.size());
        return ConstantHelpers::materializeStaticPayloadConstant(sema, fieldTypeRef, bytes.subspan(offset, size));
    }

    Result compareConstantFields(Sema& sema, ConstantEquality& result, TypeRef typeRef, ConstantRef leftRef, TypeRef rightTypeRef, ConstantRef rightRef)
    {
        const TypeInfo&      type  = sema.typeMgr().unwrapAliasEnumTypeOrSelf(sema.ctx(), typeRef);
        const ConstantValue& left  = sema.cstMgr().get(leftRef);
        const ConstantValue& right = sema.cstMgr().get(rightRef);
        if (!SemaHelpers::isByValueAggregateType(type))
        {
            result.equal = left.kind() == right.kind() && left.eq(right);
            return Result::Continue;
        }
        if (typeRef != rightTypeRef && SemaHelpers::sameRecordOrTupleShape(sema.ctx(), typeRef, rightTypeRef))
        {
            SmallVector<SemaHelpers::RecordOrTupleField> leftFields;
            SmallVector<SemaHelpers::RecordOrTupleField> rightFields;
            SemaHelpers::collectRecordOrTupleFields(sema.ctx(), leftFields, typeRef);
            SemaHelpers::collectRecordOrTupleFields(sema.ctx(), rightFields, rightTypeRef);
            for (size_t i = 0; i < leftFields.size(); ++i)
            {
                size_t j = i;
                if (leftFields[i].nameRef.isValid())
                    j = std::ranges::find(rightFields, leftFields[i].nameRef, &SemaHelpers::RecordOrTupleField::nameRef) - rightFields.begin();
                const auto& leftField  = leftFields[i];
                const auto& rightField = rightFields[j];
                SWC_RESULT(compareConstantFields(sema, result, leftField.typeRef, aggregateFieldConstant(sema, left, leftField.typeRef, leftField.offset, i),
                                                 rightField.typeRef, aggregateFieldConstant(sema, right, rightField.typeRef, rightField.offset, j)));
                if (!result.known || !result.equal)
                    return Result::Continue;
            }
            return Result::Continue;
        }
        if (type.isStruct())
        {
            SWC_RESULT(sema.waitSemaCompleted(&type, sema.curNodeRef()));
            const SymbolStruct& owner = type.payloadSymStruct();
            if (owner.isUnion() || owner.selfEqualsFunction(sema.ctx()))
            {
                result.known = false;
                return Result::Continue;
            }
        }
        size_t count;
        if (type.isStruct())
            count = type.payloadSymStruct().fields().size();
        else if (type.isAggregate())
            count = type.payloadAggregate().types.size();
        else
        {
            const TypeInfo& element = sema.typeMgr().get(type.payloadArrayElemTypeRef());
            const uint64_t  size    = element.sizeOf(sema.ctx());
            count                   = size ? type.sizeOf(sema.ctx()) / size : 0;
            if (!left.isAggregate() && !right.isAggregate() && (element.isIntLike() || element.isBool() || element.isAnyPointer()))
            {
                result.equal = left.eq(right);
                return Result::Continue;
            }
        }
        uint64_t offset = 0;
        for (size_t i = 0; i < count; ++i)
        {
            const TypeRef   fieldTypeRef = type.isStruct() ? type.payloadSymStruct().fields()[i]->typeRef() : type.isAggregate() ? type.payloadAggregate().types[i]
                                                                                                                                 : type.payloadArrayElemTypeRef();
            const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
            if (type.isStruct())
                offset = type.payloadSymStruct().fields()[i]->offset();
            else
                offset = Math::alignUpU64(offset, std::max<uint32_t>(fieldType.alignOf(sema.ctx()), 1));
            const ConstantRef leftField  = aggregateFieldConstant(sema, left, fieldTypeRef, offset, i);
            const ConstantRef rightField = aggregateFieldConstant(sema, right, fieldTypeRef, offset, i);
            SWC_RESULT(compareConstantFields(sema, result, fieldTypeRef, leftField, fieldTypeRef, rightField));
            if (!result.known || !result.equal)
                return Result::Continue;
            offset += fieldType.sizeOf(sema.ctx());
        }
        return Result::Continue;
    }

    Result constantFoldEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);
        const TypeInfo&    compareLeftType  = SemaHelpers::aliasEnumType(sema, compareLeftView);
        const TypeInfo&    compareRightType = SemaHelpers::aliasEnumType(sema, compareRightView);

        if (compareLeftType.isTypeValue() && compareRightType.isTypeValue())
        {
            SWC_ASSERT(compareLeftView.cst() != nullptr);
            SWC_ASSERT(compareRightView.cst() != nullptr);

            result = sema.cstMgr().cstBool(sameTypeValuePayload(sema, compareLeftView.cst()->getTypeValue(), compareRightView.cst()->getTypeValue()));
            return Result::Continue;
        }

        if (compareLeftType.isAnyTypeInfo(sema.ctx()) && compareRightType.isAnyTypeInfo(sema.ctx()))
        {
            result = sema.cstMgr().cstBool(sameTypeInfoIdentity(sema, compareLeftView.cstRef(), compareRightView.cstRef()));
            return Result::Continue;
        }

        if (compareLeftType.isString() && compareRightType.isString() && compareLeftView.cst()->isString() && compareRightView.cst()->isString())
        {
            result = sema.cstMgr().cstBool(compareLeftView.cst()->getString() == compareRightView.cst()->getString());
            return Result::Continue;
        }

        // Fold slice constants by content, as runtime comparison does. A null
        // operand carries no slice payload and falls through to the null case.
        if (compareLeftType.isSlice() && compareRightType.isSlice() && compareLeftView.cst()->isSlice() && compareRightView.cst()->isSlice())
        {
            result = sema.cstMgr().cstBool(sameSliceContent(*compareLeftView.cst(), *compareRightView.cst()));
            return Result::Continue;
        }

        if (compareLeftView.cst()->isNullValue(sema.ctx()) || compareRightView.cst()->isNullValue(sema.ctx()))
        {
            result = sema.cstMgr().cstBool(compareLeftView.cst()->isNullValue(sema.ctx()) &&
                                           compareRightView.cst()->isNullValue(sema.ctx()));
            return Result::Continue;
        }

        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            const auto [leftAddress, rightAddress] = constantPointerAddresses(compareLeftView, compareRightView);

            result = sema.cstMgr().cstBool(leftAddress == rightAddress);
            return Result::Continue;
        }

        if (SemaHelpers::isByValueAggregateType(compareLeftType))
        {
            ConstantEquality comparison;
            SWC_RESULT(compareConstantFields(sema, comparison, compareLeftView.typeRef(), compareLeftView.cstRef(), compareRightView.typeRef(), compareRightView.cstRef()));
            if (comparison.known)
                result = sema.cstMgr().cstBool(comparison.equal);
            return Result::Continue;
        }

        ConstantRef leftCstRef  = compareLeftView.cstRef();
        ConstantRef rightCstRef = compareRightView.cstRef();
        if (!hasAliasOperand(compareLeftView, compareRightView))
            SWC_RESULT(Cast::promoteConstants(sema, compareLeftView, compareRightView, leftCstRef, rightCstRef));

        // Compare float values rather than constant identities: +0.0 and -0.0
        // are distinct constants with equal values.
        const ConstantValue& left = sema.cstMgr().get(leftCstRef);
        if (left.isFloat())
        {
            const ConstantValue& right = sema.cstMgr().get(rightCstRef);

            result = sema.cstMgr().cstBool(left.eq(right));
            return Result::Continue;
        }

        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        result = sema.cstMgr().cstBool(leftCstRef == rightCstRef);
        return Result::Continue;
    }

    enum class OrderedCompareOp : uint8_t
    {
        Less,
        LessEqual,
        Greater,
        GreaterEqual,
    };

    Result constantFoldOrderedCompare(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView, OrderedCompareOp op)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);

        const TypeInfo& compareLeftType  = SemaHelpers::aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = SemaHelpers::aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            const auto [leftAddress, rightAddress] = constantPointerAddresses(compareLeftView, compareRightView);

            bool cmpResult = false;
            switch (op)
            {
                case OrderedCompareOp::Less: cmpResult = leftAddress < rightAddress; break;
                case OrderedCompareOp::LessEqual: cmpResult = leftAddress <= rightAddress; break;
                case OrderedCompareOp::Greater: cmpResult = leftAddress > rightAddress; break;
                case OrderedCompareOp::GreaterEqual: cmpResult = leftAddress >= rightAddress; break;
            }

            result = sema.cstMgr().cstBool(cmpResult);
            return Result::Continue;
        }

        ConstantRef leftCstRef  = compareLeftView.cstRef();
        ConstantRef rightCstRef = compareRightView.cstRef();
        if (!hasAliasOperand(compareLeftView, compareRightView))
            SWC_RESULT(Cast::promoteConstants(sema, compareLeftView, compareRightView, leftCstRef, rightCstRef));

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);

        // Float NaN comparisons must always go through the actual compare; integer/etc.
        // can short-circuit when both refs already point at the same constant.
        if (!leftCst.isFloat() && leftCstRef == rightCstRef)
        {
            const bool equalCaseValue = op == OrderedCompareOp::LessEqual || op == OrderedCompareOp::GreaterEqual;

            result = sema.cstMgr().cstBool(equalCaseValue);
            return Result::Continue;
        }

        bool cmpResult = false;
        switch (op)
        {
            case OrderedCompareOp::Less: cmpResult = leftCst.lt(rightCst); break;
            case OrderedCompareOp::LessEqual: cmpResult = leftCst.le(rightCst); break;
            case OrderedCompareOp::Greater: cmpResult = leftCst.gt(rightCst); break;
            case OrderedCompareOp::GreaterEqual: cmpResult = leftCst.ge(rightCst); break;
        }

        result = sema.cstMgr().cstBool(cmpResult);
        return Result::Continue;
    }

    Result constantFoldLess(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return constantFoldOrderedCompare(sema, result, nodeLeftView, nodeRightView, OrderedCompareOp::Less);
    }

    Result constantFoldLessEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return constantFoldOrderedCompare(sema, result, nodeLeftView, nodeRightView, OrderedCompareOp::LessEqual);
    }

    Result constantFoldGreater(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return constantFoldOrderedCompare(sema, result, nodeLeftView, nodeRightView, OrderedCompareOp::Greater);
    }

    Result constantFoldGreaterEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        return constantFoldOrderedCompare(sema, result, nodeLeftView, nodeRightView, OrderedCompareOp::GreaterEqual);
    }

    Result constantFoldCompareEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);

        const TypeInfo& compareLeftType  = SemaHelpers::aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = SemaHelpers::aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            const auto [leftAddress, rightAddress] = constantPointerAddresses(compareLeftView, compareRightView);

            const int compareResult = leftAddress < rightAddress
                                          ? -1
                                      : leftAddress > rightAddress
                                          ? 1
                                          : 0;

            result = sema.cstMgr().cstS32(compareResult);
            return Result::Continue;
        }

        ConstantRef leftCstRef  = compareLeftView.cstRef();
        ConstantRef rightCstRef = compareRightView.cstRef();
        if (!hasAliasOperand(compareLeftView, compareRightView))
            SWC_RESULT(Cast::promoteConstants(sema, compareLeftView, compareRightView, leftCstRef, rightCstRef));

        const ConstantValue& left  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& right = sema.cstMgr().get(rightCstRef);

        int val;
        if (leftCstRef == rightCstRef)
            val = 0;
        else if (left.lt(right))
            val = -1;
        else if (right.lt(left))
            val = 1;
        else
            val = 0;

        result = sema.cstMgr().cstS32(val);
        return Result::Continue;
    }

    Result constantFold(Sema& sema, ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
                return constantFoldEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymBangEqual:
                SWC_RESULT(constantFoldEqual(sema, result, nodeLeftView, nodeRightView));
                if (result.isValid())
                    result = sema.cstMgr().cstNegBool(result);
                return Result::Continue;

            case TokenId::SymLess:
                return constantFoldLess(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqual:
                return constantFoldLessEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreater:
                return constantFoldGreater(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymGreaterEqual:
                return constantFoldGreaterEqual(sema, result, nodeLeftView, nodeRightView);

            case TokenId::SymLessEqualGreater:
                return constantFoldCompareEqual(sema, result, nodeLeftView, nodeRightView);

            default:
                SWC_UNREACHABLE();
        }
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);
        if (SemaHelpers::sameRecordOrTupleShape(sema.ctx(), compareLeftView.typeRef(), compareRightView.typeRef()))
            return Result::Continue;
        if (SemaHelpers::aliasType(sema, compareLeftView).isScalarNumeric() && SemaHelpers::aliasType(sema, compareRightView).isScalarNumeric())
            return Result::Continue;
        if (isStringCompareOperands(sema, compareLeftView, compareRightView))
            return Result::Continue;
        if (compareLeftView.type()->isType() && compareRightView.type()->isType())
            return Result::Continue;
        if (compareLeftView.type()->isNull() && compareRightView.type()->isPointerLikeAliasAware(sema.ctx()))
            return Result::Continue;
        if (compareLeftView.type()->isPointerLikeAliasAware(sema.ctx()) && compareRightView.type()->isNull())
            return Result::Continue;

        const TypeInfo& compareLeftType  = SemaHelpers::aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = SemaHelpers::aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
            return Result::Continue;
        if (compareLeftType.isAnyTypeInfo(sema.ctx()) && compareRightType.isAnyTypeInfo(sema.ctx()))
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
        addMissingRelationalSpecOpHelp(sema, diag, nodeLeftView, SpecOpKind::OpEquals);
        diag.report(sema.ctx());

        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);
        if (SemaHelpers::aliasType(sema, compareLeftView).isScalarNumeric() && SemaHelpers::aliasType(sema, compareRightView).isScalarNumeric())
            return Result::Continue;

        const TypeInfo& compareLeftType  = SemaHelpers::aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = SemaHelpers::aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
        addMissingRelationalSpecOpHelp(sema, diag, nodeLeftView, SpecOpKind::OpCompare);
        diag.report(sema.ctx());

        return Result::Error;
    }

    namespace
    {
        void enumForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return;
            if (self.type()->isEnum() && !other.type()->isEnum())
                Cast::convertEnumToUnderlying(sema, self);
        }

        void nullForEquality(Sema& sema, const SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return;
            if (self.type()->isNull() && other.type()->isPointerLikeAliasAware(sema.ctx()))
                Cast::createCast(sema, other.typeRef(), self.nodeRef());
        }

        Result typeInfoForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return Result::Continue;

            // Preserve nullable qualifiers when comparing typeinfo: equality does
            // not dereference, and the non-null default would reject valid operands.
            TypeRef typeInfoTargetRef = sema.typeMgr().typeTypeInfo();
            if (SemaHelpers::aliasEnumType(sema, self).isNullable())
            {
                TypeInfo nullableTypeInfo = sema.typeMgr().get(typeInfoTargetRef);
                nullableTypeInfo.addFlag(TypeInfoFlagsE::Nullable);
                typeInfoTargetRef = sema.typeMgr().addType(nullableTypeInfo);
            }

            const TypeInfo& otherType                     = SemaHelpers::aliasEnumType(sema, other);
            const bool      otherIsRuntimeTypeInfoPointer = sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), other.typeRef());
            const bool      otherIsTypeLike               = otherType.isAnyTypeInfo(sema.ctx()) || otherIsRuntimeTypeInfoPointer || other.type()->isTypeValue();
            if (self.type()->isTypeValue() && otherIsTypeLike)
            {
                SWC_RESULT(Cast::cast(sema, self, typeInfoTargetRef, CastKind::Implicit));
                return Result::Continue;
            }

            if (sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), self.typeRef()) && otherIsTypeLike)
            {
                SWC_RESULT(Cast::cast(sema, self, typeInfoTargetRef, CastKind::Explicit));
                return Result::Continue;
            }

            return Result::Continue;
        }

        // Read a struct reference as its value unless the other operand is a pointer.
        // A reference to a pointer reads that pointer when compared to null.
        Result structReferenceForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return Result::Continue;

            const TypeInfo& selfType = *self.type();
            if (!selfType.isReference())
                return Result::Continue;

            const TypeInfo& otherType = SemaHelpers::aliasEnumType(sema, other);
            if (otherType.isAnyPointer())
                return Result::Continue;

            const TypeRef payloadTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), selfType.payloadTypeRef());
            if (!payloadTypeRef.isValid())
                return Result::Continue;

            const TypeInfo& payloadType = sema.typeMgr().get(payloadTypeRef);
            const bool      readStruct  = payloadType.isStruct();
            const bool      readPointer = payloadType.isAnyPointer() && otherType.isNull();
            if (!readStruct && !readPointer)
                return Result::Continue;

            return Cast::cast(sema, self, selfType.payloadTypeRef(), CastKind::Implicit);
        }

        bool isAggregateEqualityOperand(const TypeInfo& type)
        {
            return type.isArrayOrSlice() || type.isStruct() || type.isAggregate();
        }

        Result aggregateLiteralForEquality(Sema& sema, SemaNodeView& literalView, SemaNodeView& typedView)
        {
            if (!literalView.type() || !typedView.type())
                return Result::Continue;

            const TypeInfo& literalType = SemaHelpers::aliasEnumType(sema, literalView);
            const TypeInfo& typedType   = SemaHelpers::aliasEnumType(sema, typedView);
            const bool      arrayMatch  = literalType.isAggregateArray() && typedType.isArrayOrSlice();
            const bool      structMatch = literalType.isAggregateStruct() && typedType.isStruct();
            if (!arrayMatch && !structMatch)
                return Result::Continue;

            TypeRef targetTypeRef = typedView.typeRef();
            if (typedView.type()->isSlice() && !typedView.type()->isConst())
            {
                TypeInfo readOnlyType = *typedView.type();
                readOnlyType.addFlag(TypeInfoFlagsE::Const);

                targetTypeRef = sema.typeMgr().addType(readOnlyType);
                SWC_RESULT(Cast::castIfNeeded(sema, typedView, targetTypeRef, CastKind::Implicit));
            }

            return Cast::cast(sema, literalView, targetTypeRef, CastKind::Implicit);
        }

        Result aggregateForEquality(Sema& sema, SemaNodeView& leftView, SemaNodeView& rightView)
        {
            if (!leftView.type() || !rightView.type() || leftView.typeRef() == rightView.typeRef())
                return Result::Continue;

            const TypeInfo& leftType  = SemaHelpers::aliasEnumType(sema, leftView);
            const TypeInfo& rightType = SemaHelpers::aliasEnumType(sema, rightView);
            if (!isAggregateEqualityOperand(leftType) || !isAggregateEqualityOperand(rightType))
                return Result::Continue;

            CastRequest leftRequest(CastKind::Implicit);
            leftRequest.errorNodeRef = leftView.nodeRef();
            leftRequest.probing      = true;

            const Result leftResult = Cast::castAllowed(sema, leftRequest, leftView.typeRef(), rightView.typeRef());
            if (leftResult == Result::Pause)
                return Result::Pause;
            if (leftResult == Result::Continue)
                return Cast::castIfNeeded(sema, leftView, rightView.typeRef(), CastKind::Implicit);

            CastRequest rightRequest(CastKind::Implicit);
            rightRequest.errorNodeRef = rightView.nodeRef();
            rightRequest.probing      = true;

            const Result rightResult = Cast::castAllowed(sema, rightRequest, rightView.typeRef(), leftView.typeRef());
            if (rightResult == Result::Pause)
                return Result::Pause;
            if (rightResult == Result::Continue)
                return Cast::castIfNeeded(sema, rightView, leftView.typeRef(), CastKind::Implicit);

            return Result::Continue;
        }

        Result equalityPointerTargetTypeRef(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& pointerView, const SemaNodeView& referenceView)
        {
            outTypeRef = TypeRef::invalid();
            if (!pointerView.type() || !referenceView.type())
                return Result::Continue;

            const TypeInfo& pointerType   = SemaHelpers::aliasEnumType(sema, pointerView);
            const TypeInfo& referenceType = SemaHelpers::aliasEnumType(sema, referenceView);
            if (!pointerType.isAnyPointer() || !referenceType.isReference())
                return Result::Continue;

            TypeInfoFlags targetFlags = pointerType.flags();
            if (referenceType.isConst())
                targetFlags.add(TypeInfoFlagsE::Const);

            const TypeInfo targetType    = pointerType.isBlockPointer() ? TypeInfo::makeBlockPointer(pointerType.payloadTypeRef(), targetFlags) : TypeInfo::makeValuePointer(pointerType.payloadTypeRef(), targetFlags);
            const TypeRef  targetTypeRef = sema.typeMgr().addType(targetType);

            CastRequest castRequest(CastKind::Implicit);
            castRequest.errorNodeRef = referenceView.nodeRef();

            const Result result = Cast::castAllowed(sema, castRequest, referenceView.typeRef(), targetTypeRef);
            if (result == Result::Pause)
                return result;
            if (result != Result::Continue)
                return Result::Continue;

            outTypeRef = targetTypeRef;
            return Result::Continue;
        }

        Result pointerReferenceForEquality(Sema& sema, SemaNodeView& pointerView, SemaNodeView& referenceView)
        {
            TypeRef targetTypeRef = TypeRef::invalid();
            SWC_RESULT(equalityPointerTargetTypeRef(sema, targetTypeRef, pointerView, referenceView));
            if (!targetTypeRef.isValid())
                return Result::Continue;

            SWC_RESULT(Cast::castIfNeeded(sema, pointerView, targetTypeRef, CastKind::Implicit));
            SWC_RESULT(Cast::cast(sema, referenceView, targetTypeRef, CastKind::Implicit));

            return Result::Continue;
        }
    }

    // Comparisons never write through operands. Widen the non-null side before
    // promotion so it can compare against a nullable operand.
    Result widenNullableCompareOperand(Sema& sema, SemaNodeView& bareView, const SemaNodeView& nullableView)
    {
        if (!bareView.type() || !nullableView.type())
            return Result::Continue;

        const TypeInfo& bareType  = SemaHelpers::aliasEnumType(sema, bareView);
        const TypeInfo& otherType = SemaHelpers::aliasEnumType(sema, nullableView);
        if (!otherType.isNullable() || !bareType.isNonNullable())
            return Result::Continue;

        TypeInfo widened = bareType;
        widened.addFlag(TypeInfoFlagsE::Nullable);
        return Cast::castIfNeeded(sema, bareView, sema.typeMgr().addType(widened), CastKind::Implicit);
    }

    Result promote(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        SWC_UNUSED(node);

        SWC_RESULT(widenNullableCompareOperand(sema, nodeLeftView, nodeRightView));
        SWC_RESULT(widenNullableCompareOperand(sema, nodeRightView, nodeLeftView));

        const bool orderedCompare = op == TokenId::SymLess ||
                                    op == TokenId::SymLessEqual ||
                                    op == TokenId::SymGreater ||
                                    op == TokenId::SymGreaterEqual ||
                                    op == TokenId::SymLessEqualGreater;

        if (Token::isOpEquality(op) && nodeLeftView.typeRef() != nodeRightView.typeRef() && SemaHelpers::sameRecordOrTupleShape(sema.ctx(), nodeLeftView.typeRef(), nodeRightView.typeRef()))
            return Result::Continue;

        const bool readScalarReference = orderedCompare &&
                                         (scalarReferencePayloadType(sema, nodeLeftView) ||
                                          scalarReferencePayloadType(sema, nodeRightView));
        if (!readScalarReference)
            SWC_RESULT(Cast::castPromote(sema, nodeLeftView, nodeRightView, CastKind::Promotion));

        if (orderedCompare && nodeLeftView.typeRef() == nodeRightView.typeRef())
        {
            const TypeInfo& leftType  = SemaHelpers::aliasType(sema, nodeLeftView);
            const TypeInfo& rightType = SemaHelpers::aliasType(sema, nodeRightView);
            if (leftType.isEnum() && rightType.isEnum())
            {
                Cast::convertEnumToUnderlying(sema, nodeLeftView);
                Cast::convertEnumToUnderlying(sema, nodeRightView);
            }
        }

        if (op == TokenId::SymEqualEqual || op == TokenId::SymBangEqual)
        {
            SWC_RESULT(structReferenceForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(structReferenceForEquality(sema, nodeRightView, nodeLeftView));

            enumForEquality(sema, nodeLeftView, nodeRightView);
            enumForEquality(sema, nodeRightView, nodeLeftView);

            nullForEquality(sema, nodeLeftView, nodeRightView);
            nullForEquality(sema, nodeRightView, nodeLeftView);

            SWC_RESULT(typeInfoForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(typeInfoForEquality(sema, nodeRightView, nodeLeftView));

            SWC_RESULT(aggregateLiteralForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(aggregateLiteralForEquality(sema, nodeRightView, nodeLeftView));
            SWC_RESULT(aggregateForEquality(sema, nodeLeftView, nodeRightView));

            SWC_RESULT(pointerReferenceForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(pointerReferenceForEquality(sema, nodeRightView, nodeLeftView));
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        // Element-wise simd compares need the same vector type on both sides,
        // and the three-way compare has no lane form.
        const TypeInfo& leftType  = SemaHelpers::aliasType(sema, nodeLeftView);
        const TypeInfo& rightType = SemaHelpers::aliasType(sema, nodeRightView);
        if (leftType.isSimd() || rightType.isSimd())
        {
            const bool sameShape = leftType.isSimd() && rightType.isSimd() &&
                                   leftType.payloadSimdLaneTypeRef() == rightType.payloadSimdLaneTypeRef() &&
                                   leftType.payloadSimdLaneCount() == rightType.payloadSimdLaneCount();
            if (sameShape && op != TokenId::SymLessEqualGreater)
                return Result::Continue;

            Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
            diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
            diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
            diag.report(sema.ctx());

            return Result::Error;
        }

        if (Token::isOpEquality(op))
            return checkEqualEqual(sema, node, nodeLeftView, nodeRightView);

        SWC_INTERNAL_CHECK(Token::isOpOrdering(op));
        return checkCompareEqual(sema, node, nodeLeftView, nodeRightView);
    }
}

Result AstRelationalExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeLeftRef && SemaHelpers::canUseContextualBinding(sema, nodeRightRef))
    {
        const SemaNodeView nodeLeftView = sema.viewType(nodeLeftRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeLeftView.typeRef());
        SemaHelpers::preferContextualAutoMemberBindingType(sema, nodeRightRef);
        sema.pushFramePopOnPostChild(std::move(frame), nodeRightRef);
    }

    return Result::Continue;
}

Result AstRelationalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);
    const Token& tok           = sema.token({srcViewRef(), tokRef()});

    if (tok.id == TokenId::SymEqualEqual || tok.id == TokenId::SymBangEqual)
    {
        if (nodeRightView.type() && nodeRightView.type()->isNull())
            SWC_RESULT(SemaCheck::typePattern(sema, nodeLeftRef));
        if (nodeLeftView.type() && nodeLeftView.type()->isNull())
            SWC_RESULT(SemaCheck::typePattern(sema, nodeRightRef));
    }

    SemaHelpers::normalizeTypeOperandToConstant(sema, nodeLeftView);
    SemaHelpers::normalizeTypeOperandToConstant(sema, nodeRightView);
    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeLeftView));
    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
    SemaHelpers::normalizeTypeOperandToConstant(sema, nodeLeftView);
    SemaHelpers::normalizeTypeOperandToConstant(sema, nodeRightView);
    sema.setIsValue(*this);

    // A late slot's exposed type is non-null while its storage starts at zero.
    // Null comparison tests presence and must bypass the late-read guard.
    if (tok.id == TokenId::SymEqualEqual || tok.id == TokenId::SymBangEqual)
    {
        if (nodeLeftView.type() && nodeLeftView.type()->isNull())
            SemaHelpers::clearLateFieldReadGuard(sema, nodeRightRef);
        if (nodeRightView.type() && nodeRightView.type()->isNull())
            SemaHelpers::clearLateFieldReadGuard(sema, nodeLeftRef);
    }

    // An interface value is an object view, while a type operand is metadata. Comparing their
    // storage does not test the object's concrete type; that operation is expressed with 'is'.
    if (Token::isOpEquality(tok.id))
    {
        const TypeInfo& leftType  = SemaHelpers::aliasEnumType(sema, nodeLeftView);
        const TypeInfo& rightType = SemaHelpers::aliasEnumType(sema, nodeRightView);
        if ((leftType.isInterface() && rightType.isTypeValue()) || (rightType.isInterface() && leftType.isTypeValue()))
        {
            Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, codeRef());
            diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
            diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    bool handledSpecialOp = false;
    SWC_RESULT(SemaSpecOp::tryResolveRelational(sema, *this, nodeLeftView, handledSpecialOp));
    if (handledSpecialOp)
        return Result::Continue;

    SWC_RESULT(promote(sema, tok.id, *this, nodeLeftView, nodeRightView));

    SWC_RESULT(check(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // SIMD comparisons produce unsigned all-ones mask lanes where they hold.
    // The mask keeps the input shape and does not fold to a constant.
    {
        const TypeInfo& leftCmpType = SemaHelpers::aliasType(sema, nodeLeftView);
        if (leftCmpType.isSimd())
        {
            const TypeInfo& laneType = sema.typeMgr().get(leftCmpType.payloadSimdLaneTypeRef());
            const uint32_t  laneBits = laneType.isFloat() ? laneType.payloadFloatBits() : laneType.payloadIntBits();
            const TypeRef   maskLane = sema.typeMgr().typeInt(laneBits, TypeInfo::Sign::Unsigned);

            sema.setType(sema.curNodeRef(), sema.typeMgr().addType(TypeInfo::makeSimd(maskLane, leftCmpType.payloadSimdLaneCount())));
            return Result::Continue;
        }
    }

    if (tok.id == TokenId::SymLessEqualGreater)
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeInt(32, TypeInfo::Sign::Signed));
    else
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());

    bool canConstantFold = nodeLeftView.cstRef().isValid() && nodeRightView.cstRef().isValid();
    if (canConstantFold)
    {
        ConstantRef result;
        SWC_RESULT(constantFold(sema, result, tok.id, nodeLeftView, nodeRightView));

        canConstantFold = result.isValid();
        if (canConstantFold)
            sema.setConstant(sema.curNodeRef(), result);
    }

    if (!canConstantFold &&
        (tok.id == TokenId::SymEqualEqual || tok.id == TokenId::SymBangEqual) &&
        !hasNullComparableOperandConstant(sema, nodeLeftView, nodeRightView))
    {
        if (nodeLeftView.type() && nodeRightView.type())
        {
            const TypeInfo& compareLeftType  = SemaHelpers::aliasEnumType(sema, nodeLeftView);
            const TypeInfo& compareRightType = SemaHelpers::aliasEnumType(sema, nodeRightView);

            for (const SemaNodeView* operand : {&nodeLeftView, &nodeRightView})
            {
                const TypeInfo& type = *operand->type();
                const uint64_t  size = type.sizeOf(sema.ctx());
                if (SemaHelpers::isByValueAggregateType(type) && (size == 1 || size == 2 || size == 4 || size == 8))
                    SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, operand->nodeRef(), sema.node(operand->nodeRef()), operand->typeRef(), "__compare_operand_storage"));
            }

            // Type checking has already unified slice element types and sizes.
            if (compareLeftType.isString() && compareRightType.isString())
                SWC_RESULT(SemaHelpers::attachRuntimeStringCmpFunctionToNode(sema, sema.curNodeRef(), codeRef()));
            else if (compareLeftType.isSlice() && compareRightType.isSlice())
                SWC_RESULT(SemaHelpers::attachRuntimeSliceCmpFunctionToNode(sema, sema.curNodeRef(), codeRef()));
            else
                SWC_RESULT(attachAggregateContentCompareHelper(sema, compareLeftType, codeRef()));
        }
        else
        {
            const TypeRef compareLeftTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), nodeLeftView.typeRef());
            SWC_RESULT(attachAggregateContentCompareHelper(sema, sema.typeMgr().get(compareLeftTypeRef), codeRef()));
        }
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
