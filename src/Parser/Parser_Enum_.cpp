#include "pch.h"

#include "Parser/AstNodes.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseEnum()
{
    auto [ref, node] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::File, consume());

    SmallVector<AstNodeRef> stmts;

    return ref;
}

SWC_END_NAMESPACE();
