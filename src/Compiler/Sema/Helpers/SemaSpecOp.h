#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct AstBinaryExpr;
struct AstRelationalExpr;
struct AstUnaryExpr;
struct SemaNodeView;

struct RelationalSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

enum class SpecOpKind : uint8_t
{
    None,
    Invalid,
    OpBinary,
    OpUnary,
    OpAssign,
    OpIndexAssign,
    OpCast,
    OpEquals,
    OpCmp,
    OpPostCopy,
    OpPostMove,
    OpDrop,
    OpCount,
    OpData,
    OpAffect,
    OpAffectLiteral,
    OpSlice,
    OpIndex,
    OpIndexAffect,
    OpVisit,
};

namespace SemaSpecOp
{
    SpecOpKind computeSymbolKind(const Sema& sema, const SymbolFunction& sym);
    Result     validateSymbol(Sema& sema, SymbolFunction& sym);
    Result     registerSymbol(Sema& sema, SymbolFunction& sym);
    Result     tryResolveBinary(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& leftView, bool& outHandled);
    Result     tryResolveRelational(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& leftView, bool& outHandled);
    Result     tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled);
}

SWC_END_NAMESPACE();
