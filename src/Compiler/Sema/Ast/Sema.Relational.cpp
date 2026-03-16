#include "pch.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool sameTypeInfoIdentity(Sema& sema, ConstantRef leftCstRef, ConstantRef rightCstRef)
    {
        const TypeRef leftTypeRef  = sema.cstMgr().makeTypeValue(sema, leftCstRef);
        const TypeRef rightTypeRef = sema.cstMgr().makeTypeValue(sema, rightCstRef);
        if (leftTypeRef.isValid() && rightTypeRef.isValid())
            return leftTypeRef == rightTypeRef;

        const auto* leftTypeInfo  = reinterpret_cast<const Runtime::TypeInfo*>(sema.cstMgr().get(leftCstRef).getValuePointer());
        const auto* rightTypeInfo = reinterpret_cast<const Runtime::TypeInfo*>(sema.cstMgr().get(rightCstRef).getValuePointer());
        if (!leftTypeInfo || !rightTypeInfo)
            return leftTypeInfo == rightTypeInfo;

        return leftTypeInfo->crc == rightTypeInfo->crc;
    }

    TypeRef unwrapAliasEnumTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeInfo& typeInfo         = sema.typeMgr().get(typeRef);
        const TypeRef   unwrappedTypeRef = typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (unwrappedTypeRef.isValid())
            return unwrappedTypeRef;

        return typeRef;
    }

    bool isStringCompareOperands(Sema& sema, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (!nodeLeftView.type() || !nodeRightView.type())
            return false;

        const TypeRef   leftTypeRef  = unwrapAliasEnumTypeRef(sema, nodeLeftView.typeRef());
        const TypeRef   rightTypeRef = unwrapAliasEnumTypeRef(sema, nodeRightView.typeRef());
        const TypeInfo& leftType     = sema.typeMgr().get(leftTypeRef);
        const TypeInfo& rightType    = sema.typeMgr().get(rightTypeRef);
        return leftType.isString() && rightType.isString();
    }

    Result setupStringCompareRuntimeCall(Sema& sema, const AstRelationalExpr& node)
    {
        SymbolFunction* stringCmpFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::StringCmp, stringCmpFn, node.codeRef()));
        SWC_ASSERT(stringCmpFn != nullptr);

        if (SymbolFunction* currentFn = sema.frame().currentFunction())
            currentFn->addCallDependency(stringCmpFn);

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeFunctionSymbol = stringCmpFn;
        return Result::Continue;
    }

    Result constantFoldEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.type()->isTypeValue() && nodeRightView.type()->isTypeValue())
        {
            result = sema.cstMgr().cstBool(*(nodeLeftView.type()) == *(nodeRightView.type()));
            return Result::Continue;
        }

        if (nodeLeftView.type()->isAnyTypeInfo(sema.ctx()) && nodeRightView.type()->isAnyTypeInfo(sema.ctx()))
        {
            result = sema.cstMgr().cstBool(sameTypeInfoIdentity(sema, nodeLeftView.cstRef(), nodeRightView.cstRef()));
            return Result::Continue;
        }

        if (nodeLeftView.cst()->isNull() || nodeRightView.cst()->isNull())
        {
            result = sema.cstMgr().cstBool(nodeLeftView.cst()->isNull() && nodeRightView.cst()->isNull());
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

    Result constantFoldLess(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.cstRef() == nodeRightView.cstRef())
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();

        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.lt(rightCst));
        return Result::Continue;
    }

    Result constantFoldLessEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();

        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);
        if (!leftCst.isFloat() && leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        result = sema.cstMgr().cstBool(leftCst.le(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreater(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();

        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        if (leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstFalse();
            return Result::Continue;
        }

        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);

        result = sema.cstMgr().cstBool(leftCst.gt(rightCst));
        return Result::Continue;
    }

    Result constantFoldGreaterEqual(Sema& sema, ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        ConstantRef leftCstRef  = nodeLeftView.cstRef();
        ConstantRef rightCstRef = nodeRightView.cstRef();

        SWC_RESULT(Cast::promoteConstants(sema, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
        const ConstantValue& leftCst  = sema.cstMgr().get(leftCstRef);
        const ConstantValue& rightCst = sema.cstMgr().get(rightCstRef);
        if (!leftCst.isFloat() && leftCstRef == rightCstRef)
        {
            result = sema.cstMgr().cstTrue();
            return Result::Continue;
        }

        result = sema.cstMgr().cstBool(leftCst.ge(rightCst));
        return Result::Continue;
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
                return Result::Error;
        }
    }

    Result checkEqualEqual(Sema& sema, const AstRelationalExpr& node, SemaNodeView& nodeLeftView, SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.typeRef() == nodeRightView.typeRef())
            return Result::Continue;
        if (nodeLeftView.type()->isScalarNumeric() && nodeRightView.type()->isScalarNumeric())
            return Result::Continue;
        if (nodeLeftView.type()->isType() && nodeRightView.type()->isType())
            return Result::Continue;
        if (nodeLeftView.type()->isNull() && nodeRightView.type()->isPointerLike())
            return Result::Continue;
        if (nodeLeftView.type()->isPointerLike() && nodeRightView.type()->isNull())
            return Result::Continue;
        if (nodeLeftView.type()->isAnyPointer() && nodeRightView.type()->isAnyPointer())
            return Result::Continue;
        if (nodeLeftView.type()->isAnyTypeInfo(sema.ctx()) && nodeRightView.type()->isAnyTypeInfo(sema.ctx()))
            return Result::Continue;

        Diagnostic diag = SemaError::report(sema, DiagnosticId::sema_err_compare_operand_type, node.codeRef());
        diag.addArgument(Diagnostic::ARG_LEFT, nodeLeftView.typeRef());
        diag.addArgument(Diagnostic::ARG_RIGHT, nodeRightView.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result checkCompareEqual(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView)
    {
        if (nodeLeftView.type()->isScalarNumeric() && nodeRightView.type()->isScalarNumeric())
            return Result::Continue;
        if (nodeLeftView.type()->isAnyPointer() && nodeRightView.type()->isAnyPointer())
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

    if (!canConstantFold && (tok.id == TokenId::SymEqualEqual || tok.id == TokenId::SymBangEqual) && isStringCompareOperands(sema, nodeLeftView, nodeRightView))
        SWC_RESULT(setupStringCompareRuntimeCall(sema, *this));

    return Result::Continue;
}

SWC_END_NAMESPACE();
