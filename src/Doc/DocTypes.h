#pragma once

#include "Backend/Runtime.h"
#include "Support/Core/Utf8.h"

#include <unordered_map>
#include <vector>

SWC_BEGIN_NAMESPACE();

class SourceFile;
class Symbol;
class TaskContext;

enum class DocItemKind : uint8_t
{
    Namespace,
    Struct,
    Interface,
    Enum,
    Constant,
    Alias,
    Attribute,
    Function,
};

struct DocPageOptions
{
    Runtime::BuildCfgDocKind  kind  = Runtime::BuildCfgDocKind::None;
    Runtime::BuildCfgDocTheme theme = Runtime::BuildCfgDocTheme::Auto;
    Utf8                      outputName;
    Utf8                      titleToc;
    Utf8                      titleContent;
    Utf8                      css;
    Utf8                      icon;
    Utf8                      morePages;
    Utf8                      quoteIconNote;
    Utf8                      quoteIconTip;
    Utf8                      quoteIconWarning;
    Utf8                      quoteIconAttention;
    Utf8                      quoteIconExample;
    Utf8                      quoteTitleNote;
    Utf8                      quoteTitleTip;
    Utf8                      quoteTitleWarning;
    Utf8                      quoteTitleAttention;
    Utf8                      quoteTitleExample;
    Utf8                      brandName;
    Utf8                      brandUrl;
    Utf8                      navLinks;
    Utf8                      footer;
    uint32_t                  syntaxDefaultColor = 0x00222222;
    uint32_t                  accentColor        = 0;
    bool                      hasSwagWatermark   = true;
    bool                      hasSymbolIndex     = true;
    bool                      hasSearch          = true;
};

struct DocOverload
{
    const Symbol*     symbol = nullptr;
    const SourceFile* file   = nullptr;
    Utf8              signature;
    std::vector<Utf8> commentLines;
    uint32_t          sourceLine = 0;
};

struct DocMember
{
    const Symbol*     symbol = nullptr;
    Utf8              fullName;
    Utf8              name;
    Utf8              typeName;
    std::vector<Utf8> commentLines;
};

struct DocItem
{
    DocItemKind              kind = DocItemKind::Function;
    Utf8                     fullName;
    Utf8                     displayName;
    Utf8                     ownerName;
    Utf8                     namespaceName;
    Utf8                     category;
    std::vector<DocOverload> overloads;
    std::vector<DocMember>   members;
};

struct DocGuide
{
    Utf8              title;
    Utf8              anchor;
    std::vector<Utf8> lines;
};

struct DocRenderContext
{
    TaskContext*                              ctx                = nullptr;
    const DocPageOptions*                     options            = nullptr;
    const std::unordered_map<Utf8, Utf8>*     references         = nullptr;
    const std::unordered_map<Utf8, Utf8>*     externalReferences = nullptr;
    const std::unordered_map<Utf8, Utf8>*     externalModules    = nullptr;
    const std::vector<std::pair<Utf8, Utf8>>* anonymousTypeNames = nullptr;
    Utf8                                      moduleName;
    Utf8                                      headingAnchorPrefix;
};

struct DocApiDocument
{
    std::vector<DocItem>           items;
    std::vector<DocGuide>          guides;
    std::vector<Utf8>              namespaceNames;
    std::unordered_map<Utf8, Utf8> references;
    std::unordered_map<Utf8, Utf8> externalReferences;
    std::unordered_map<Utf8, Utf8> externalModules;
    Utf8                           toc;
    Utf8                           content;
};

SWC_END_NAMESPACE();
