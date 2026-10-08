#include "pch.h"
#include "Main/EditorIndex.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void writeString(std::ostream& out, std::string_view text)
    {
        out << '"';
        for (const unsigned char ch : text)
        {
            if (ch == '"' || ch == '\\')
                out << '\\' << ch;
            else if (ch < 0x20)
                out << std::format("\\u{:04x}", ch);
            else
                out << ch;
        }
        out << '"';
    }

    void writePath(std::ostream& out, const fs::path& path)
    {
        const auto text = FileSystem::absolutePathNoThrow(path).lexically_normal().generic_u8string();
        writeString(out, {reinterpret_cast<const char*>(text.data()), text.size()});
    }

    bool readOverlayString(std::istream& input, std::string& value)
    {
        std::string line;
        if (!std::getline(input, line))
            return false;
        uint32_t   size   = 0;
        const auto parsed = std::from_chars(line.data(), line.data() + line.size(), size);
        if (parsed.ec != std::errc{} || parsed.ptr != line.data() + line.size() || size > 64 * 1024 * 1024)
            return false;
        value.resize(size);
        return static_cast<bool>(input.read(value.data(), size));
    }

    std::string_view tokenKind(const Symbol& symbol)
    {
        switch (symbol.kind())
        {
            case SymbolKind::Namespace: return "namespace";
            case SymbolKind::Struct: return "struct";
            case SymbolKind::Interface: return "interface";
            case SymbolKind::Enum: return "enum";
            case SymbolKind::EnumValue: return "enumMember";
            case SymbolKind::Alias: return "type";
            case SymbolKind::Function: return "function";
            case SymbolKind::Variable:
                if (symbol.cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::Parameter))
                    return "parameter";
                if (symbol.ownerSymMap() && symbol.ownerSymMap()->isStruct())
                    return "property";
                return "variable";
            case SymbolKind::Constant: return "variable";
            default: return "";
        }
    }

    struct FileWriter
    {
        CompilerInstance*                      compiler    = nullptr;
        TaskContext*                           ctx         = nullptr;
        const SourceFile*                      file        = nullptr;
        std::ostream*                          out         = nullptr;
        std::unordered_set<const SourceFile*>* targetFiles = nullptr;
        bool                                   first       = true;

        const AstNode* writtenCallee(AstNodeRef ref) const
        {
            // Navigation needs the written name, even when sema substituted its expression.
            // The semantic call unwrapping helper deliberately follows those substitutions.
            while (ref.isValid())
            {
                const AstNode& node = file->ast().node(ref);
                switch (node.id())
                {
                    case AstNodeId::Identifier: return &node;
                    case AstNodeId::ParenExpr: ref = node.cast<AstParenExpr>().nodeExprRef; break;
                    case AstNodeId::QuotedExpr: ref = node.cast<AstQuotedExpr>().nodeExprRef; break;
                    case AstNodeId::QuotedListExpr: ref = node.cast<AstQuotedListExpr>().nodeExprRef; break;
                    case AstNodeId::MemberAccessExpr: ref = node.cast<AstMemberAccessExpr>().nodeRightRef; break;
                    case AstNodeId::AutoMemberAccessExpr: ref = node.cast<AstAutoMemberAccessExpr>().nodeIdentRef; break;
                    default: return nullptr;
                }
            }
            return nullptr;
        }

        void occurrence(const Symbol& symbol, const SourceView& source, TokenRef tokenRef)
        {
            if (!symbol.decl() || symbol.tokRef().isInvalid() || tokenRef.isInvalid() || symbol.isIgnored() || symbol.isExcludedByCondition())
                return;
            const auto kind = tokenKind(symbol);
            if (kind.empty() || source.ref() != file->ast().srcView().ref())
                return;
            const Token& token = source.token(tokenRef);
            if (token.id != TokenId::Identifier || source.tokenString(tokenRef) != symbol.name(*ctx))
                return;

            const SourceView& target = compiler->srcView(symbol.srcViewRef());
            // Generated views can reuse a physical file with different offsets. Until they have a
            // canonical source mapping, returning that file would navigate to unrelated text.
            if (!target.file() || target.ref() != target.file()->ast().srcView().ref())
                return;
            const Token& targetToken = target.token(symbol.tokRef());
            targetFiles->insert(target.file());
            const bool  declaration = target.ref() == source.ref() && symbol.tokRef() == tokenRef;
            const auto* variable    = symbol.decl()->safeCast<AstSingleVarDecl>();
            const bool  inferred    = declaration && variable && variable->nodeTypeRef.isInvalid() && variable->nodeInitRef.isValid();
            const bool  readonly    = symbol.isConstant() || symbol.isEnumValue() || symbol.isLetVariable();

            if (!first)
                *out << ',';
            first = false;
            *out << "{\"start\":" << source.tokenByteStart(token) << ",\"length\":" << token.byteLength << ",\"name\":";
            writeString(*out, source.tokenString(tokenRef));
            *out << ",\"kind\":";
            writeString(*out, kind);
            *out << ",\"type\":";
            writeString(*out, symbol.typeRef().isValid() ? symbol.typeInfo(*ctx).toName(*ctx).view() : std::string_view{});
            *out << ",\"declaration\":" << (declaration ? "true" : "false") << ",\"readonly\":" << (readonly ? "true" : "false");
            *out << ",\"inferred\":" << (inferred ? "true" : "false") << ",\"definition\":{\"path\":";
            writePath(*out, target.file()->path());
            *out << ",\"start\":" << target.tokenByteStart(targetToken) << ",\"length\":" << targetToken.byteLength << "}}";
        }

        void visit(AstNodeRef ref, const AstNode& node)
        {
            const NodePayload& payload  = file->nodePayloadContext();
            const auto         resolved = payload.resolveSymbols(ref);
            for (const Symbol* symbol : resolved.symbols)
            {
                if (symbol && symbol->decl() == &node)
                    occurrence(*symbol, compiler->srcView(symbol->srcViewRef()), symbol->tokRef());
            }

            const Symbol* symbol = resolved.symbols.size() == 1 ? resolved.symbols.front() : payload.foldedSourceSymbol(ref);
            if (symbol)
            {
                occurrence(*symbol, compiler->srcView(node.srcViewRef()), node.tokRef());
                const auto* call = node.safeCast<AstCallExpr>();
                if (call && symbol->isFunction())
                {
                    const AstNode* callee = writtenCallee(call->nodeExprRef);
                    if (callee)
                        occurrence(*symbol, compiler->srcView(callee->srcViewRef()), callee->tokRef());
                }
            }
        }
    };
}

std::string EditorIndex::pathKey(const fs::path& path)
{
    auto text = FileSystem::absolutePathNoThrow(path).lexically_normal().generic_u8string();
#ifdef _WIN32
    for (auto& ch : text)
    {
        if (ch >= u8'A' && ch <= u8'Z')
            ch += u8'a' - u8'A';
    }
#endif
    return {reinterpret_cast<const char*>(text.data()), text.size()};
}

Result EditorIndex::loadOverlays(CommandLine& cmdLine)
{
    if (cmdLine.editorOverlay.empty())
        return Result::Continue;
    std::ifstream input(cmdLine.editorOverlay, std::ios::binary);
    std::string   header;
    auto          sources = std::make_shared<std::unordered_map<std::string, std::string>>();
    bool          valid   = static_cast<bool>(std::getline(input, header)) && header == "SWAG-EDITOR-1";
    while (valid && input.peek() != std::char_traits<char>::eof())
    {
        std::string path;
        std::string content;
        valid = readOverlayString(input, path) && readOverlayString(input, content);
        if (valid)
            sources->insert_or_assign(pathKey(fs::path(std::u8string(path.begin(), path.end()))), std::move(content));
    }
    if (!valid || input.bad())
    {
        std::println(stderr, "cannot read editor overlay '{}': expected SWAG-EDITOR-1 and length-prefixed UTF-8 paths and buffers", cmdLine.editorOverlay.string());
        return Result::Error;
    }
    cmdLine.editorSources = std::move(sources);
    return Result::Continue;
}

Result EditorIndex::write(CompilerInstance& compiler)
{
    std::ofstream out(compiler.cmdLine().editorIndex, std::ios::binary | std::ios::trunc);
    TaskContext   ctx(compiler);

    std::unordered_map<std::string, std::string> indexedSources;
    std::unordered_set<std::string>              modulePaths;
    std::unordered_set<const SourceFile*>        targetFiles;
    const CommandLine&                           cmdLine      = compiler.cmdLine();
    const std::string                            moduleKey    = cmdLine.modulePath.empty() ? std::string{} : pathKey(cmdLine.modulePath);
    const std::string                            modulePrefix = moduleKey.empty() || moduleKey.ends_with('/') ? moduleKey : moduleKey + "/";

    // Editor queries only search the requested module. Imported API files are included below
    // only when one of those queries points to a declaration inside them.
    for (const SourceFile* file : compiler.files())
    {
        if (!file || !file->ast().hasSourceView())
            continue;

        const std::string key      = pathKey(file->path());
        const bool        inModule = !moduleKey.empty()
                                         ? key == moduleKey || key.starts_with(modulePrefix)
                                         : std::ranges::any_of(cmdLine.files, [&](const fs::path& path) { return key == pathKey(path); });
        if (!inModule)
            continue;

        modulePaths.insert(key);
        std::ostringstream occurrences;
        if (!Stats::hasError() && file->ast().root().isValid() && !file->isRuntime() && !file->isImportedApi())
        {
            FileWriter writer{&compiler, &ctx, file, &occurrences, &targetFiles};
            Ast::visit(file->ast(), file->ast().root(), [&](AstNodeRef ref, const AstNode& node) {
                writer.visit(ref, node);
                return Ast::VisitResult::Continue;
            });
        }
        indexedSources.emplace(key, occurrences.str());
    }

    out << "{\"version\":1,\"complete\":" << (Stats::hasError() ? "false" : "true") << ",\"files\":[";
    bool first = true;
    for (const SourceFile* file : compiler.files())
    {
        if (!file || !file->ast().hasSourceView())
            continue;

        const auto key = pathKey(file->path());
        if (!modulePaths.contains(key) && !targetFiles.contains(file))
            continue;

        if (!first)
            out << ',';
        first = false;
        out << "{\"path\":";
        writePath(out, file->path());
        out << ",\"text\":";
        writeString(out, file->sourceView());
        out << ",\"occurrences\":[";
        const auto source = indexedSources.find(key);
        if (source != indexedSources.end())
        {
            out << source->second;
        }
        out << "]}";
    }
    out << "]}";
    out.close();
    if (!out)
    {
        std::println(stderr, "cannot write editor snapshot '{}'", compiler.cmdLine().editorIndex.string());
        return Result::Error;
    }
    return Result::Continue;
}

SWC_END_NAMESPACE();
