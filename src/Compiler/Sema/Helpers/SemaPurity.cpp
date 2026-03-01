#include "pch.h"
#include "Compiler/Sema/Helpers/SemaPurity.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isCompoundAssignToken(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::SymPlusEqual:
            case TokenId::SymMinusEqual:
            case TokenId::SymAsteriskEqual:
            case TokenId::SymSlashEqual:
            case TokenId::SymAmpersandEqual:
            case TokenId::SymPipeEqual:
            case TokenId::SymCircumflexEqual:
            case TokenId::SymPercentEqual:
            case TokenId::SymLowerLowerEqual:
            case TokenId::SymGreaterGreaterEqual:
                return true;

            default:
                break;
        }

        return false;
    }

    bool isIdentifierNodeMatching(Sema& sema, AstNodeRef exprRef, IdentifierRef expectedId)
    {
        const AstNodeRef nodeRef = sema.viewZero(exprRef).nodeRef();
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        if (!node.is(AstNodeId::Identifier))
            return false;

        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());
        return idRef == expectedId;
    }

    bool extractSingleLocalInitializer(Sema& sema, AstNodeRef stmtRef, IdentifierRef& outIdRef, AstNodeRef& outInitExprRef)
    {
        if (stmtRef.isInvalid())
            return false;

        AstNodeRef     varDeclRef = stmtRef;
        const AstNode& stmtNode   = sema.node(stmtRef);
        if (stmtNode.is(AstNodeId::VarDeclList))
        {
            SmallVector<AstNodeRef> decls;
            sema.ast().appendNodes(decls, stmtNode.cast<AstVarDeclList>().spanChildrenRef);
            if (decls.size() != 1)
                return false;
            varDeclRef = decls[0];
        }

        const AstNode& varDeclNode = sema.node(varDeclRef);
        if (!varDeclNode.is(AstNodeId::SingleVarDecl))
            return false;

        const auto& varDecl = varDeclNode.cast<AstSingleVarDecl>();
        if (!varDecl.tokNameRef.isValid() || varDecl.nodeInitRef.isInvalid())
            return false;

        outIdRef       = sema.idMgr().addIdentifier(sema.ctx(), SourceCodeRef{varDecl.srcViewRef(), varDecl.tokNameRef});
        outInitExprRef = sema.viewZero(varDecl.nodeInitRef).nodeRef();
        return outIdRef.isValid() && outInitExprRef.isValid();
    }

    AstNodeRef buildLinearLocalExpression(Sema& sema, std::span<const AstNodeRef> statements)
    {
        if (statements.size() < 2)
            return AstNodeRef::invalid();

        IdentifierRef localIdRef  = IdentifierRef::invalid();
        AstNodeRef    currentExpr = AstNodeRef::invalid();
        if (!extractSingleLocalInitializer(sema, statements[0], localIdRef, currentExpr))
            return AstNodeRef::invalid();

        for (size_t i = 1; i + 1 < statements.size(); i++)
        {
            const AstNode& stmtNode = sema.node(statements[i]);
            if (!stmtNode.is(AstNodeId::AssignStmt))
                return AstNodeRef::invalid();

            const auto& assignStmt = stmtNode.cast<AstAssignStmt>();
            if (assignStmt.modifierFlags != AstModifierFlagsE::Zero)
                return AstNodeRef::invalid();
            if (!isIdentifierNodeMatching(sema, assignStmt.nodeLeftRef, localIdRef))
                return AstNodeRef::invalid();

            const AstNodeRef rhsExprRef = sema.viewZero(assignStmt.nodeRightRef).nodeRef();
            if (rhsExprRef.isInvalid())
                return AstNodeRef::invalid();

            const TokenId tokenId = sema.token(assignStmt.codeRef()).id;
            if (tokenId == TokenId::SymEqual)
            {
                currentExpr = rhsExprRef;
                continue;
            }

            if (!isCompoundAssignToken(tokenId))
                return AstNodeRef::invalid();

            auto [binaryRef, binaryPtr] = sema.ast().makeNode<AstNodeId::BinaryExpr>(assignStmt.tokRef());
            binaryPtr->nodeLeftRef      = currentExpr;
            binaryPtr->nodeRightRef     = rhsExprRef;
            currentExpr                 = binaryRef;
        }

        const AstNode& retNode = sema.node(statements.back());
        if (!retNode.is(AstNodeId::ReturnStmt))
            return AstNodeRef::invalid();

        const auto& retStmt = retNode.cast<AstReturnStmt>();
        if (retStmt.nodeExprRef.isInvalid())
            return AstNodeRef::invalid();
        if (!isIdentifierNodeMatching(sema, retStmt.nodeExprRef, localIdRef))
            return AstNodeRef::invalid();

        return currentExpr;
    }

    AstNodeRef extractPureExprRef(Sema& sema, const SymbolFunction& fn)
    {
        const AstNode* declNode = fn.decl();
        if (!declNode)
            return AstNodeRef::invalid();
        if (!declNode->is(AstNodeId::FunctionDecl))
            return AstNodeRef::invalid();

        const Ast* const declAst = declNode->sourceAst(sema.ctx());
        if (!declAst || declAst != &sema.ast())
            return AstNodeRef::invalid();

        const auto& decl = declNode->cast<AstFunctionDecl>();
        if (decl.srcViewRef() != sema.ast().srcView().ref())
            return AstNodeRef::invalid();

        if (decl.hasFlag(AstFunctionFlagsE::Short))
            return decl.nodeBodyRef;

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& bodyNode = declAst->node(decl.nodeBodyRef);
        if (!bodyNode.is(AstNodeId::EmbeddedBlock))
            return AstNodeRef::invalid();
        const auto& block = bodyNode.cast<AstEmbeddedBlock>();

        SmallVector<AstNodeRef> statements;
        declAst->appendNodes(statements, block.spanChildrenRef);
        if (statements.size() == 1)
        {
            const AstNode& retNode = declAst->node(statements[0]);
            if (!retNode.is(AstNodeId::ReturnStmt))
                return AstNodeRef::invalid();
            const auto& retStmt = retNode.cast<AstReturnStmt>();
            if (retStmt.nodeExprRef.isInvalid())
                return AstNodeRef::invalid();

            return retStmt.nodeExprRef;
        }

        return buildLinearLocalExpression(sema, statements.span());
    }

    struct PureExpressionScanEntry
    {
        AstNodeRef nodeRef         = AstNodeRef::invalid();
        bool       checkIdentifier = true;
    };

    void pushPureExpressionChild(SmallVector<PureExpressionScanEntry>& out, AstNodeRef nodeRef, bool checkIdentifier)
    {
        if (!nodeRef.isValid())
            return;

        out.push_back({.nodeRef = nodeRef, .checkIdentifier = checkIdentifier});
    }

    bool appendPureExpressionChildren(const AstNode& node, SmallVector<PureExpressionScanEntry>& out)
    {
        switch (node.id())
        {
            case AstNodeId::BinaryExpr:
            {
                const auto& expr = node.cast<AstBinaryExpr>();
                pushPureExpressionChild(out, expr.nodeRightRef, true);
                pushPureExpressionChild(out, expr.nodeLeftRef, true);
                return true;
            }

            case AstNodeId::LogicalExpr:
            {
                const auto& expr = node.cast<AstLogicalExpr>();
                pushPureExpressionChild(out, expr.nodeRightRef, true);
                pushPureExpressionChild(out, expr.nodeLeftRef, true);
                return true;
            }

            case AstNodeId::RelationalExpr:
            {
                const auto& expr = node.cast<AstRelationalExpr>();
                pushPureExpressionChild(out, expr.nodeRightRef, true);
                pushPureExpressionChild(out, expr.nodeLeftRef, true);
                return true;
            }

            case AstNodeId::NullCoalescingExpr:
            {
                const auto& expr = node.cast<AstNullCoalescingExpr>();
                pushPureExpressionChild(out, expr.nodeRightRef, true);
                pushPureExpressionChild(out, expr.nodeLeftRef, true);
                return true;
            }

            case AstNodeId::ConditionalExpr:
            {
                const auto& expr = node.cast<AstConditionalExpr>();
                pushPureExpressionChild(out, expr.nodeFalseRef, true);
                pushPureExpressionChild(out, expr.nodeTrueRef, true);
                pushPureExpressionChild(out, expr.nodeCondRef, true);
                return true;
            }

            case AstNodeId::IndexExpr:
            {
                const auto& expr = node.cast<AstIndexExpr>();
                pushPureExpressionChild(out, expr.nodeArgRef, true);
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                return true;
            }

            case AstNodeId::MemberAccessExpr:
            {
                const auto& expr = node.cast<AstMemberAccessExpr>();
                pushPureExpressionChild(out, expr.nodeRightRef, false);
                pushPureExpressionChild(out, expr.nodeLeftRef, true);
                return true;
            }

            case AstNodeId::AutoMemberAccessExpr:
            {
                const auto& expr = node.cast<AstAutoMemberAccessExpr>();
                pushPureExpressionChild(out, expr.nodeIdentRef, false);
                return true;
            }

            case AstNodeId::Identifier:
                return true;

            case AstNodeId::AncestorIdentifier:
            {
                const auto& expr = node.cast<AstAncestorIdentifier>();
                pushPureExpressionChild(out, expr.nodeIdentRef, false);
                pushPureExpressionChild(out, expr.nodeValueRef, true);
                return true;
            }

            case AstNodeId::ParenExpr:
            {
                const auto& expr = node.cast<AstParenExpr>();
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                return true;
            }

            case AstNodeId::CastExpr:
            {
                const auto& expr = node.cast<AstCastExpr>();
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                pushPureExpressionChild(out, expr.nodeTypeRef, false);
                return true;
            }

            case AstNodeId::AutoCastExpr:
            {
                const auto& expr = node.cast<AstAutoCastExpr>();
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                return true;
            }

            case AstNodeId::AsCastExpr:
            {
                const auto& expr = node.cast<AstAsCastExpr>();
                pushPureExpressionChild(out, expr.nodeTypeRef, false);
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                return true;
            }

            case AstNodeId::IsTypeExpr:
            {
                const auto& expr = node.cast<AstIsTypeExpr>();
                pushPureExpressionChild(out, expr.nodeTypeRef, false);
                pushPureExpressionChild(out, expr.nodeExprRef, true);
                return true;
            }

            case AstNodeId::SuffixLiteral:
            {
                const auto& expr = node.cast<AstSuffixLiteral>();
                pushPureExpressionChild(out, expr.nodeSuffixRef, false);
                pushPureExpressionChild(out, expr.nodeLiteralRef, true);
                return true;
            }

            case AstNodeId::BoolLiteral:
            case AstNodeId::CharacterLiteral:
            case AstNodeId::FloatLiteral:
            case AstNodeId::IntegerLiteral:
            case AstNodeId::BinaryLiteral:
            case AstNodeId::HexaLiteral:
            case AstNodeId::NullLiteral:
                return true;

            default:
                return false;
        }
    }

    bool isPureExpression(Sema& sema, AstNodeRef rootRef, std::span<const IdentifierRef> parameterIds, uint32_t& budget)
    {
        if (rootRef.isInvalid())
            return false;

        SmallVector<PureExpressionScanEntry> toScan;
        pushPureExpressionChild(toScan, rootRef, true);
        while (!toScan.empty())
        {
            if (!budget)
                return false;
            budget--;

            const PureExpressionScanEntry entry = toScan.back();
            toScan.pop_back();

            const AstNode& node = sema.node(entry.nodeRef);
            if (!appendPureExpressionChildren(node, toScan))
                return false;

            if (!entry.checkIdentifier || !node.is(AstNodeId::Identifier))
                continue;

            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());
            if (std::ranges::find(parameterIds, idRef) == parameterIds.end())
                return false;
        }

        return true;
    }
}

namespace SemaPurity
{
    void computePurityFlag(Sema& sema, SymbolFunction& sym)
    {
        sym.setPureExpression(false);
        sym.setPureExpressionRef(AstNodeRef::invalid());

        const AstNodeRef srcExprRef = extractPureExprRef(sema, sym);
        if (srcExprRef.isInvalid())
            return;

        SmallVector<IdentifierRef> parameterIds;
        parameterIds.reserve(sym.parameters().size());
        for (const SymbolVariable* param : sym.parameters())
        {
            SWC_ASSERT(param != nullptr);
            if (param->idRef().isValid())
                parameterIds.push_back(param->idRef());
        }

        uint32_t expressionBudget = 64;
        if (!isPureExpression(sema, srcExprRef, parameterIds.span(), expressionBudget))
            return;

        sym.setPureExpression(true);
        sym.setPureExpressionRef(srcExprRef);
    }
}

SWC_END_NAMESPACE();
