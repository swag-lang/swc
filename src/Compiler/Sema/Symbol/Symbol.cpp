#include "pch.h"
#include "Compiler/Parser/Ast/AstPrinter.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Logger.h"
#include "Support/Report/SyntaxColor.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr std::string_view K_AST_STAGE_PRE_SEMA  = "pre-sema";
    constexpr std::string_view K_AST_STAGE_POST_SEMA = "post-sema";

    bool shouldPrintAstStage(const AttributeList& attributes, std::string_view stageName)
    {
        for (const Utf8& stage : attributes.printAstStageOptions)
        {
            if (std::string_view{stage} == stageName)
                return true;
        }

        return false;
    }

    void printAstStage(TaskContext& ctx, const Ast& ast, const Symbol& symbol, AstNodeRef declRef, std::string_view stageName)
    {
        Logger::ScopedLock     lock(ctx.global().logger());
        const SourceCodeRange  codeLoc  = symbol.codeRange(ctx);
        const SourceView&      srcView  = ctx.compiler().srcView(symbol.srcViewRef());
        const SourceFile*      srcFile  = srcView.file();
        const Utf8             filePath = srcFile ? Utf8(srcFile->path().string()) : Utf8("<unknown-file>");

        Logger::print(ctx, "\n");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Compiler));
        Logger::print(ctx, "[ast]");
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  stage");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "    : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Attribute));
        Logger::print(ctx, stageName);
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  symbol");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, "   : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Function));
        Logger::print(ctx, symbol.getFullScopedName(ctx));
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Keyword));
        Logger::print(ctx, "  location");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Code));
        Logger::print(ctx, " : ");
        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::String));
        Logger::print(ctx, std::format("{}:{}", filePath, codeLoc.line));
        Logger::print(ctx, "\n");

        Logger::print(ctx, SyntaxColorHelper::toAnsi(ctx, SyntaxColor::Default));
        AstPrinter::print(ctx, ast, declRef);
    }
}

SourceCodeRange Symbol::codeRange(TaskContext& ctx) const noexcept
{
    const SourceView& srcView = ctx.compiler().srcView(srcViewRef());
    const Token&      tok     = srcView.token(tokRef_);
    return tok.codeRange(ctx, srcView);
}

Utf8 Symbol::toFamily() const
{
    switch (kind_)
    {
        case SymbolKind::Namespace: return "namespace";
        case SymbolKind::Variable: return "variable";
        case SymbolKind::Constant: return "constant";
        case SymbolKind::Enum: return "enum";
        case SymbolKind::EnumValue: return "enum value";
        default: return "symbol";
    }
}

bool Symbol::isAttribute() const noexcept
{
    if (!isFunction())
        return false;
    return cast<SymbolFunction>().isAttribute();
}

void Symbol::setTyped(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::Typed))
        return;
    flags_.add(SymbolFlagsE::Typed);
    ctx.compiler().notifyAlive();
}

void Symbol::setSemaCompleted(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::SemaCompleted))
        return;
    flags_.add(SymbolFlagsE::SemaCompleted);
    ctx.compiler().notifyAlive();
}

void Symbol::setCodeGenCompleted(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::CodeGenCompleted))
        return;
    flags_.add(SymbolFlagsE::CodeGenCompleted);
    ctx.compiler().notifyAlive();
}

void Symbol::setCodeGenPreSolved(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::CodeGenPreSolved))
        return;
    flags_.add(SymbolFlagsE::CodeGenPreSolved);
    ctx.compiler().notifyAlive();
}

void Symbol::setDeclared(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::Declared))
        return;
    flags_.add(SymbolFlagsE::Declared);
    ctx.compiler().notifyAlive();
}

void Symbol::setIgnored(TaskContext& ctx) noexcept
{
    if (flags_.has(SymbolFlagsE::Ignored))
        return;
    flags_.add(SymbolFlagsE::Ignored);
    ctx.compiler().notifyAlive();
}

void Symbol::registerCompilerIf(Sema& sema)
{
    if (SemaCompilerIf* compilerIf = sema.frame().currentCompilerIf())
        compilerIf->addSymbolToChain(this);
}

void Symbol::registerAttributes(Sema& sema)
{
    setAttributes(sema.frame().currentAttributes());

    if (!attributes().hasRtFlag(RtAttributeFlagsE::PrintAst))
        return;

    if (!decl_)
        return;

    const AstNodeRef declRef = decl_->nodeRef(sema.ast());
    if (declRef.isInvalid())
        return;

    TaskContext& ctx = sema.ctx();

    if (shouldPrintAstStage(attributes(), K_AST_STAGE_PRE_SEMA))
        printAstStage(ctx, sema.ast(), *this, declRef, K_AST_STAGE_PRE_SEMA);

    if (shouldPrintAstStage(attributes(), K_AST_STAGE_POST_SEMA))
    {
        const Symbol* symbol = this;
        sema.deferPostNodeAction(declRef, [symbol](Sema& deferredSema, AstNodeRef nodeRef) {
            printAstStage(deferredSema.ctx(), deferredSema.ast(), *symbol, nodeRef, K_AST_STAGE_POST_SEMA);
            return Result::Continue;
        });
    }
}

bool Symbol::isType() const
{
    if (isEnum() || isStruct() || isInterface())
        return true;

    if (isAlias())
    {
        const SymbolAlias& symAlias = cast<SymbolAlias>();
        if (symAlias.aliasedSymbol())
            return symAlias.aliasedSymbol()->isType();
        return symAlias.typeRef().isValid();
    }

    return false;
}

bool Symbol::inSwagNamespace(const TaskContext& ctx) const noexcept
{
    const SymbolMap* const map = ownerSymMap();
    if (!map)
        return false;
    return map->isNamespace() && map->idRef() == ctx.idMgr().predefined(IdentifierManager::PredefinedName::Swag);
}

bool Symbol::deepCompare(const Symbol* other) const noexcept
{
    if (this == other)
        return true;
    if (kind_ != other->kind_)
        return false;
    if (isFunction())
        return cast<SymbolFunction>().deepCompare(other->cast<SymbolFunction>());
    return true;
}

std::string_view Symbol::name(const TaskContext& ctx) const
{
    if (idRef_.isInvalid())
        return "";
    const Identifier& id = ctx.idMgr().get(idRef_);
    return id.name;
}

Utf8 Symbol::getFullScopedName(const TaskContext& ctx) const
{
    Utf8 result;
    appendFullScopedName(ctx, result);
    return result;
}

void Symbol::appendFullScopedName(const TaskContext& ctx, Utf8& out) const
{
    // Walk scopes from inner → outer
    SmallVector8<const Symbol*> scopeChain;

    // Add the symbol itself
    scopeChain.push_back(this);

    // Walk owner scopes
    const SymbolMap* map = ownerSymMap_;
    while (map)
    {
        scopeChain.push_back(map);
        map = map->ownerSymMap();
    }

    // Emit in reverse (outer to inner)
    for (const auto& it : std::ranges::reverse_view(scopeChain))
    {
        if (!out.empty())
            out.append(".");
        out.append(it->name(ctx));
    }
}

const TypeInfo& Symbol::typeInfo(const TaskContext& ctx) const
{
    SWC_ASSERT(typeRef_.isValid());
    return ctx.typeMgr().get(typeRef_);
}

SWC_END_NAMESPACE();
