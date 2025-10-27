#include "pch.h"

#include "Parser/Parser.h"
#include "Parser/AstNodes.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseEnum()
{
    auto [ref, node] = ast_->makeNodePtr<AstNodeEnumDecl>(AstNodeId::File, eat());

    SmallVector<AstNodeRef> stmts;

    return ref;
}

SWC_END_NAMESPACE();
