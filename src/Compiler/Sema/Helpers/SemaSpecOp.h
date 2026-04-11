#pragma once
#include "Compiler/Sema/Ast/Sema.Index.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class SymbolFunction;
struct AstAssignStmt;
struct AstBinaryExpr;
struct AstIndexExpr;
struct AstRelationalExpr;
struct AstUnaryExpr;
struct SemaNodeView;

struct AssignSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct VarInitSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct CountOfSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct RelationalSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct DeferredIndexAssignSpecOpPayload : IndexSpecOpPayloadBase
{
    DeferredIndexAssignSpecOpPayload()
    {
        kind = IndexSpecOpPayloadKind::DeferredAssign;
    }
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
    Result     tryResolveVarInitAffect(Sema& sema, AstNodeRef receiverRef, AstNodeRef valueRef, bool& outHandled);
    Result     tryResolveCountOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled);
    Result     tryResolveIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled);
    Result     tryResolveIndexAssign(Sema& sema, const AstAssignStmt& node, bool& outHandled);
    Result     tryResolveAssign(Sema& sema, const AstAssignStmt& node, const SemaNodeView& leftView, bool& outHandled);
    Result     tryResolveBinary(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& leftView, bool& outHandled);
    Result     tryResolveRelational(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& leftView, bool& outHandled);
    Result     tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled);
}

SWC_END_NAMESPACE();
