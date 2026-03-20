#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;
class Symbol;
class TypeInfo;
struct AstMemberAccessExpr;

namespace SemaMemberAccess
{
    bool   resolveAggregateMemberIndex(Sema& sema, const TypeInfo& aggregateType, IdentifierRef idRef, size_t& outIndex);
    Result resolve(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet);
}

SWC_END_NAMESPACE();
