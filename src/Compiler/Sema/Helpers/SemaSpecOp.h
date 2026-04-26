#pragma once
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class Sema;
class Diagnostic;
class Symbol;
class SymbolFunction;
class SymbolStruct;
struct SourceCodeRef;
struct AstAssignStmt;
struct AstBinaryExpr;
struct AstIndexExpr;
struct AstIndexListExpr;
struct AstRelationalExpr;
struct AstUnaryExpr;
struct AstForeachStmt;
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

struct DataOfSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct RelationalSpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct UnarySpecOpPayload
{
    SymbolFunction* calledFn = nullptr;
};

struct BinarySpecOpPayload
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
    OpBinaryRight,
    OpUnary,
    OpAssign,
    OpIndexAssign,
    OpCast,
    OpEquals,
    OpCompare,
    OpPostCopy,
    OpPostMove,
    OpDrop,
    OpCount,
    OpData,
    OpSet,
    OpSetLiteral,
    OpSlice,
    OpIndex,
    OpIndexSet,
    OpVisit,
};

namespace SemaSpecOp
{
    SpecOpKind computeSymbolKind(const Sema& sema, const SymbolFunction& sym);
    void       addMissingDeclarationHelp(Sema& sema, Diagnostic& diag, const SymbolStruct& ownerStruct, SpecOpKind kind);
    Result     ensureGeneratedOperators(Sema& sema, SymbolStruct& ownerStruct);
    Result     validateSymbol(Sema& sema, SymbolFunction& sym);
    Result     registerSymbol(Sema& sema, SymbolFunction& sym);
    Result     collectSetCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, AstNodeRef valueRef, SmallVector<Symbol*>& outCandidates);
    Result     canResolveVisit(Sema& sema, const AstForeachStmt& node, bool& outMatched);

    Result tryResolveVarInitSet(Sema& sema, AstNodeRef receiverRef, AstNodeRef valueRef, bool& outHandled);
    Result tryResolveCountOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled);
    Result tryResolveDataOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled);
    Result tryResolveVisit(Sema& sema, const AstForeachStmt& node, bool& outHandled);
    Result tryResolveSlice(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled);
    Result tryResolveIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled);
    Result tryResolveIndex(Sema& sema, const AstIndexListExpr& node, const SemaNodeView& indexedView, bool& outHandled);
    Result tryResolveIndexAssign(Sema& sema, const AstAssignStmt& node, bool& outHandled);
    Result tryResolveAssign(Sema& sema, const AstAssignStmt& node, const SemaNodeView& leftView, bool& outHandled);
    Result tryResolveBinary(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView, bool& outHandled);
    Result tryResolveRelational(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& leftView, bool& outHandled);
    Result tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled);
}

SWC_END_NAMESPACE();
