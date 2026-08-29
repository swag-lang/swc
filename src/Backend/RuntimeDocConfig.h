#pragma once
#include "Backend/RuntimeBase.h"

SWC_BEGIN_NAMESPACE();

namespace Runtime
{
    enum class BuildCfgDocKind
    {
        None,
        Api,
        Examples,
        Pages,
    };

    enum class BuildCfgDocTheme
    {
        Auto,
        Light,
        Dark,
    };

    struct BuildCfgGenDoc
    {
        BuildCfgDocKind  kind = BuildCfgDocKind::None;
        String           outputName;
        String           titleToc;
        String           titleContent;
        String           css;
        String           icon;
        String           morePages;
        String           quoteIconNote;
        String           quoteIconTip;
        String           quoteIconWarning;
        String           quoteIconAttention;
        String           quoteIconExample;
        String           quoteTitleNote;
        String           quoteTitleTip;
        String           quoteTitleWarning;
        String           quoteTitleAttention;
        String           quoteTitleExample;
        String           brandName;
        String           brandUrl;
        String           navLinks;
        String           footer;
        uint32_t         syntaxDefaultColor = 0x00222222;
        float            syntaxColorLum     = 0.5f;
        uint32_t         accentColor        = 0;
        BuildCfgDocTheme theme              = BuildCfgDocTheme::Auto;
        bool             hasSwagWatermark   = true;
        bool             hasSymbolIndex     = true;
        bool             hasSearch          = true;
    };
}

SWC_END_NAMESPACE();
