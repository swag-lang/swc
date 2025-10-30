#include "pch.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseExpression()
{
    skipTrivia();
    return INVALID_REF;
}

SWC_END_NAMESPACE()
