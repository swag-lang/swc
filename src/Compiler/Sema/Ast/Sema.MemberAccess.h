#pragma once

SWC_BEGIN_NAMESPACE();

class Sema;
struct AstMemberAccessExpr;

namespace SemaMemberAccess
{
    Result resolve(Sema& sema, AstNodeRef memberRef, AstMemberAccessExpr& node, bool allowOverloadSet);
}

SWC_END_NAMESPACE();
