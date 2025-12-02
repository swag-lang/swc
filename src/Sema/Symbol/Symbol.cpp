#include "pch.h"
#include "Sema/Symbol/Symbol.h"
#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()

std::string_view Symbol::name(const TaskContext& ctx) const
{
    const auto& srcView = ctx.compiler().srcView(srcViewRef_);
    const auto& tok     = srcView.token(tokRef_);
    return tok.string(srcView);
}

uint32_t Symbol::crc(const TaskContext& ctx) const
{
    const auto& srcView = ctx.compiler().srcView(srcViewRef_);
    const auto& tok     = srcView.token(tokRef_);
    return tok.crc(srcView);
}

SWC_END_NAMESPACE()
