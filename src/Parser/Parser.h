#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

struct ParserResult
{
    AstNodeRef node = INVALID_REF;
    bool       ok   = false;
};

class ParserOutput
{
protected:
    friend class Parser;
    Ast ast_;
};

class Parser
{
    SourceFile*  file_       = nullptr;
    Ast*         ast_        = nullptr;
    const Token* firstToken_ = nullptr;
    const Token* curToken_   = nullptr;
    const Token* lastToken_  = nullptr;

    void nextToken();

    TokenRef tokenRef() const
    {
        return static_cast<TokenRef>(curToken_ - firstToken_) + 1;
    }

    ParserResult parseTopLevelInstruction();
    ParserResult parseTopLevelBlock(AstNodeId id);

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE();
