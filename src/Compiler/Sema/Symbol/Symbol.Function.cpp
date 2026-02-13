#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collectFileConstIdentifiers(Sema& sema, const Ast& fnAst, std::unordered_set<IdentifierRef>& outConstIds)
    {
        Ast::visit(fnAst, fnAst.root(), [&](const AstNodeRef, const AstNode& node) {
            if (node.safeCast<AstFunctionDecl>() || node.safeCast<AstFunctionExpr>() || node.safeCast<AstClosureExpr>() || node.safeCast<AstCompilerFunc>() || node.safeCast<AstAttrDecl>())
                return Ast::VisitResult::Skip;

            if (const auto* single = node.safeCast<AstSingleVarDecl>())
            {
                if (!single->hasFlag(AstVarDeclFlagsE::Const))
                    return Ast::VisitResult::Continue;

                const SourceCodeRef codeRef{single->srcViewRef(), single->tokNameRef};
                outConstIds.insert(sema.idMgr().addIdentifier(sema.ctx(), codeRef));
                return Ast::VisitResult::Continue;
            }

            if (const auto* multi = node.safeCast<AstMultiVarDecl>())
            {
                if (!multi->hasFlag(AstVarDeclFlagsE::Const))
                    return Ast::VisitResult::Continue;

                SmallVector<TokenRef> tokNames;
                fnAst.appendTokens(tokNames, multi->spanNamesRef);
                for (const TokenRef tokRef : tokNames)
                {
                    const SourceCodeRef codeRef{multi->srcViewRef(), tokRef};
                    outConstIds.insert(sema.idMgr().addIdentifier(sema.ctx(), codeRef));
                }
            }

            return Ast::VisitResult::Continue;
        });
    }
}

Utf8 SymbolFunction::computeName(const TaskContext& ctx) const
{
    Utf8 out;
    out += hasExtraFlag(SymbolFunctionFlagsE::Method) ? "mtd" : "func";
    out += hasExtraFlag(SymbolFunctionFlagsE::Closure) ? "||" : "";
    out += "(";
    for (size_t i = 0; i < parameters_.size(); ++i)
    {
        if (i != 0)
            out += ", ";

        if (parameters_[i]->idRef().isValid())
        {
            out += parameters_[i]->name(ctx);
            out += ": ";
        }

        const TypeInfo& paramType = ctx.typeMgr().get(parameters_[i]->typeRef());
        out += paramType.toName(ctx);
    }
    out += ")";

    if (returnType_ != ctx.typeMgr().typeVoid())
    {
        out += "->";
        const TypeInfo& returnType = ctx.typeMgr().get(returnType_);
        out += returnType.toName(ctx);
    }

    out += hasExtraFlag(SymbolFunctionFlagsE::Throwable) ? " throw" : "";
    return out;
}

void SymbolFunction::setExtraFlags(EnumFlags<AstFunctionFlagsE> parserFlags)
{
    if (parserFlags.has(AstFunctionFlagsE::Method))
        addExtraFlag(SymbolFunctionFlagsE::Method);
    if (parserFlags.has(AstFunctionFlagsE::Throwable))
        addExtraFlag(SymbolFunctionFlagsE::Throwable);
    if (parserFlags.has(AstFunctionFlagsE::Closure))
        addExtraFlag(SymbolFunctionFlagsE::Closure);
    if (parserFlags.has(AstFunctionFlagsE::Const))
        addExtraFlag(SymbolFunctionFlagsE::Const);
}

bool SymbolFunction::deepCompare(const SymbolFunction& otherFunc) const noexcept
{
    if (this == &otherFunc)
        return true;

    if (idRef() != otherFunc.idRef())
        return false;
    if (returnTypeRef() != otherFunc.returnTypeRef())
        return false;
    if (extraFlags() != otherFunc.extraFlags())
        return false;

    const auto& params1 = parameters();
    const auto& params2 = otherFunc.parameters();
    if (params1.size() != params2.size())
        return false;

    for (uint32_t i = 0; i < params1.size(); ++i)
    {
        if (params1[i]->typeRef() != params2[i]->typeRef())
            return false;
    }

    return true;
}

SymbolStruct* SymbolFunction::ownerStruct()
{
    SymbolStruct* ownerStruct = nullptr;
    if (auto* symMap = ownerSymMap())
    {
        if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
            ownerStruct = symImpl->symStruct();
        else
            ownerStruct = symMap->safeCast<SymbolStruct>();
    }

    return ownerStruct;
}

const SymbolStruct* SymbolFunction::ownerStruct() const
{
    const SymbolStruct* ownerStruct = nullptr;
    if (const auto* symMap = ownerSymMap())
    {
        if (const auto* symImpl = symMap->safeCast<SymbolImpl>())
            ownerStruct = symImpl->symStruct();
        else
            ownerStruct = symMap->safeCast<SymbolStruct>();
    }

    return ownerStruct;
}

bool SymbolFunction::computePurity(Sema& sema) const
{
    const auto* decl = this->decl() ? this->decl()->safeCast<AstFunctionDecl>() : nullptr;
    if (!decl || !decl->hasFlag(AstFunctionFlagsE::Short) || decl->nodeBodyRef.isInvalid())
        return false;
    const Ast* fnAst = decl->sourceAst(sema.ctx());
    if (!fnAst)
        return false;

    std::unordered_set<IdentifierRef> paramIds;
    for (const SymbolVariable* param : parameters())
    {
        if (param && param->idRef().isValid())
            paramIds.insert(param->idRef());
    }
    std::unordered_set<IdentifierRef> constIds;
    collectFileConstIdentifiers(sema, *fnAst, constIds);

    bool isPure = true;
    Ast::visit(*fnAst, decl->nodeBodyRef, [&](const AstNodeRef, const AstNode& node) {
        if (node.safeCast<AstCompilerCall>() || node.safeCast<AstCompilerCallOne>() || node.safeCast<AstCompilerDiagnostic>())
            return Ast::VisitResult::Skip;

        if (node.safeCast<AstCallExpr>())
        {
            isPure = false;
            return Ast::VisitResult::Stop;
        }

        if (const auto* intrinsicCall = node.safeCast<AstIntrinsicCallExpr>())
        {
            if (intrinsicCall->nodeExprRef.isInvalid())
            {
                isPure = false;
                return Ast::VisitResult::Stop;
            }

            const AstNode& calleeNode = fnAst->node(intrinsicCall->nodeExprRef);
            if (!Token::isPureIntrinsic(sema.token(calleeNode.codeRef()).id))
            {
                isPure = false;
                return Ast::VisitResult::Stop;
            }

            return Ast::VisitResult::Continue;
        }

        const auto* ident = node.safeCast<AstIdentifier>();
        if (!ident || ident->hasFlag(AstIdentifierFlagsE::CallCallee))
            return Ast::VisitResult::Continue;

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), ident->codeRef());
        if (paramIds.contains(idRef) || constIds.contains(idRef))
            return Ast::VisitResult::Continue;

        isPure = false;
        return Ast::VisitResult::Stop;
    });

    return isPure;
}

SWC_END_NAMESPACE();
