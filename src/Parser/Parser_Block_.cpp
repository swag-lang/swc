#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseTopLevelInstruction()
{
    const auto start = static_cast<TokenRef>(curToken_ - firstToken_);
    nextToken();
    return ast_->makeNode(AstNodeId::Invalid, file_->ref(), start);
}

SWC_END_NAMESPACE();
