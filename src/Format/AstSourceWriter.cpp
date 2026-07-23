#include "pch.h"
#include "Format/AstSourceWriter.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Format/FormatClassifier.h"
#include "Format/FormatModel.h"
#include "Format/FormatPasses.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

AstSourceWriter::AstSourceWriter(FormatContext& formatCtx) :
    formatCtx_(&formatCtx)
{
    SWC_ASSERT(formatCtx.ast != nullptr);
    SWC_ASSERT(formatCtx.srcView != nullptr);
    SWC_ASSERT(formatCtx.options != nullptr);
    SWC_ASSERT(!formatCtx.ast->root().isInvalid());
}

void AstSourceWriter::write()
{
    FormatModel model;
    model.build(*formatCtx_->srcView, *formatCtx_->options);
    FormatClassifier::classify(model, *formatCtx_->ast);
    FormatPass::runAll(model);
    model.render(formatCtx_->output);
}

SWC_END_NAMESPACE();
