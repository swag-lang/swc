#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/DiagnosticBuilder.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t compilerMessageMask(const Runtime::CompilerMsgKind kind)
    {
        return 1ull << static_cast<uint32_t>(kind);
    }
}

SWC_TEST_BEGIN(Compiler_MessagePassSkipsWithoutListeners)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_message_no_listener";

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SWC_RESULT(compiler.setupSema(compilerCtx));

    if (compiler.hasCompilerMessageInterest(Runtime::CompilerMsgKind::PassAfterSemantic))
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Continue)
        return Result::Error;
    if (compiler.executePendingCompilerMessages(compilerCtx) != Result::Continue)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_MessagePassQueuesOnlyOncePerListener)
{
    CommandLine cmdLine;
    cmdLine.command = CommandKind::Syntax;
    cmdLine.name    = "compiler_message_listener";

    CompilerInstance compiler(ctx.global(), cmdLine);
    TaskContext      compilerCtx(compiler);
    SWC_RESULT(compiler.setupSema(compilerCtx));

    auto* listener = Symbol::make<SymbolFunction>(compilerCtx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    compiler.registerCompilerMessageFunction(listener, AstNodeRef::invalid(), compilerMessageMask(Runtime::CompilerMsgKind::PassAfterSemantic));

    if (!compiler.hasCompilerMessageInterest(Runtime::CompilerMsgKind::PassAfterSemantic))
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Pause)
        return Result::Error;
    if (compiler.ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassAfterSemantic) != Result::Continue)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_MessageAliasPayloadUsesUnderlyingType)
{
    auto* aliasSymbol = Symbol::make<SymbolAlias>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), {});
    aliasSymbol->setUnderlyingTypeRef(ctx.typeMgr().typeConstValuePtrVoid());

    const TypeRef aliasTypeRef = ctx.typeMgr().addType(TypeInfo::makeAlias(aliasSymbol));
    aliasSymbol->setTypeRef(aliasTypeRef);

    const TypeInfo& aliasType = ctx.typeMgr().get(aliasTypeRef);
    if (aliasType.payloadTypeRef() != ctx.typeMgr().typeConstValuePtrVoid())
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_AssertDiagnosticPreservesLiteralSuffixQuotes)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic  diag = Diagnostic::get(DiagnosticId::sema_err_assert_failed);
    diag.addArgument(Diagnostic::ARG_BECAUSE, "text[0] == 'w''u8 + 'd''u8");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("assertion failed: text[0] == 'w''u8 + 'd''u8") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticEscapesQuotedArgumentTicks)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::sema_err_type_not_indexable);
    diag.addArgument(Diagnostic::ARG_TYPE, "List'(s32)");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("type 'List'(s32)' does not support indexing") == Utf8::npos)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(Compiler_DiagnosticEscapesQuotedArgumentWithoutBreakingHelpSplit)
{
    CommandLine cmdLine;
    cmdLine.command     = CommandKind::Test;
    cmdLine.logColor    = false;
    cmdLine.syntaxColor = false;

    const TaskContext localCtx(ctx.global(), cmdLine);
    Diagnostic        diag = Diagnostic::get(DiagnosticId::sema_err_type_not_indexable);
    diag.addArgument(Diagnostic::ARG_TYPE, "List'(s32); [help] fake");

    DiagnosticBuilder builder(localCtx, diag);
    const Utf8        text = builder.build();

    if (text.find("type 'List'(s32); [help] fake' does not support indexing") == Utf8::npos)
        return Result::Error;

    size_t helpCount = 0;
    size_t pos       = 0;
    while ((pos = text.find("help:", pos)) != Utf8::npos)
    {
        ++helpCount;
        pos += 5;
    }

    if (helpCount != 1)
        return Result::Error;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
