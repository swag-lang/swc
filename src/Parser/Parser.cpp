#include "pch.h"
#include "Parser/Parser.h"
#include "Lexer/SourceFile.h"
#include "Main/EvalContext.h"

SWC_BEGIN_NAMESPACE();

Result Parser::parse(EvalContext& ctx)
{
    file_ = ctx.sourceFile();
    
    SWC_CHECK(file_->loadContent(ctx));
    SWC_CHECK(file_->tokenize(ctx));
    SWC_CHECK(file_->verifier().verify(ctx));
    
    return Result::Success;
}

SWC_END_NAMESPACE();
