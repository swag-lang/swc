#include "pch.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void collectParamNames(const Ast& fnAst, const AstFunctionDecl& decl, std::unordered_set<std::string_view>& outParamNames)
    {
        if (decl.nodeParamsRef.isInvalid())
            return;

        Ast::visit(fnAst, decl.nodeParamsRef, [&](const AstNodeRef, const AstNode& node) {
            if (const auto* single = node.safeCast<AstSingleVarDecl>())
            {
                if (single->tokNameRef.isValid())
                    outParamNames.insert(fnAst.srcView().tokenString(single->tokNameRef));
                return Ast::VisitResult::Continue;
            }

            if (const auto* multi = node.safeCast<AstMultiVarDecl>())
            {
                SmallVector<TokenRef> tokNames;
                fnAst.appendTokens(tokNames, multi->spanNamesRef);
                for (const TokenRef tokRef : tokNames)
                {
                    if (tokRef.isValid())
                        outParamNames.insert(fnAst.srcView().tokenString(tokRef));
                }
                return Ast::VisitResult::Continue;
            }

            if (const auto* me = node.safeCast<AstFunctionParamMe>())
            {
                if (me->tokRef().isValid())
                    outParamNames.insert(fnAst.srcView().tokenString(me->tokRef()));
            }

            return Ast::VisitResult::Continue;
        });
    }

    bool isConstIdentifierFromAst(const Ast& fnAst, const AstIdentifier& ident)
    {
        if (ident.tokRef().isInvalid())
            return false;

        const std::string_view identName = fnAst.srcView().tokenString(ident.tokRef());
        bool                   isConst   = false;
        Ast::visit(fnAst, fnAst.root(), [&](const AstNodeRef, const AstNode& node) {
            if (node.safeCast<AstFunctionDecl>() || node.safeCast<AstFunctionExpr>() || node.safeCast<AstClosureExpr>() || node.safeCast<AstCompilerFunc>() || node.safeCast<AstAttrDecl>())
                return Ast::VisitResult::Skip;

            if (const auto* single = node.safeCast<AstSingleVarDecl>())
            {
                if (!single->hasFlag(AstVarDeclFlagsE::Const))
                    return Ast::VisitResult::Continue;
                if (single->tokNameRef.isValid() && fnAst.srcView().tokenString(single->tokNameRef) == identName)
                {
                    isConst = true;
                    return Ast::VisitResult::Stop;
                }
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
                    if (tokRef.isValid() && fnAst.srcView().tokenString(tokRef) == identName)
                    {
                        isConst = true;
                        return Ast::VisitResult::Stop;
                    }
                }
            }

            return Ast::VisitResult::Continue;
        });

        return isConst;
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

bool SymbolFunction::isPure(const TaskContext& ctx) const
{
    computeAstFlags(ctx);
    return hasExtraFlag(SymbolFunctionFlagsE::Pure);
}

void SymbolFunction::computeAstFlags(const TaskContext& ctx) const
{
    std::call_once(pureFromAstOnce_, [&]() {
        auto* self = const_cast<SymbolFunction*>(this);
        if (computePurity(ctx))
            self->addExtraFlag(SymbolFunctionFlagsE::Pure);
    });
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

bool SymbolFunction::computePurity(const TaskContext& ctx) const
{
    const auto* decl = this->decl() ? this->decl()->safeCast<AstFunctionDecl>() : nullptr;
    if (!decl || !decl->hasFlag(AstFunctionFlagsE::Short) || decl->nodeBodyRef.isInvalid())
        return false;
    const Ast* fnAst = decl->sourceAst(ctx);
    if (!fnAst)
        return false;

    std::unordered_set<std::string_view> paramNames;
    collectParamNames(*fnAst, *decl, paramNames);

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
            if (calleeNode.srcViewRef() != fnAst->srcView().ref() || calleeNode.tokRef().isInvalid())
            {
                isPure = false;
                return Ast::VisitResult::Stop;
            }

            if (!Token::isPureIntrinsic(fnAst->srcView().token(calleeNode.tokRef()).id))
            {
                isPure = false;
                return Ast::VisitResult::Stop;
            }

            return Ast::VisitResult::Continue;
        }

        const auto* ident = node.safeCast<AstIdentifier>();
        if (!ident || ident->hasFlag(AstIdentifierFlagsE::CallCallee))
            return Ast::VisitResult::Continue;

        if (!ident->tokRef().isValid())
            return Ast::VisitResult::Continue;

        const std::string_view identName = fnAst->srcView().tokenString(ident->tokRef());
        if (paramNames.contains(identName) || isConstIdentifierFromAst(*fnAst, *ident))
            return Ast::VisitResult::Continue;

        isPure = false;
        return Ast::VisitResult::Stop;
    });

    return isPure;
}

SWC_END_NAMESPACE();
