#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Support/Report/Assert.h"
#include "Support/Report/Diagnostic.h"

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
            case AstNodeId::ReferenceType:
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

    void normalizeTypeOperandToConstant(Sema& sema, SemaNodeView& view)
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
            {
                if (ident->hasFlag(AstIdentifierFlagsE::GenericTypeBinding))
                    isTypeExpr = true;
                else
                {
                    const SemaNodeView symbolView = sema.viewNodeTypeSymbol(targetRef);
                    isTypeExpr                    = symbolView.sym() && symbolView.sym()->isType();
                }
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

    bool isNullComparableConstant(Sema& sema, const ConstantValue& cst) noexcept
    {
        if (cst.isNull())
            return true;
        if (cst.isValuePointer())
            return cst.getValuePointer() == 0;
        if (cst.isBlockPointer())
            return cst.getBlockPointer() == 0;
        if (cst.isStruct() && cst.typeRef().isValid())
        {
            const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
            if (typeInfo.isAny())
            {
                const std::span<const std::byte> bytes = cst.getStruct();
                if (bytes.size() != sizeof(Runtime::Any))
                    return false;

                Runtime::Any runtimeAny{};
                std::memcpy(&runtimeAny, bytes.data(), sizeof(runtimeAny));
                return runtimeAny.type == nullptr && runtimeAny.value == nullptr;
            }

            if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
            {
                const std::span<const std::byte> bytes = cst.getStruct();
                if (bytes.size() != sizeof(Runtime::ClosureValue))
                    return false;

                const auto* closureValue = reinterpret_cast<const Runtime::ClosureValue*>(bytes.data());
                if (closureValue->invoke)
                    return false;

                for (const uint8_t byte : closureValue->capture)
                {
                    if (byte != 0)
                        return false;
                }

                return true;
            }
        }
        return false;
    }

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

    bool sameTypeValuePayload(Sema& sema, TypeRef leftTypeRef, TypeRef rightTypeRef)
    {
        if (leftTypeRef == rightTypeRef)
            return true;
        if (!leftTypeRef.isValid() || !rightTypeRef.isValid())
            return false;

        const TypeInfo& leftType  = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType = sema.typeMgr().get(rightTypeRef);
        if (leftType.kind() != rightType.kind())
            return false;
        if (leftType.flags() != rightType.flags())
            return false;

        if (leftType.isFunction())
            return leftType.payloadSymFunction().sameTypeSignature(rightType.payloadSymFunction());

        return leftType == rightType;
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

    ConstantRef anyStoredTypeInfoConstant(Sema& sema, ConstantRef anyCstRef)
    {
        const ConstantValue& anyCst = sema.cstMgr().get(anyCstRef);
        if (!anyCst.isStruct())
            return ConstantRef::invalid();

        const std::span<const std::byte> anyBytes = anyCst.getStruct();
        if (anyBytes.size() != sizeof(Runtime::Any))
            return ConstantRef::invalid();

        Runtime::Any runtimeAny{};
        std::memcpy(&runtimeAny, anyBytes.data(), sizeof(runtimeAny));

        ConstantValue typeCst = ConstantValue::makeValuePointer(sema.ctx(), sema.typeMgr().structTypeInfo(), reinterpret_cast<uint64_t>(runtimeAny.type), TypeInfoFlagsE::Const);
        typeCst.setTypeRef(sema.typeMgr().typeTypeInfo());
        return sema.cstMgr().addConstant(sema.ctx(), typeCst);
    }

    bool shouldReadScalarReference(Sema& sema, TypeRef typeRef)
    {
        const TypeRef normalizedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (!normalizedTypeRef.isValid())
            return false;

        const TypeInfo& normalizedType = sema.typeMgr().get(normalizedTypeRef);
        if (!normalizedType.isReference())
            return false;

        return sema.typeMgr().get(normalizedType.payloadTypeRef()).isScalarNumeric();
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
        if (!shouldReadScalarReference(sema, view.typeRef()))
            return view;

        SemaNodeView  result           = view;
        const TypeRef normalizedRef    = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        const TypeRef payloadTypeRef   = sema.typeMgr().get(normalizedRef).payloadTypeRef();
        result.typeRef()               = payloadTypeRef;
        result.type()                  = &sema.typeMgr().get(payloadTypeRef);
        const ConstantRef scalarCstRef = readScalarReferenceConstant(sema, view.cstRef(), payloadTypeRef);
        if (scalarCstRef.isValid())
        {
            result.cstRef() = scalarCstRef;
            result.cst()    = &sema.cstMgr().get(scalarCstRef);
        }

        return result;
    }

    const TypeInfo& aliasEnumType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        return sema.typeMgr().get(typeRef);
    }

    const TypeInfo& aliasType(Sema& sema, const SemaNodeView& view)
    {
        const TypeRef typeRef = sema.typeMgr().get(view.typeRef()).unwrap(sema.ctx(), view.typeRef(), TypeExpandE::Alias);
        SWC_ASSERT(typeRef.isValid());
        return sema.typeMgr().get(typeRef);
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

        TypeRef         typeRef   = view.typeRef();
        const TypeInfo& valueType = sema.typeMgr().get(typeRef);
        if (valueType.isReference())
            typeRef = valueType.payloadTypeRef();

        typeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
        if (!typeRef.isValid())
            return nullptr;

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (!type.isStruct())
            return nullptr;

        return &type.payloadSymStruct();
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

        const TypeRef   leftTypeRef  = sema.typeMgr().unwrapAliasEnum(sema.ctx(), nodeLeftView.typeRef());
        const TypeRef   rightTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), nodeRightView.typeRef());
        const TypeInfo& leftType     = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType    = sema.typeMgr().get(rightTypeRef);
        return leftType.isString() && rightType.isString();
    }

    bool hasNullComparableOperandConstant(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cst() && isNullComparableConstant(sema, *nodeLeftView.cst()))
            return true;
        if (nodeRightView.cst() && isNullComparableConstant(sema, *nodeRightView.cst()))
            return true;
        return false;
    }

    Result constantFoldEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);
        const TypeInfo&    compareLeftType  = aliasEnumType(sema, compareLeftView);
        const TypeInfo&    compareRightType = aliasEnumType(sema, compareRightView);

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

        const bool leftIsAny       = compareLeftType.isAny();
        const bool rightIsAny      = compareRightType.isAny();
        const bool leftIsTypeLike  = compareLeftType.isAnyTypeInfo(sema.ctx()) || compareLeftType.isTypeValue();
        const bool rightIsTypeLike = compareRightType.isAnyTypeInfo(sema.ctx()) || compareRightType.isTypeValue();

        if (leftIsAny && rightIsTypeLike)
        {
            const ConstantRef anyTypeCstRef = anyStoredTypeInfoConstant(sema, compareLeftView.cstRef());
            if (anyTypeCstRef.isValid())
            {
                result = sema.cstMgr().cstBool(sameTypeInfoIdentity(sema, anyTypeCstRef, compareRightView.cstRef()));
                return Result::Continue;
            }
        }

        if (rightIsAny && leftIsTypeLike)
        {
            const ConstantRef anyTypeCstRef = anyStoredTypeInfoConstant(sema, compareRightView.cstRef());
            if (anyTypeCstRef.isValid())
            {
                result = sema.cstMgr().cstBool(sameTypeInfoIdentity(sema, compareLeftView.cstRef(), anyTypeCstRef));
                return Result::Continue;
            }
        }

        if (compareLeftType.isString() && compareRightType.isString() && compareLeftView.cst()->isString() && compareRightView.cst()->isString())
        {
            result = sema.cstMgr().cstBool(compareLeftView.cst()->getString() == compareRightView.cst()->getString());
            return Result::Continue;
        }

        if (isNullComparableConstant(sema, *compareLeftView.cst()) || isNullComparableConstant(sema, *compareRightView.cst()))
        {
            result = sema.cstMgr().cstBool(isNullComparableConstant(sema, *compareLeftView.cst()) &&
                                           isNullComparableConstant(sema, *compareRightView.cst()));
            return Result::Continue;
        }

        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            uint64_t   leftAddress     = 0;
            uint64_t   rightAddress    = 0;
            const bool hasLeftAddress  = constantPointerAddress(leftAddress, *compareLeftView.cst());
            const bool hasRightAddress = constantPointerAddress(rightAddress, *compareRightView.cst());
            SWC_ASSERT(hasLeftAddress && hasRightAddress);
            result = sema.cstMgr().cstBool(leftAddress == rightAddress);
            return Result::Continue;
        }

        ConstantRef leftCstRef  = compareLeftView.cstRef();
        ConstantRef rightCstRef = compareRightView.cstRef();
        if (!hasAliasOperand(compareLeftView, compareRightView))
            SWC_RESULT(Cast::promoteConstants(sema, compareLeftView, compareRightView, leftCstRef, rightCstRef));

        // For float, we need to compare by values, because two different constants
        // can still have the same value. For example, 0.0 and -0.0 are two different
        // constants but have equal values.
        const ConstantValue& left = sema.cstMgr().get(leftCstRef);
        if (left.isFloat())
        {
            const ConstantValue& right = sema.cstMgr().get(rightCstRef);
            result                     = sema.cstMgr().cstBool(left.eq(right));
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

        const TypeInfo& compareLeftType  = aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            uint64_t   leftAddress     = 0;
            uint64_t   rightAddress    = 0;
            const bool hasLeftAddress  = constantPointerAddress(leftAddress, *compareLeftView.cst());
            const bool hasRightAddress = constantPointerAddress(rightAddress, *compareRightView.cst());
            SWC_ASSERT(hasLeftAddress && hasRightAddress);

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
            result                    = sema.cstMgr().cstBool(equalCaseValue);
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

        const TypeInfo& compareLeftType  = aliasEnumType(sema, compareLeftView);
        const TypeInfo& compareRightType = aliasEnumType(sema, compareRightView);
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
        {
            uint64_t   leftAddress     = 0;
            uint64_t   rightAddress    = 0;
            const bool hasLeftAddress  = constantPointerAddress(leftAddress, *compareLeftView.cst());
            const bool hasRightAddress = constantPointerAddress(rightAddress, *compareRightView.cst());
            SWC_ASSERT(hasLeftAddress && hasRightAddress);
            const int compareResult = leftAddress < rightAddress ? -1 : leftAddress > rightAddress ? 1
                                                                                                   : 0;
            result                  = sema.cstMgr().cstS32(compareResult);
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
        const TypeInfo&    compareLeftType  = aliasEnumType(sema, compareLeftView);
        const TypeInfo&    compareRightType = aliasEnumType(sema, compareRightView);
        if (compareLeftView.typeRef() == compareRightView.typeRef())
            return Result::Continue;
        if (aliasType(sema, compareLeftView).isScalarNumeric() && aliasType(sema, compareRightView).isScalarNumeric())
            return Result::Continue;
        if (isStringCompareOperands(sema, compareLeftView, compareRightView))
            return Result::Continue;
        if (compareLeftView.type()->isType() && compareRightView.type()->isType())
            return Result::Continue;
        if (compareLeftView.type()->isNull() && compareRightView.type()->isPointerLikeAliasAware(sema.ctx()))
            return Result::Continue;
        if (compareLeftView.type()->isPointerLikeAliasAware(sema.ctx()) && compareRightView.type()->isNull())
            return Result::Continue;
        if (compareLeftType.isAnyPointer() && compareRightType.isAnyPointer())
            return Result::Continue;
        if (compareLeftType.isAnyTypeInfo(sema.ctx()) && compareRightType.isAnyTypeInfo(sema.ctx()))
            return Result::Continue;
        if ((compareLeftType.isAny() && compareRightType.isAnyTypeInfo(sema.ctx())) ||
            (compareLeftType.isAnyTypeInfo(sema.ctx()) && compareRightType.isAny()))
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
        const TypeInfo&    compareLeftType  = aliasEnumType(sema, compareLeftView);
        const TypeInfo&    compareRightType = aliasEnumType(sema, compareRightView);
        if (aliasType(sema, compareLeftView).isScalarNumeric() && aliasType(sema, compareRightView).isScalarNumeric())
            return Result::Continue;
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

            // A nullable operand compares as a nullable typeinfo: comparisons never
            // dereference, so the nullability of the source must be preserved rather
            // than rejected by the non-null default.
            TypeRef typeInfoTargetRef = sema.typeMgr().typeTypeInfo();
            if (aliasEnumType(sema, self).isNullable())
            {
                TypeInfo nullableTypeInfo = sema.typeMgr().get(typeInfoTargetRef);
                nullableTypeInfo.addFlag(TypeInfoFlagsE::Nullable);
                typeInfoTargetRef = sema.typeMgr().addType(nullableTypeInfo);
            }

            const TypeInfo& otherType                     = aliasEnumType(sema, other);
            const bool      otherIsRuntimeTypeInfoPointer = sema.typeMgr().isRuntimeTypeInfoPointer(sema.ctx(), other.typeRef());
            const bool      otherIsTypeLike               = otherType.isAnyTypeInfo(sema.ctx()) || otherType.isAny() || otherIsRuntimeTypeInfoPointer || other.type()->isTypeValue();
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

        // A reference to a struct compares as the struct itself (unless the other side
        // is a pointer, which pointerReferenceForEquality handles as identity), and a
        // reference to a pointer compares its pointee against 'null'.
        Result structReferenceForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return Result::Continue;

            const TypeInfo& selfType = sema.typeMgr().get(self.typeRef());
            if (!selfType.isReference())
                return Result::Continue;

            const TypeInfo& otherType = aliasEnumType(sema, other);
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

        Result structLiteralForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return Result::Continue;

            const TypeInfo& selfType  = aliasEnumType(sema, self);
            const TypeInfo& otherType = aliasEnumType(sema, other);
            if (!selfType.isAggregateStruct() || !otherType.isStruct())
                return Result::Continue;

            SWC_RESULT(Cast::cast(sema, self, other.typeRef(), CastKind::Implicit));
            return Result::Continue;
        }

        TypeRef normalizedEqualityTypeRef(Sema& sema, TypeRef typeRef)
        {
            if (!typeRef.isValid())
                return TypeRef::invalid();

            const TypeRef unwrappedTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), typeRef);
            return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
        }

        Result equalityPointerTargetTypeRef(Sema& sema, TypeRef& outTypeRef, const SemaNodeView& pointerView, const SemaNodeView& referenceView)
        {
            outTypeRef = TypeRef::invalid();
            if (!pointerView.type() || !referenceView.type())
                return Result::Continue;

            const TypeRef pointerTypeRef   = normalizedEqualityTypeRef(sema, pointerView.typeRef());
            const TypeRef referenceTypeRef = normalizedEqualityTypeRef(sema, referenceView.typeRef());
            if (!pointerTypeRef.isValid() || !referenceTypeRef.isValid())
                return Result::Continue;

            const TypeInfo& pointerType   = sema.typeMgr().get(pointerTypeRef);
            const TypeInfo& referenceType = sema.typeMgr().get(referenceTypeRef);
            if (!pointerType.isAnyPointer() || !referenceType.isReference())
                return Result::Continue;

            TypeInfoFlags targetFlags = pointerType.flags();
            if (referenceType.isConst())
                targetFlags.add(TypeInfoFlagsE::Const);

            const TypeInfo targetType    = pointerType.isBlockPointer()
                                               ? TypeInfo::makeBlockPointer(pointerType.payloadTypeRef(), targetFlags)
                                               : TypeInfo::makeValuePointer(pointerType.payloadTypeRef(), targetFlags);
            const TypeRef  targetTypeRef = sema.typeMgr().addType(targetType);

            CastRequest castRequest(CastKind::Implicit);
            castRequest.errorNodeRef = referenceView.nodeRef();
            const Result result      = Cast::castAllowed(sema, castRequest, referenceView.typeRef(), targetTypeRef);
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

    // Comparisons never write through their operands, so a bare (non-null) operand can
    // always be compared against a #null one: widen the bare side to nullable and let
    // the regular promotion unify the base types.
    Result widenNullableCompareOperand(Sema& sema, SemaNodeView& bareView, const SemaNodeView& nullableView)
    {
        TypeRef bareTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), bareView.typeRef());
        if (bareTypeRef.isInvalid())
            bareTypeRef = bareView.typeRef();
        TypeRef otherTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), nullableView.typeRef());
        if (otherTypeRef.isInvalid())
            otherTypeRef = nullableView.typeRef();
        if (bareTypeRef.isInvalid() || otherTypeRef.isInvalid())
            return Result::Continue;

        const TypeInfo& bareType  = sema.typeMgr().get(bareTypeRef);
        const TypeInfo& otherType = sema.typeMgr().get(otherTypeRef);
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
        const bool readScalarReference = orderedCompare &&
                                         (shouldReadScalarReference(sema, nodeLeftView.typeRef()) ||
                                          shouldReadScalarReference(sema, nodeRightView.typeRef()));
        if (!readScalarReference)
            SWC_RESULT(Cast::castPromote(sema, nodeLeftView, nodeRightView, CastKind::Promotion));

        if (orderedCompare && nodeLeftView.typeRef() == nodeRightView.typeRef())
        {
            const TypeInfo& leftType  = aliasType(sema, nodeLeftView);
            const TypeInfo& rightType = aliasType(sema, nodeRightView);
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
            SWC_RESULT(structLiteralForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(structLiteralForEquality(sema, nodeRightView, nodeLeftView));
            SWC_RESULT(pointerReferenceForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(pointerReferenceForEquality(sema, nodeRightView, nodeLeftView));
        }

        return Result::Continue;
    }

    Result check(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        switch (op)
        {
            case TokenId::SymEqualEqual:
            case TokenId::SymBangEqual:
                return checkEqualEqual(sema, node, nodeLeftView, nodeRightView);

            case TokenId::SymLess:
            case TokenId::SymLessEqual:
            case TokenId::SymGreater:
            case TokenId::SymGreaterEqual:
            case TokenId::SymLessEqualGreater:
                return checkCompareEqual(sema, node, nodeLeftView, nodeRightView);

            default:
                SWC_UNREACHABLE();
        }
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
        sema.pushFramePopOnPostChild(frame, nodeRightRef);
    }

    return Result::Continue;
}

Result AstRelationalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);
    const Token& tok           = sema.token({srcViewRef(), tokRef()});

    normalizeTypeOperandToConstant(sema, nodeLeftView);
    normalizeTypeOperandToConstant(sema, nodeRightView);
    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeLeftView));
    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
    normalizeTypeOperandToConstant(sema, nodeLeftView);
    normalizeTypeOperandToConstant(sema, nodeRightView);
    sema.setIsValue(*this);

    bool handledSpecialOp = false;
    SWC_RESULT(SemaSpecOp::tryResolveRelational(sema, *this, nodeLeftView, handledSpecialOp));
    if (handledSpecialOp)
        return Result::Continue;

    // Force types
    SWC_RESULT(promote(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // Type-check
    SWC_RESULT(check(sema, tok.id, *this, nodeLeftView, nodeRightView));

    // Set the result type
    if (tok.id == TokenId::SymLessEqualGreater)
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeInt(32, TypeInfo::Sign::Signed));
    else
        sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());

    // Constant folding
    const bool canConstantFold = nodeLeftView.cstRef().isValid() && nodeRightView.cstRef().isValid();
    if (canConstantFold)
    {
        ConstantRef result;
        SWC_RESULT(constantFold(sema, result, tok.id, nodeLeftView, nodeRightView));
        sema.setConstant(sema.curNodeRef(), result);
    }

    if (!canConstantFold &&
        (tok.id == TokenId::SymEqualEqual || tok.id == TokenId::SymBangEqual) &&
        isStringCompareOperands(sema, nodeLeftView, nodeRightView) &&
        !hasNullComparableOperandConstant(sema, nodeLeftView, nodeRightView))
        SWC_RESULT(SemaHelpers::attachRuntimeStringCmpFunctionToNode(sema, sema.curNodeRef(), codeRef()));

    return Result::Continue;
}

SWC_END_NAMESPACE();
