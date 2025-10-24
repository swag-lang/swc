#include "pch.h"
#include "Parser/Parser.h"
#include "Lexer/SourceFile.h"
#include "Main/EvalContext.h"

SWC_BEGIN_NAMESPACE();

Result Parser::parse(EvalContext& ctx)
{
    file_ = ctx.sourceFile();
    ast_  = &file_->parserOut_.ast_;

    SWC_CHECK(file_->loadContent(ctx));
    SWC_CHECK(file_->tokenize(ctx));
    SWC_CHECK(file_->verifier().verify(ctx));

    ast_->root_ = ast_->makeNode(AstNodeId::File, file_->ref());

    return Result::Success;
}

SWC_END_NAMESPACE();
