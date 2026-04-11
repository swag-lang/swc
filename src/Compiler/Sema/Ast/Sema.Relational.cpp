#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
            if (typeInfo.isFunction() && typeInfo.isLambdaClosure())
            {
                const ByteSpan bytes = cst.getStruct();
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

    SemaNodeView scalarReadView(Sema& sema, const SemaNodeView& view)
    {
        if (!shouldReadScalarReference(sema, view.typeRef()))
            return view;

        SemaNodeView  result         = view;
        const TypeRef normalizedRef  = sema.typeMgr().unwrapAliasEnum(sema.ctx(), view.typeRef());
        const TypeRef payloadTypeRef = sema.typeMgr().get(normalizedRef).payloadTypeRef();
        result.typeRef()             = payloadTypeRef;
        result.type()                = &sema.typeMgr().get(payloadTypeRef);
        return result;
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
        if (nodeLeftView.type()->isTypeValue() && nodeRightView.type()->isTypeValue())
        {
            SWC_ASSERT(nodeLeftView.cst() != nullptr);
            SWC_ASSERT(nodeRightView.cst() != nullptr);
            result = sema.cstMgr().cstBool(sameTypeValuePayload(sema, nodeLeftView.cst()->getTypeValue(), nodeRightView.cst()->getTypeValue()));
            return Result::Continue;
        }

        if (nodeLeftView.type()->isAnyTypeInfo(sema.ctx()) && nodeRightView.type()->isAnyTypeInfo(sema.ctx()))
        {
            result = sema.cstMgr().cstBool(sameTypeInfoIdentity(sema, nodeLeftView.cstRef(), nodeRightView.cstRef()));
            return Result::Continue;
        }

        if (isNullComparableConstant(sema, *nodeLeftView.cst()) || isNullComparableConstant(sema, *nodeRightView.cst()))
        {
            result = sema.cstMgr().cstBool(isNullComparableConstant(sema, *nodeLeftView.cst()) &&
                                           isNullComparableConstant(sema, *nodeRightView.cst()));
            return Result::Continue;
        }

        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();
        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));

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
        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();
        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));

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
        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();

        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
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
        if (compareLeftView.typeRef() == compareRightView.typeRef())
            return Result::Continue;
        if (compareLeftView.type()->isScalarNumeric() && compareRightView.type()->isScalarNumeric())
            return Result::Continue;
        if (compareLeftView.type()->isType() && compareRightView.type()->isType())
            return Result::Continue;
        if (compareLeftView.type()->isNull() && compareRightView.type()->isPointerLike())
            return Result::Continue;
        if (compareLeftView.type()->isPointerLike() && compareRightView.type()->isNull())
            return Result::Continue;
        if (compareLeftView.type()->isAnyPointer() && compareRightView.type()->isAnyPointer())
            return Result::Continue;
        if (compareLeftView.type()->isAnyTypeInfo(sema.ctx()) && compareRightView.type()->isAnyTypeInfo(sema.ctx()))
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        const SemaNodeView compareLeftView  = scalarReadView(sema, nodeLeftView);
        const SemaNodeView compareRightView = scalarReadView(sema, nodeRightView);
        if (compareLeftView.type()->isScalarNumeric() && compareRightView.type()->isScalarNumeric())
            return Result::Continue;
        if (compareLeftView.type()->isAnyPointer() && compareRightView.type()->isAnyPointer())
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
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
            if (self.type()->isNull() && other.type()->isPointerLike())
                Cast::createCast(sema, other.typeRef(), self.nodeRef());
        }

        Result typeInfoForEquality(Sema& sema, SemaNodeView& self, const SemaNodeView& other)
        {
            if (!self.type() || !other.type())
                return Result::Continue;
            if (self.type()->isTypeValue() && other.type()->isAnyTypeInfo(sema.ctx()))
            {
                SWC_RESULT(Cast::cast(sema, self, sema.typeMgr().typeTypeInfo(), CastKind::Implicit));
                return Result::Continue;
            }

            return Result::Continue;
        }
    }

    Result promote(Sema& sema, TokenId op, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        SWC_UNUSED(node);

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

        if (op == TokenId::SymEqualEqual || op == TokenId::SymBangEqual)
        {
            enumForEquality(sema, nodeLeftView, nodeRightView);
            enumForEquality(sema, nodeRightView, nodeLeftView);
            nullForEquality(sema, nodeLeftView, nodeRightView);
            nullForEquality(sema, nodeRightView, nodeLeftView);
            SWC_RESULT(typeInfoForEquality(sema, nodeLeftView, nodeRightView));
            SWC_RESULT(typeInfoForEquality(sema, nodeRightView, nodeLeftView));
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
    if (childRef == nodeLeftRef)
    {
        const SemaNodeView nodeLeftView = sema.viewType(nodeLeftRef);
        SemaFrame          frame        = sema.frame();
        frame.pushBindingType(nodeLeftView.typeRef());
        sema.pushFramePopOnPostChild(frame, nodeRightRef);
    }

    return Result::Continue;
}

Result AstRelationalExpr::semaPostNode(Sema& sema)
{
    SemaNodeView nodeLeftView  = sema.viewNodeTypeConstant(nodeLeftRef);
    SemaNodeView nodeRightView = sema.viewNodeTypeConstant(nodeRightRef);
    const Token& tok           = sema.token({srcViewRef(), tokRef()});

    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeLeftView));
    SWC_RESULT(SemaCheck::isValueOrType(sema, nodeRightView));
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
        SWC_RESULT(SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::StringCmp, codeRef()));

    return Result::Continue;
}

SWC_END_NAMESPACE();
