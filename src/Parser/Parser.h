#pragma once
#include "Lexer/Token.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

class SourceFile;
class Context;

class ParserOutput
{
protected:
    friend class Parser;
    Ast ast_;
};

class Parser
{
    Context*     ctx_        = nullptr;
    SourceFile*  file_       = nullptr;
    Ast*         ast_        = nullptr;
    const Token* firstToken_ = nullptr;
    const Token* curToken_   = nullptr;
    const Token* lastToken_  = nullptr;

    void consume()
    {
        SWC_ASSERT(curToken_->id != TokenId::EndOfFile);
        curToken_++;
        while (curToken_->id == TokenId::Blank || curToken_->id == TokenId::EndOfLine)
            curToken_++;
    }

    TokenRef eat()
    {
        const auto ref = tokenRef();
        consume();
        return ref;
    }

    TokenRef tokenRef() const
    {
        return static_cast<TokenRef>(curToken_ - firstToken_) + 1;
    }

    TokenId id() const { return curToken_->id; }
    bool    atEnd() const { return curToken_ >= lastToken_; }

    AstNodeRef parseTopLevelDecl();
    AstNodeRef parseTopLevelCurlyBlock();
    AstNodeRef parseFile();

public:
    Result parse(Context& ctx);
};

SWC_END_NAMESPACE();
