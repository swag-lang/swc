#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Sema/Cast/CastRequest.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
class SymbolVariable;
struct AstUnaryExpr;
struct AstBinaryExpr;
struct AstRelationalExpr;
struct AstLogicalExpr;
struct AstConditionalExpr;
struct AstNullCoalescingExpr;
struct AstExplicitCastExpr;
struct AstImplicitCastExpr;
struct AstAutoCastExpr;
struct AstMemberAccessExpr;
struct AstIndexExpr;
struct AstIndexListExpr;
struct AstIntrinsicCallExpr;
struct AstCallExpr;

class ConstantEval
{
public:
    struct ParamBinding
    {
        const SymbolVariable* sym    = nullptr;
        ConstantRef           cstRef = ConstantRef::invalid();
        AstNodeRef            argRef = AstNodeRef::invalid();
    };

    ConstantEval(Sema& sema, std::span<const ParamBinding> bindings);

    Result evalExpr(AstNodeRef exprRef, ConstantRef& out);

    static Result tryConstantFoldPureCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg);

private:
    Result                evalExprInternal(AstNodeRef exprRef, ConstantRef& out, bool allowSubstitute);
    Result                evalIdentifier(AstNodeRef nodeRef, ConstantRef& out) const;
    const SymbolVariable* lookupParameter(AstNodeRef nodeRef) const;
    AstNodeRef            mapArgumentRef(AstNodeRef argRef) const;
    Result                castConstant(AstNodeRef nodeRef, ConstantRef srcCstRef, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags, ConstantRef& out, TypeRef srcTypeRef = TypeRef::invalid()) const;
    Result                getConstIndex(AstNodeRef nodeArgRef, ConstantRef indexCstRef, int64_t& outIndex) const;
    Result                evalUnary(AstNodeRef nodeRef, const AstUnaryExpr* node, ConstantRef& out);
    Result                evalBinary(AstNodeRef nodeRef, const AstBinaryExpr* node, ConstantRef& out);
    Result                evalRelational(AstNodeRef nodeRef, const AstRelationalExpr* node, ConstantRef& out);
    Result                evalLogical(AstNodeRef nodeRef, const AstLogicalExpr* node, ConstantRef& out);
    Result                evalConditional(AstNodeRef nodeRef, const AstConditionalExpr* node, ConstantRef& out);
    Result                evalNullCoalescing(AstNodeRef nodeRef, const AstNullCoalescingExpr* node, ConstantRef& out);
    Result                evalExplicitCast(AstNodeRef nodeRef, const AstExplicitCastExpr* node, ConstantRef& out);
    Result                evalImplicitCast(AstNodeRef nodeRef, const AstImplicitCastExpr* node, ConstantRef& out);
    Result                evalAutoCast(AstNodeRef nodeRef, const AstAutoCastExpr* node, ConstantRef& out);
    Result                evalMemberAccess(AstNodeRef nodeRef, const AstMemberAccessExpr* node, ConstantRef& out);
    Result                evalIndex(AstNodeRef nodeRef, const AstIndexExpr* node, ConstantRef& out);
    Result                evalIndexList(AstNodeRef nodeRef, const AstIndexListExpr* node, ConstantRef& out);
    Result                evalCountOf(AstNodeRef nodeRef, AstNodeRef exprRef, ConstantRef& out);
    Result                evalIntrinsicCall(AstNodeRef nodeRef, const AstIntrinsicCallExpr* node, ConstantRef& out);
    Result                evalCall(AstNodeRef nodeRef, const AstCallExpr* node, ConstantRef& out) const;

    Sema*                         sema_ = nullptr;
    std::span<const ParamBinding> bindings_;
};

SWC_END_NAMESPACE();
