<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php include('common/start-head.php'); ?><title>Module gdi32</title>
<link rel="stylesheet" type="text/css" href="css/style.css">
<script src="https://kit.fontawesome.com/f76be2b3ee.js" crossorigin="anonymous"></script>
<style>
.container{display:flex;flex-wrap:nowrap;flex-direction:row;margin:0 auto;padding:0}.left{display:block;overflow-y:auto;width:500px}.left-page{margin:10px}.right{display:block;width:100%}.right-page{max-width:1024px;margin:10px auto}
@media(min-width:640px){.container{max-width:640px}}@media(min-width:768px){.container{max-width:768px}}@media(min-width:1024px){.container{max-width:1024px}}@media(min-width:1280px){.container{max-width:1280px}}@media(min-width:1536px){.container{max-width:1536px}}@media screen and (max-width:600px){.left{display:none}.right-page{margin:10px}}
html{font-family:ui-sans-serif,system-ui,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif}body{margin:0;line-height:1.3em}.container a{color:DodgerBlue}.container a:hover{text-decoration:underline}.container img{margin:0 auto}.left a{text-decoration:none}.left ul{list-style-type:none;margin-left:-20px}.left h3{background-color:#000;color:#fff;padding:6px}.right h1{margin-top:50px;margin-bottom:50px}.right h2{margin-top:35px}.right hr{margin-top:50px;margin-bottom:50px}.strikethrough-text{text-decoration:line-through}.swag-watermark{text-align:right;font-size:80%;margin-top:30px}.swag-watermark a{text-decoration:none;color:inherit}
.blockquote{border-radius:5px;border:1px solid;margin:20px;padding:10px}.blockquote-default{border-color:orange;border-left:6px solid orange;background-color:#ffffe0}.blockquote-note{border-color:#adcedd;background-color:#cdeefd}.blockquote-tip{border-color:#bccfbc;background-color:#dcefdc}.blockquote-warning{border-color:#dfbdb3;background-color:#ffddd3}.blockquote-attention{border-color:#ddbab8;background-color:#fddad8}.blockquote-example{border:2px solid #d3d3d3}.blockquote-title-block{margin-bottom:10px}.blockquote-title{font-weight:bold}.description-list-title{font-weight:bold;font-style:italic}.description-list-block{margin-left:30px}
.container table{border:1px solid #d3d3d3;border-collapse:collapse;font-size:90%;margin:20px}.container td,.container th{border:1px solid #d3d3d3;padding:6px;min-width:100px}.container th{background-color:#eee}table.api-item{border-collapse:separate;background-color:#000;color:#fff;width:100%;margin:70px 0 0;font-size:110%}.api-item td{font-size:revert;border:0}.api-item td:first-child{width:66%;white-space:nowrap}.api-item-title-src-ref{text-align:right}.api-item-title-src-ref a{color:inherit}.api-item-title-kind{font-weight:normal;font-size:80%}.api-item-title-strong{font-weight:bold}.table-enumeration{width:calc(100% - 40px)}.table-enumeration td:first-child{background-color:#f8f8f8;white-space:nowrap}.table-enumeration td:last-child{width:100%}.table-enumeration td.code-type{background-color:#eee}.table-enumeration a{text-decoration:none;color:inherit}
.code-inline{background-color:#eee;border-radius:5px;border:1px dotted #ccc;padding:0 8px;font-size:110%;font-family:monospace;display:inline-block}.code-block{background-color:#eee;border-radius:5px;border:1px solid #d3d3d3;padding:10px;margin:20px;white-space:pre;overflow-x:auto;font-family:ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono",monospace}.code-block a{color:inherit}
.SCmt{color:#6a9955}.SCmp,.SAtr{color:#777}.SFct{color:#c54f00}.SCst{color:#168f7d}.SItr{color:#8a7600}.STpe{color:#a66c00}.SKwd{color:#286fa8}.SLgc{color:#8e4d99}.SNum{color:#4d7a45}.SStr{color:#a64f38}.SInv{color:#d22}.SBcR{color:#817c31}
.SCde{color:#222222}
.container{height:100vh}.right{overflow-y:auto}
</style>
<?php include('common/end-head.php'); ?>
</head>
<body>
<?php include('common/start-body.php'); ?>
<div class="container">
<div class="left"><div class="left-page">
<h2>Table of Contents</h2>
<h3>Structs</h3>
<li><a href="#Gdi32_BITMAP">Gdi32.BITMAP</a></li>
<li><a href="#Gdi32_BITMAPINFO">Gdi32.BITMAPINFO</a></li>
<li><a href="#Gdi32_BITMAPINFOHEADER">Gdi32.BITMAPINFOHEADER</a></li>
<li><a href="#Gdi32_ENUMLOGFONTEXA">Gdi32.ENUMLOGFONTEXA</a></li>
<li><a href="#Gdi32_ENUMLOGFONTEXW">Gdi32.ENUMLOGFONTEXW</a></li>
<li><a href="#Gdi32_LOGFONTA">Gdi32.LOGFONTA</a></li>
<li><a href="#Gdi32_LOGFONTW">Gdi32.LOGFONTW</a></li>
<li><a href="#Gdi32_NEWTEXTMETRICA">Gdi32.NEWTEXTMETRICA</a></li>
<li><a href="#Gdi32_NEWTEXTMETRICW">Gdi32.NEWTEXTMETRICW</a></li>
<li><a href="#Gdi32_PIXELFORMATDESCRIPTOR">Gdi32.PIXELFORMATDESCRIPTOR</a></li>
<li><a href="#Gdi32_RGBQUAD">Gdi32.RGBQUAD</a></li>
<li><a href="#Gdi32_TEXTMETRICA">Gdi32.TEXTMETRICA</a></li>
<li><a href="#Gdi32_TEXTMETRICW">Gdi32.TEXTMETRICW</a></li>
<h3>Constants</h3>
<li><a href="#Gdi32_ANSI_CHARSET">Gdi32.ANSI_CHARSET</a></li>
<li><a href="#Gdi32_ANSI_FIXED_FONT">Gdi32.ANSI_FIXED_FONT</a></li>
<li><a href="#Gdi32_ANSI_VAR_FONT">Gdi32.ANSI_VAR_FONT</a></li>
<li><a href="#Gdi32_ARABIC_CHARSET">Gdi32.ARABIC_CHARSET</a></li>
<li><a href="#Gdi32_ASPECTX">Gdi32.ASPECTX</a></li>
<li><a href="#Gdi32_ASPECTXY">Gdi32.ASPECTXY</a></li>
<li><a href="#Gdi32_ASPECTY">Gdi32.ASPECTY</a></li>
<li><a href="#Gdi32_BALTIC_CHARSET">Gdi32.BALTIC_CHARSET</a></li>
<li><a href="#Gdi32_BITSPIXEL">Gdi32.BITSPIXEL</a></li>
<li><a href="#Gdi32_BI_BITFIELDS">Gdi32.BI_BITFIELDS</a></li>
<li><a href="#Gdi32_BI_JPEG">Gdi32.BI_JPEG</a></li>
<li><a href="#Gdi32_BI_PNG">Gdi32.BI_PNG</a></li>
<li><a href="#Gdi32_BI_RGB">Gdi32.BI_RGB</a></li>
<li><a href="#Gdi32_BI_RLE4">Gdi32.BI_RLE4</a></li>
<li><a href="#Gdi32_BI_RLE8">Gdi32.BI_RLE8</a></li>
<li><a href="#Gdi32_BKMODE_LAST">Gdi32.BKMODE_LAST</a></li>
<li><a href="#Gdi32_BLACKNESS">Gdi32.BLACKNESS</a></li>
<li><a href="#Gdi32_BLACK_BRUSH">Gdi32.BLACK_BRUSH</a></li>
<li><a href="#Gdi32_BLACK_PEN">Gdi32.BLACK_PEN</a></li>
<li><a href="#Gdi32_BLTALIGNMENT">Gdi32.BLTALIGNMENT</a></li>
<li><a href="#Gdi32_CAPTUREBLT">Gdi32.CAPTUREBLT</a></li>
<li><a href="#Gdi32_CHINESEBIG5_CHARSET">Gdi32.CHINESEBIG5_CHARSET</a></li>
<li><a href="#Gdi32_CLIPCAPS">Gdi32.CLIPCAPS</a></li>
<li><a href="#Gdi32_COLORMGMTCAPS">Gdi32.COLORMGMTCAPS</a></li>
<li><a href="#Gdi32_COLORRES">Gdi32.COLORRES</a></li>
<li><a href="#Gdi32_CURVECAPS">Gdi32.CURVECAPS</a></li>
<li><a href="#Gdi32_DEFAULT_CHARSET">Gdi32.DEFAULT_CHARSET</a></li>
<li><a href="#Gdi32_DEFAULT_PALETTE">Gdi32.DEFAULT_PALETTE</a></li>
<li><a href="#Gdi32_DESKTOPHORZRES">Gdi32.DESKTOPHORZRES</a></li>
<li><a href="#Gdi32_DESKTOPVERTRES">Gdi32.DESKTOPVERTRES</a></li>
<li><a href="#Gdi32_DEVICE_DEFAULT_FONT">Gdi32.DEVICE_DEFAULT_FONT</a></li>
<li><a href="#Gdi32_DEVICE_FONTTYPE">Gdi32.DEVICE_FONTTYPE</a></li>
<li><a href="#Gdi32_DIB_PAL_COLORS">Gdi32.DIB_PAL_COLORS</a></li>
<li><a href="#Gdi32_DIB_RGB_COLORS">Gdi32.DIB_RGB_COLORS</a></li>
<li><a href="#Gdi32_DKGRAY_BRUSH">Gdi32.DKGRAY_BRUSH</a></li>
<li><a href="#Gdi32_DRIVERVERSION">Gdi32.DRIVERVERSION</a></li>
<li><a href="#Gdi32_DSTINVERT">Gdi32.DSTINVERT</a></li>
<li><a href="#Gdi32_EASTEUROPE_CHARSET">Gdi32.EASTEUROPE_CHARSET</a></li>
<li><a href="#Gdi32_FW_BLACK">Gdi32.FW_BLACK</a></li>
<li><a href="#Gdi32_FW_BOLD">Gdi32.FW_BOLD</a></li>
<li><a href="#Gdi32_FW_DEMIBOLD">Gdi32.FW_DEMIBOLD</a></li>
<li><a href="#Gdi32_FW_DONTCARE">Gdi32.FW_DONTCARE</a></li>
<li><a href="#Gdi32_FW_EXTRABOLD">Gdi32.FW_EXTRABOLD</a></li>
<li><a href="#Gdi32_FW_EXTRALIGHT">Gdi32.FW_EXTRALIGHT</a></li>
<li><a href="#Gdi32_FW_HEAVY">Gdi32.FW_HEAVY</a></li>
<li><a href="#Gdi32_FW_LIGHT">Gdi32.FW_LIGHT</a></li>
<li><a href="#Gdi32_FW_MEDIUM">Gdi32.FW_MEDIUM</a></li>
<li><a href="#Gdi32_FW_NORMAL">Gdi32.FW_NORMAL</a></li>
<li><a href="#Gdi32_FW_REGULAR">Gdi32.FW_REGULAR</a></li>
<li><a href="#Gdi32_FW_SEMIBOLD">Gdi32.FW_SEMIBOLD</a></li>
<li><a href="#Gdi32_FW_THIN">Gdi32.FW_THIN</a></li>
<li><a href="#Gdi32_FW_ULTRABOLD">Gdi32.FW_ULTRABOLD</a></li>
<li><a href="#Gdi32_FW_ULTRALIGHT">Gdi32.FW_ULTRALIGHT</a></li>
<li><a href="#Gdi32_GB2312_CHARSET">Gdi32.GB2312_CHARSET</a></li>
<li><a href="#Gdi32_GDI_ERROR">Gdi32.GDI_ERROR</a></li>
<li><a href="#Gdi32_GRAY_BRUSH">Gdi32.GRAY_BRUSH</a></li>
<li><a href="#Gdi32_GREEK_CHARSET">Gdi32.GREEK_CHARSET</a></li>
<li><a href="#Gdi32_HANGEUL_CHARSET">Gdi32.HANGEUL_CHARSET</a></li>
<li><a href="#Gdi32_HANGUL_CHARSET">Gdi32.HANGUL_CHARSET</a></li>
<li><a href="#Gdi32_HEBREW_CHARSET">Gdi32.HEBREW_CHARSET</a></li>
<li><a href="#Gdi32_HOLLOW_BRUSH">Gdi32.HOLLOW_BRUSH</a></li>
<li><a href="#Gdi32_HORZRES">Gdi32.HORZRES</a></li>
<li><a href="#Gdi32_HORZSIZE">Gdi32.HORZSIZE</a></li>
<li><a href="#Gdi32_JOHAB_CHARSET">Gdi32.JOHAB_CHARSET</a></li>
<li><a href="#Gdi32_LF_FACESIZE">Gdi32.LF_FACESIZE</a></li>
<li><a href="#Gdi32_LF_FULLFACESIZE">Gdi32.LF_FULLFACESIZE</a></li>
<li><a href="#Gdi32_LINECAPS">Gdi32.LINECAPS</a></li>
<li><a href="#Gdi32_LOGPIXELSX">Gdi32.LOGPIXELSX</a></li>
<li><a href="#Gdi32_LOGPIXELSY">Gdi32.LOGPIXELSY</a></li>
<li><a href="#Gdi32_LTGRAY_BRUSH">Gdi32.LTGRAY_BRUSH</a></li>
<li><a href="#Gdi32_MAC_CHARSET">Gdi32.MAC_CHARSET</a></li>
<li><a href="#Gdi32_MERGECOPY">Gdi32.MERGECOPY</a></li>
<li><a href="#Gdi32_MERGEPAINT">Gdi32.MERGEPAINT</a></li>
<li><a href="#Gdi32_NOMIRRORBITMAP">Gdi32.NOMIRRORBITMAP</a></li>
<li><a href="#Gdi32_NOTSRCCOPY">Gdi32.NOTSRCCOPY</a></li>
<li><a href="#Gdi32_NOTSRCERASE">Gdi32.NOTSRCERASE</a></li>
<li><a href="#Gdi32_NULL_BRUSH">Gdi32.NULL_BRUSH</a></li>
<li><a href="#Gdi32_NULL_PEN">Gdi32.NULL_PEN</a></li>
<li><a href="#Gdi32_NUMBRUSHES">Gdi32.NUMBRUSHES</a></li>
<li><a href="#Gdi32_NUMCOLORS">Gdi32.NUMCOLORS</a></li>
<li><a href="#Gdi32_NUMFONTS">Gdi32.NUMFONTS</a></li>
<li><a href="#Gdi32_NUMMARKERS">Gdi32.NUMMARKERS</a></li>
<li><a href="#Gdi32_NUMPENS">Gdi32.NUMPENS</a></li>
<li><a href="#Gdi32_NUMRESERVED">Gdi32.NUMRESERVED</a></li>
<li><a href="#Gdi32_OEM_CHARSET">Gdi32.OEM_CHARSET</a></li>
<li><a href="#Gdi32_OEM_FIXED_FONT">Gdi32.OEM_FIXED_FONT</a></li>
<li><a href="#Gdi32_OPAQUE">Gdi32.OPAQUE</a></li>
<li><a href="#Gdi32_PATCOPY">Gdi32.PATCOPY</a></li>
<li><a href="#Gdi32_PATINVERT">Gdi32.PATINVERT</a></li>
<li><a href="#Gdi32_PATPAINT">Gdi32.PATPAINT</a></li>
<li><a href="#Gdi32_PDEVICESIZE">Gdi32.PDEVICESIZE</a></li>
<li><a href="#Gdi32_PFD_DEPTH_DONTCARE">Gdi32.PFD_DEPTH_DONTCARE</a></li>
<li><a href="#Gdi32_PFD_DIRECT3D_ACCELERATED">Gdi32.PFD_DIRECT3D_ACCELERATED</a></li>
<li><a href="#Gdi32_PFD_DOUBLEBUFFER">Gdi32.PFD_DOUBLEBUFFER</a></li>
<li><a href="#Gdi32_PFD_DOUBLEBUFFER_DONTCARE">Gdi32.PFD_DOUBLEBUFFER_DONTCARE</a></li>
<li><a href="#Gdi32_PFD_DRAW_TO_BITMAP">Gdi32.PFD_DRAW_TO_BITMAP</a></li>
<li><a href="#Gdi32_PFD_DRAW_TO_WINDOW">Gdi32.PFD_DRAW_TO_WINDOW</a></li>
<li><a href="#Gdi32_PFD_GENERIC_ACCELERATED">Gdi32.PFD_GENERIC_ACCELERATED</a></li>
<li><a href="#Gdi32_PFD_GENERIC_FORMAT">Gdi32.PFD_GENERIC_FORMAT</a></li>
<li><a href="#Gdi32_PFD_MAIN_PLANE">Gdi32.PFD_MAIN_PLANE</a></li>
<li><a href="#Gdi32_PFD_NEED_PALETTE">Gdi32.PFD_NEED_PALETTE</a></li>
<li><a href="#Gdi32_PFD_NEED_SYSTEM_PALETTE">Gdi32.PFD_NEED_SYSTEM_PALETTE</a></li>
<li><a href="#Gdi32_PFD_OVERLAY_PLANE">Gdi32.PFD_OVERLAY_PLANE</a></li>
<li><a href="#Gdi32_PFD_STEREO">Gdi32.PFD_STEREO</a></li>
<li><a href="#Gdi32_PFD_STEREO_DONTCARE">Gdi32.PFD_STEREO_DONTCARE</a></li>
<li><a href="#Gdi32_PFD_SUPPORT_COMPOSITION">Gdi32.PFD_SUPPORT_COMPOSITION</a></li>
<li><a href="#Gdi32_PFD_SUPPORT_DIRECTDRAW">Gdi32.PFD_SUPPORT_DIRECTDRAW</a></li>
<li><a href="#Gdi32_PFD_SUPPORT_GDI">Gdi32.PFD_SUPPORT_GDI</a></li>
<li><a href="#Gdi32_PFD_SUPPORT_OPENGL">Gdi32.PFD_SUPPORT_OPENGL</a></li>
<li><a href="#Gdi32_PFD_SWAP_COPY">Gdi32.PFD_SWAP_COPY</a></li>
<li><a href="#Gdi32_PFD_SWAP_EXCHANGE">Gdi32.PFD_SWAP_EXCHANGE</a></li>
<li><a href="#Gdi32_PFD_SWAP_LAYER_BUFFERS">Gdi32.PFD_SWAP_LAYER_BUFFERS</a></li>
<li><a href="#Gdi32_PFD_TYPE_COLORINDEX">Gdi32.PFD_TYPE_COLORINDEX</a></li>
<li><a href="#Gdi32_PFD_TYPE_RGBA">Gdi32.PFD_TYPE_RGBA</a></li>
<li><a href="#Gdi32_PFD_UNDERLAY_PLANE">Gdi32.PFD_UNDERLAY_PLANE</a></li>
<li><a href="#Gdi32_PHYSICALHEIGHT">Gdi32.PHYSICALHEIGHT</a></li>
<li><a href="#Gdi32_PHYSICALOFFSETX">Gdi32.PHYSICALOFFSETX</a></li>
<li><a href="#Gdi32_PHYSICALOFFSETY">Gdi32.PHYSICALOFFSETY</a></li>
<li><a href="#Gdi32_PHYSICALWIDTH">Gdi32.PHYSICALWIDTH</a></li>
<li><a href="#Gdi32_PLANES">Gdi32.PLANES</a></li>
<li><a href="#Gdi32_POLYGONALCAPS">Gdi32.POLYGONALCAPS</a></li>
<li><a href="#Gdi32_PS_ALTERNATE">Gdi32.PS_ALTERNATE</a></li>
<li><a href="#Gdi32_PS_DASH">Gdi32.PS_DASH</a></li>
<li><a href="#Gdi32_PS_DASHDOT">Gdi32.PS_DASHDOT</a></li>
<li><a href="#Gdi32_PS_DASHDOTDOT">Gdi32.PS_DASHDOTDOT</a></li>
<li><a href="#Gdi32_PS_DOT">Gdi32.PS_DOT</a></li>
<li><a href="#Gdi32_PS_INSIDEFRAME">Gdi32.PS_INSIDEFRAME</a></li>
<li><a href="#Gdi32_PS_NULL">Gdi32.PS_NULL</a></li>
<li><a href="#Gdi32_PS_SOLID">Gdi32.PS_SOLID</a></li>
<li><a href="#Gdi32_PS_STYLE_MASK">Gdi32.PS_STYLE_MASK</a></li>
<li><a href="#Gdi32_PS_USERSTYLE">Gdi32.PS_USERSTYLE</a></li>
<li><a href="#Gdi32_RASTERCAPS">Gdi32.RASTERCAPS</a></li>
<li><a href="#Gdi32_RASTER_FONTTYPE">Gdi32.RASTER_FONTTYPE</a></li>
<li><a href="#Gdi32_RUSSIAN_CHARSET">Gdi32.RUSSIAN_CHARSET</a></li>
<li><a href="#Gdi32_SCALINGFACTORX">Gdi32.SCALINGFACTORX</a></li>
<li><a href="#Gdi32_SCALINGFACTORY">Gdi32.SCALINGFACTORY</a></li>
<li><a href="#Gdi32_SHADEBLENDCAPS">Gdi32.SHADEBLENDCAPS</a></li>
<li><a href="#Gdi32_SHIFTJIS_CHARSET">Gdi32.SHIFTJIS_CHARSET</a></li>
<li><a href="#Gdi32_SIZEPALETTE">Gdi32.SIZEPALETTE</a></li>
<li><a href="#Gdi32_SRCAND">Gdi32.SRCAND</a></li>
<li><a href="#Gdi32_SRCCOPY">Gdi32.SRCCOPY</a></li>
<li><a href="#Gdi32_SRCERASE">Gdi32.SRCERASE</a></li>
<li><a href="#Gdi32_SRCINVERT">Gdi32.SRCINVERT</a></li>
<li><a href="#Gdi32_SRCPAINT">Gdi32.SRCPAINT</a></li>
<li><a href="#Gdi32_SYMBOL_CHARSET">Gdi32.SYMBOL_CHARSET</a></li>
<li><a href="#Gdi32_SYSTEM_FIXED_FONT">Gdi32.SYSTEM_FIXED_FONT</a></li>
<li><a href="#Gdi32_SYSTEM_FONT">Gdi32.SYSTEM_FONT</a></li>
<li><a href="#Gdi32_TECHNOLOGY">Gdi32.TECHNOLOGY</a></li>
<li><a href="#Gdi32_TEXTCAPS">Gdi32.TEXTCAPS</a></li>
<li><a href="#Gdi32_THAI_CHARSET">Gdi32.THAI_CHARSET</a></li>
<li><a href="#Gdi32_TRANSPARENT">Gdi32.TRANSPARENT</a></li>
<li><a href="#Gdi32_TRUETYPE_FONTTYPE">Gdi32.TRUETYPE_FONTTYPE</a></li>
<li><a href="#Gdi32_TURKISH_CHARSET">Gdi32.TURKISH_CHARSET</a></li>
<li><a href="#Gdi32_VERTRES">Gdi32.VERTRES</a></li>
<li><a href="#Gdi32_VERTSIZE">Gdi32.VERTSIZE</a></li>
<li><a href="#Gdi32_VIETNAMESE_CHARSET">Gdi32.VIETNAMESE_CHARSET</a></li>
<li><a href="#Gdi32_VREFRESH">Gdi32.VREFRESH</a></li>
<li><a href="#Gdi32_WHITENESS">Gdi32.WHITENESS</a></li>
<li><a href="#Gdi32_WHITE_BRUSH">Gdi32.WHITE_BRUSH</a></li>
<li><a href="#Gdi32_WHITE_PEN">Gdi32.WHITE_PEN</a></li>
<h3>Type Aliases</h3>
<li><a href="#Gdi32_FONTENUMPROCA">Gdi32.FONTENUMPROCA</a></li>
<li><a href="#Gdi32_FONTENUMPROCW">Gdi32.FONTENUMPROCW</a></li>
<li><a href="#Gdi32_HFONT">Gdi32.HFONT</a></li>
<li><a href="#Gdi32_HGDIOBJ">Gdi32.HGDIOBJ</a></li>
<li><a href="#Gdi32_HPEN">Gdi32.HPEN</a></li>
<h3>Functions</h3>
<li><a href="#Gdi32_BitBlt">Gdi32.BitBlt</a></li>
<li><a href="#Gdi32_ChoosePixelFormat">Gdi32.ChoosePixelFormat</a></li>
<li><a href="#Gdi32_CreateCompatibleBitmap">Gdi32.CreateCompatibleBitmap</a></li>
<li><a href="#Gdi32_CreateCompatibleDC">Gdi32.CreateCompatibleDC</a></li>
<li><a href="#Gdi32_CreateDIBSection">Gdi32.CreateDIBSection</a></li>
<li><a href="#Gdi32_CreateFontIndirectA">Gdi32.CreateFontIndirectA</a></li>
<li><a href="#Gdi32_CreateFontIndirectW">Gdi32.CreateFontIndirectW</a></li>
<li><a href="#Gdi32_CreatePen">Gdi32.CreatePen</a></li>
<li><a href="#Gdi32_CreateSolidBrush">Gdi32.CreateSolidBrush</a></li>
<li><a href="#Gdi32_DeleteDC">Gdi32.DeleteDC</a></li>
<li><a href="#Gdi32_DeleteObject">Gdi32.DeleteObject</a></li>
<li><a href="#Gdi32_DescribePixelFormat">Gdi32.DescribePixelFormat</a></li>
<li><a href="#Gdi32_EnumFontFamiliesA">Gdi32.EnumFontFamiliesA</a></li>
<li><a href="#Gdi32_EnumFontFamiliesExA">Gdi32.EnumFontFamiliesExA</a></li>
<li><a href="#Gdi32_EnumFontFamiliesExW">Gdi32.EnumFontFamiliesExW</a></li>
<li><a href="#Gdi32_EnumFontFamiliesW">Gdi32.EnumFontFamiliesW</a></li>
<li><a href="#Gdi32_GdiFlush">Gdi32.GdiFlush</a></li>
<li><a href="#Gdi32_GetBitmapBits">Gdi32.GetBitmapBits</a></li>
<li><a href="#Gdi32_GetDIBits">Gdi32.GetDIBits</a></li>
<li><a href="#Gdi32_GetDeviceCaps">Gdi32.GetDeviceCaps</a></li>
<li><a href="#Gdi32_GetFontData">Gdi32.GetFontData</a></li>
<li><a href="#Gdi32_GetObjectA">Gdi32.GetObjectA</a></li>
<li><a href="#Gdi32_GetObjectW">Gdi32.GetObjectW</a></li>
<li><a href="#Gdi32_GetPixel">Gdi32.GetPixel</a></li>
<li><a href="#Gdi32_GetStockObject">Gdi32.GetStockObject</a></li>
<li><a href="#Gdi32_LineTo">Gdi32.LineTo</a></li>
<li><a href="#Gdi32_MoveTo">Gdi32.MoveTo</a></li>
<li><a href="#Gdi32_RGB">Gdi32.RGB</a></li>
<li><a href="#Gdi32_Rectangle">Gdi32.Rectangle</a></li>
<li><a href="#Gdi32_SelectObject">Gdi32.SelectObject</a></li>
<li><a href="#Gdi32_SetBitmapBits">Gdi32.SetBitmapBits</a></li>
<li><a href="#Gdi32_SetBkColor">Gdi32.SetBkColor</a></li>
<li><a href="#Gdi32_SetBkMode">Gdi32.SetBkMode</a></li>
<li><a href="#Gdi32_SetPixelFormat">Gdi32.SetPixelFormat</a></li>
<li><a href="#Gdi32_SetTextColor">Gdi32.SetTextColor</a></li>
<li><a href="#Gdi32_SwapBuffers">Gdi32.SwapBuffers</a></li>
<li><a href="#Gdi32_TextOutA">Gdi32.TextOutA</a></li>
<li><a href="#Gdi32_TextOutW">Gdi32.TextOutW</a></li>
</div></div>
<div class="right"><div class="right-page">
<h1>Module gdi32</h1>
<h1>Content</h1>
<table class="api-item"><tr><td><span id="Gdi32_BITMAP"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.BITMAP</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L91">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">BITMAP</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">bmBits</td><td class="code-type">#null [*] void</td><td></td></tr>
<tr><td class="code-type">bmBitsPixel</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">bmHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">bmPlanes</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">bmType</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">bmWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">bmWidthBytes</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_BITMAPINFO"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.BITMAPINFO</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L135">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">BITMAPINFO</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">bmiColors</td><td class="code-type">[1] Gdi32.RGBQUAD</td><td></td></tr>
<tr><td class="code-type">bmiHeader</td><td class="code-type">Gdi32.BITMAPINFOHEADER</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_BITMAPINFOHEADER"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.BITMAPINFOHEADER</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L120">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">BITMAPINFOHEADER</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">biBitCount</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">biClrImportant</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">biClrUsed</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">biCompression</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">biHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">biPlanes</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">biSize</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">biSizeImage</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">biWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">biXPelsPerMeter</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">biYPelsPerMeter</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_ENUMLOGFONTEXA"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.ENUMLOGFONTEXA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L295">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">ENUMLOGFONTEXA</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">elfFullName</td><td class="code-type">[64] u8</td><td></td></tr>
<tr><td class="code-type">elfLogFont</td><td class="code-type">Gdi32.LOGFONTA</td><td></td></tr>
<tr><td class="code-type">elfScript</td><td class="code-type">[32] u8</td><td></td></tr>
<tr><td class="code-type">elfStyle</td><td class="code-type">[32] u8</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_ENUMLOGFONTEXW"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.ENUMLOGFONTEXW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L303">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">ENUMLOGFONTEXW</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">elfFullName</td><td class="code-type">[64] u16</td><td></td></tr>
<tr><td class="code-type">elfLogFont</td><td class="code-type">Gdi32.LOGFONTW</td><td></td></tr>
<tr><td class="code-type">elfScript</td><td class="code-type">[32] u16</td><td></td></tr>
<tr><td class="code-type">elfStyle</td><td class="code-type">[32] u16</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_LOGFONTA"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.LOGFONTA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L257">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">LOGFONTA</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">lfCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfClipPrecision</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfEscapement</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfFaceName</td><td class="code-type">[32] u8</td><td></td></tr>
<tr><td class="code-type">lfHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfOrientation</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfOutPrecision</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfQuality</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfStrikeOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfUnderline</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfWeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfWidth</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_LOGFONTW"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.LOGFONTW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L275">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">LOGFONTW</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">lfCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfClipPrecision</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfEscapement</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfFaceName</td><td class="code-type">[32] u16</td><td></td></tr>
<tr><td class="code-type">lfHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfOrientation</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfOutPrecision</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfQuality</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfStrikeOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfUnderline</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">lfWeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">lfWidth</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_NEWTEXTMETRICA"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.NEWTEXTMETRICA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L359">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">NEWTEXTMETRICA</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">ntmAvgWidth</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmCellHeight</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmFlags</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmSizeEM</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">tmAscent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmAveCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmBreakChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDefaultChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDescent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectX</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectY</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmExternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmFirstChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmInternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmLastChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmMaxCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmOverhang</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmStruckOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmUnderlined</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmWeight</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_NEWTEXTMETRICW"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.NEWTEXTMETRICW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L387">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">NEWTEXTMETRICW</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">ntmAvgWidth</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmCellHeight</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmFlags</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">ntmSizeEM</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">tmAscent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmAveCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmBreakChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDefaultChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmDescent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectX</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectY</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmExternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmFirstChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmInternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmLastChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmMaxCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmOverhang</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmStruckOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmUnderlined</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmWeight</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_PIXELFORMATDESCRIPTOR"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.PIXELFORMATDESCRIPTOR</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L17">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">PIXELFORMATDESCRIPTOR</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">bReserved</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAccumAlphaBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAccumBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAccumBlueBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAccumGreenBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAccumRedBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAlphaBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAlphaShift</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cAuxBuffers</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cBlueBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cBlueShift</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cColorBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cDepthBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cGreenBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cGreenShift</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cRedBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cRedShift</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">cStencilBits</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">dwDamageMask</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">dwFlags</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">dwLayerMask</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">dwVisibleMask</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">iLayerType</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">iPixelType</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">nSize</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">nVersion</td><td class="code-type">u16</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_RGBQUAD"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.RGBQUAD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L102">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">RGBQUAD</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">rgbBlue</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">rgbGreen</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">rgbRed</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">rgbReserved</td><td class="code-type">u8</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_TEXTMETRICA"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.TEXTMETRICA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L311">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">TEXTMETRICA</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">tmAscent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmAveCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmBreakChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDefaultChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDescent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectX</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectY</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmExternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmFirstChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmInternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmLastChar</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmMaxCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmOverhang</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmStruckOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmUnderlined</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmWeight</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_TEXTMETRICW"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdi32.TEXTMETRICW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L335">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">TEXTMETRICW</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">tmAscent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmAveCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmBreakChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmCharSet</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmDefaultChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmDescent</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectX</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmDigitizedAspectY</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmExternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmFirstChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmHeight</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmInternalLeading</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmItalic</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmLastChar</td><td class="code-type">u16</td><td></td></tr>
<tr><td class="code-type">tmMaxCharWidth</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmOverhang</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">tmPitchAndFamily</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmStruckOut</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmUnderlined</td><td class="code-type">u8</td><td></td></tr>
<tr><td class="code-type">tmWeight</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdi32_ANSI_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ANSI_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L180">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ANSI_CHARSET</span>        = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ANSI_FIXED_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ANSI_FIXED_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L173">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ANSI_FIXED_FONT</span>     = <span class="SNum">11</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ANSI_VAR_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ANSI_VAR_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L174">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ANSI_VAR_FONT</span>       = <span class="SNum">12</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ARABIC_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ARABIC_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L191">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ARABIC_CHARSET</span>      = <span class="SNum">178</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ASPECTX"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ASPECTX</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L236">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ASPECTX</span>         = <span class="SNum">40</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ASPECTXY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ASPECTXY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L238">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ASPECTXY</span>        = <span class="SNum">44</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ASPECTY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.ASPECTY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L237">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">ASPECTY</span>         = <span class="SNum">42</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BALTIC_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BALTIC_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L199">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BALTIC_CHARSET</span>      = <span class="SNum">186</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BITSPIXEL"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BITSPIXEL</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L222">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BITSPIXEL</span>       = <span class="SNum">12</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_BITFIELDS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_BITFIELDS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L113">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_BITFIELDS</span> = <span class="SNum">3</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_JPEG"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_JPEG</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L114">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_JPEG</span>      = <span class="SNum">4</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_PNG"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_PNG</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L115">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_PNG</span>       = <span class="SNum">5</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_RGB"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_RGB</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L110">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_RGB</span>       = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_RLE4"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_RLE4</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L112">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_RLE4</span>      = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BI_RLE8"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BI_RLE8</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L111">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BI_RLE8</span>      = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BKMODE_LAST"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BKMODE_LAST</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L214">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BKMODE_LAST</span> = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BLACKNESS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BLACKNESS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L86">[src]</a></td></tr></table>
<p>dest = BLACK</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BLACKNESS</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00000042</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BLACK_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BLACK_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L166">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BLACK_BRUSH</span>         = <span class="SNum">4</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BLACK_PEN"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BLACK_PEN</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L170">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BLACK_PEN</span>           = <span class="SNum">7</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BLTALIGNMENT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.BLTALIGNMENT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L253">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">BLTALIGNMENT</span>    = <span class="SNum">119</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CAPTUREBLT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.CAPTUREBLT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L89">[src]</a></td></tr></table>
<p>Include layered windows</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">CAPTUREBLT</span>     = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x40000000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CHINESEBIG5_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.CHINESEBIG5_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L187">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">CHINESEBIG5_CHARSET</span> = <span class="SNum">136</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CLIPCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.CLIPCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L234">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">CLIPCAPS</span>        = <span class="SNum">36</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_COLORMGMTCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.COLORMGMTCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L255">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">COLORMGMTCAPS</span>   = <span class="SNum">121</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_COLORRES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.COLORRES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L243">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">COLORRES</span>        = <span class="SNum">108</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CURVECAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.CURVECAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L230">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">CURVECAPS</span>       = <span class="SNum">28</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DEFAULT_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DEFAULT_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L181">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DEFAULT_CHARSET</span>     = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DEFAULT_PALETTE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DEFAULT_PALETTE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L177">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DEFAULT_PALETTE</span>     = <span class="SNum">15</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DESKTOPHORZRES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DESKTOPHORZRES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L252">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DESKTOPHORZRES</span>  = <span class="SNum">118</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DESKTOPVERTRES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DESKTOPVERTRES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L251">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DESKTOPVERTRES</span>  = <span class="SNum">117</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DEVICE_DEFAULT_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DEVICE_DEFAULT_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L176">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DEVICE_DEFAULT_FONT</span> = <span class="SNum">14</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DEVICE_FONTTYPE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DEVICE_FONTTYPE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L143">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DEVICE_FONTTYPE</span>   = <span class="SNum">0x0002</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DIB_PAL_COLORS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DIB_PAL_COLORS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L118">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DIB_PAL_COLORS</span> = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DIB_RGB_COLORS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DIB_RGB_COLORS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L117">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DIB_RGB_COLORS</span> = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DKGRAY_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DKGRAY_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L165">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DKGRAY_BRUSH</span>        = <span class="SNum">3</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DRIVERVERSION"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DRIVERVERSION</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L216">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DRIVERVERSION</span>   = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DSTINVERT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.DSTINVERT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L85">[src]</a></td></tr></table>
<p>dest = (NOT dest)</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DSTINVERT</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00550009</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_EASTEUROPE_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.EASTEUROPE_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L196">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">EASTEUROPE_CHARSET</span>  = <span class="SNum">238</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_BLACK"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_BLACK</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L160">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_BLACK</span>      = <span class="SCst">FW_HEAVY</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_BOLD"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_BOLD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L153">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_BOLD</span>       = <span class="SNum">700</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_DEMIBOLD"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_DEMIBOLD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L158">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_DEMIBOLD</span>   = <span class="SCst">FW_SEMIBOLD</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_DONTCARE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_DONTCARE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L146">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_DONTCARE</span>   = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_EXTRABOLD"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_EXTRABOLD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L154">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_EXTRABOLD</span>  = <span class="SNum">800</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_EXTRALIGHT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_EXTRALIGHT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L148">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_EXTRALIGHT</span> = <span class="SNum">200</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_HEAVY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_HEAVY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L155">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_HEAVY</span>      = <span class="SNum">900</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_LIGHT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_LIGHT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L149">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_LIGHT</span>      = <span class="SNum">300</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_MEDIUM"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_MEDIUM</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L151">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_MEDIUM</span>     = <span class="SNum">500</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_NORMAL"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_NORMAL</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L150">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_NORMAL</span>     = <span class="SNum">400</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_REGULAR"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_REGULAR</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L157">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_REGULAR</span>    = <span class="SCst">FW_NORMAL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_SEMIBOLD"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_SEMIBOLD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L152">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_SEMIBOLD</span>   = <span class="SNum">600</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_THIN"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_THIN</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L147">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_THIN</span>       = <span class="SNum">100</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_ULTRABOLD"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_ULTRABOLD</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L159">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_ULTRABOLD</span>  = <span class="SCst">FW_EXTRABOLD</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FW_ULTRALIGHT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.FW_ULTRALIGHT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L156">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">FW_ULTRALIGHT</span> = <span class="SCst">FW_EXTRALIGHT</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GB2312_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.GB2312_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L186">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GB2312_CHARSET</span>      = <span class="SNum">134</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GDI_ERROR"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.GDI_ERROR</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L15">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GDI_ERROR</span> = <span class="SNum">0xFFFFFFFF</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GRAY_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.GRAY_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L164">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GRAY_BRUSH</span>          = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GREEK_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.GREEK_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L192">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GREEK_CHARSET</span>       = <span class="SNum">161</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HANGEUL_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HANGEUL_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L184">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HANGEUL_CHARSET</span>     = <span class="SNum">129</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HANGUL_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HANGUL_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L185">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HANGUL_CHARSET</span>      = <span class="SNum">129</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HEBREW_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HEBREW_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L190">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HEBREW_CHARSET</span>      = <span class="SNum">177</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HOLLOW_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HOLLOW_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L168">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HOLLOW_BRUSH</span>        = <span class="SCst">NULL_BRUSH</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HORZRES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HORZRES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L220">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HORZRES</span>         = <span class="SNum">8</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HORZSIZE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.HORZSIZE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L218">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">HORZSIZE</span>        = <span class="SNum">4</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_JOHAB_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.JOHAB_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L189">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">JOHAB_CHARSET</span>       = <span class="SNum">130</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LF_FACESIZE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LF_FACESIZE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L141">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LF_FACESIZE</span>       = <span class="SNum">32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LF_FULLFACESIZE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LF_FULLFACESIZE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L293">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LF_FULLFACESIZE</span> = <span class="SNum">64</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LINECAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LINECAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L231">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LINECAPS</span>        = <span class="SNum">30</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LOGPIXELSX"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LOGPIXELSX</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L239">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LOGPIXELSX</span>      = <span class="SNum">88</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LOGPIXELSY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LOGPIXELSY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L240">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LOGPIXELSY</span>      = <span class="SNum">90</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LTGRAY_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.LTGRAY_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L163">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">LTGRAY_BRUSH</span>        = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_MAC_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.MAC_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L198">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">MAC_CHARSET</span>         = <span class="SNum">77</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_MERGECOPY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.MERGECOPY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L80">[src]</a></td></tr></table>
<p>dest = (source AND pattern)</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">MERGECOPY</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00C000CA</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_MERGEPAINT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.MERGEPAINT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L81">[src]</a></td></tr></table>
<p>dest = (NOT source) OR dest</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">MERGEPAINT</span>     = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00BB0226</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NOMIRRORBITMAP"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NOMIRRORBITMAP</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L88">[src]</a></td></tr></table>
<p>Do not Mirror the bitmap in this call</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NOMIRRORBITMAP</span> = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x80000000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NOTSRCCOPY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NOTSRCCOPY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L78">[src]</a></td></tr></table>
<p>dest = (NOT source)</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NOTSRCCOPY</span>     = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00330008</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NOTSRCERASE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NOTSRCERASE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L79">[src]</a></td></tr></table>
<p>dest = (NOT src) AND (NOT dest)</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NOTSRCERASE</span>    = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x001100A6</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NULL_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NULL_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L167">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NULL_BRUSH</span>          = <span class="SNum">5</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NULL_PEN"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NULL_PEN</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L171">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NULL_PEN</span>            = <span class="SNum">8</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMBRUSHES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMBRUSHES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L224">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMBRUSHES</span>      = <span class="SNum">16</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMCOLORS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMCOLORS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L228">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMCOLORS</span>       = <span class="SNum">24</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMFONTS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMFONTS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L227">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMFONTS</span>        = <span class="SNum">22</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMMARKERS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMMARKERS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L226">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMMARKERS</span>      = <span class="SNum">20</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMPENS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMPENS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L225">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMPENS</span>         = <span class="SNum">18</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_NUMRESERVED"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.NUMRESERVED</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L242">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NUMRESERVED</span>     = <span class="SNum">106</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_OEM_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.OEM_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L188">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">OEM_CHARSET</span>         = <span class="SNum">255</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_OEM_FIXED_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.OEM_FIXED_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L172">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">OEM_FIXED_FONT</span>      = <span class="SNum">10</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_OPAQUE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.OPAQUE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L213">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">OPAQUE</span>      = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PATCOPY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PATCOPY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L82">[src]</a></td></tr></table>
<p>dest = pattern</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PATCOPY</span>        = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00F00021</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PATINVERT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PATINVERT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L84">[src]</a></td></tr></table>
<p>dest = pattern XOR dest</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PATINVERT</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x005A0049</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PATPAINT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PATPAINT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L83">[src]</a></td></tr></table>
<p>dest = DPSnoo</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PATPAINT</span>       = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00FB0A09</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PDEVICESIZE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PDEVICESIZE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L229">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PDEVICESIZE</span>     = <span class="SNum">26</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DEPTH_DONTCARE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DEPTH_DONTCARE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L69">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DEPTH_DONTCARE</span>        = <span class="SNum">0x20000000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DIRECT3D_ACCELERATED"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DIRECT3D_ACCELERATED</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L67">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DIRECT3D_ACCELERATED</span>  = <span class="SNum">0x00004000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DOUBLEBUFFER"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DOUBLEBUFFER</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L53">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DOUBLEBUFFER</span>          = <span class="SNum">0x00000001</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DOUBLEBUFFER_DONTCARE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DOUBLEBUFFER_DONTCARE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L70">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DOUBLEBUFFER_DONTCARE</span> = <span class="SNum">0x40000000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DRAW_TO_BITMAP"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DRAW_TO_BITMAP</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L56">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DRAW_TO_BITMAP</span>        = <span class="SNum">0x00000008</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_DRAW_TO_WINDOW"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_DRAW_TO_WINDOW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L55">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_DRAW_TO_WINDOW</span>        = <span class="SNum">0x00000004</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_GENERIC_ACCELERATED"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_GENERIC_ACCELERATED</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L65">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_GENERIC_ACCELERATED</span>   = <span class="SNum">0x00001000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_GENERIC_FORMAT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_GENERIC_FORMAT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L59">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_GENERIC_FORMAT</span>        = <span class="SNum">0x00000040</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_MAIN_PLANE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_MAIN_PLANE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L49">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_MAIN_PLANE</span>      = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_NEED_PALETTE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_NEED_PALETTE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L60">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_NEED_PALETTE</span>          = <span class="SNum">0x00000080</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_NEED_SYSTEM_PALETTE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_NEED_SYSTEM_PALETTE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L61">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_NEED_SYSTEM_PALETTE</span>   = <span class="SNum">0x00000100</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_OVERLAY_PLANE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_OVERLAY_PLANE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L50">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_OVERLAY_PLANE</span>   = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_STEREO"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_STEREO</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L54">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_STEREO</span>                = <span class="SNum">0x00000002</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_STEREO_DONTCARE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_STEREO_DONTCARE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L71">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_STEREO_DONTCARE</span>       = <span class="SNum">0x80000000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SUPPORT_COMPOSITION"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SUPPORT_COMPOSITION</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L68">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SUPPORT_COMPOSITION</span>   = <span class="SNum">0x00008000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SUPPORT_DIRECTDRAW"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SUPPORT_DIRECTDRAW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L66">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SUPPORT_DIRECTDRAW</span>    = <span class="SNum">0x00002000</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SUPPORT_GDI"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SUPPORT_GDI</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L57">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SUPPORT_GDI</span>           = <span class="SNum">0x00000010</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SUPPORT_OPENGL"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SUPPORT_OPENGL</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L58">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SUPPORT_OPENGL</span>        = <span class="SNum">0x00000020</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SWAP_COPY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SWAP_COPY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L63">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SWAP_COPY</span>             = <span class="SNum">0x00000400</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SWAP_EXCHANGE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SWAP_EXCHANGE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L62">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SWAP_EXCHANGE</span>         = <span class="SNum">0x00000200</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_SWAP_LAYER_BUFFERS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_SWAP_LAYER_BUFFERS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L64">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_SWAP_LAYER_BUFFERS</span>    = <span class="SNum">0x00000800</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_TYPE_COLORINDEX"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_TYPE_COLORINDEX</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L48">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_TYPE_COLORINDEX</span> = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_TYPE_RGBA"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_TYPE_RGBA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L47">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_TYPE_RGBA</span>       = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PFD_UNDERLAY_PLANE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PFD_UNDERLAY_PLANE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L51">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PFD_UNDERLAY_PLANE</span>  = -<span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PHYSICALHEIGHT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PHYSICALHEIGHT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L245">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PHYSICALHEIGHT</span>  = <span class="SNum">111</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PHYSICALOFFSETX"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PHYSICALOFFSETX</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L246">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PHYSICALOFFSETX</span> = <span class="SNum">112</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PHYSICALOFFSETY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PHYSICALOFFSETY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L247">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PHYSICALOFFSETY</span> = <span class="SNum">113</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PHYSICALWIDTH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PHYSICALWIDTH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L244">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PHYSICALWIDTH</span>   = <span class="SNum">110</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PLANES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PLANES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L223">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PLANES</span>          = <span class="SNum">14</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_POLYGONALCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.POLYGONALCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L232">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">POLYGONALCAPS</span>   = <span class="SNum">32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_ALTERNATE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_ALTERNATE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L209">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_ALTERNATE</span>   = <span class="SNum">8</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_DASH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_DASH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L202">[src]</a></td></tr></table>
<p>-------</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_DASH</span>        = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_DASHDOT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_DASHDOT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L204">[src]</a></td></tr></table>
<p>_._._._</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_DASHDOT</span>     = <span class="SNum">3</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_DASHDOTDOT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_DASHDOTDOT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L205">[src]</a></td></tr></table>
<p>_.._.._</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_DASHDOTDOT</span>  = <span class="SNum">4</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_DOT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_DOT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L203">[src]</a></td></tr></table>
<p>.......</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_DOT</span>         = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_INSIDEFRAME"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_INSIDEFRAME</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L207">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_INSIDEFRAME</span> = <span class="SNum">6</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_NULL"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_NULL</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L206">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_NULL</span>        = <span class="SNum">5</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_SOLID"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_SOLID</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L201">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_SOLID</span>       = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_STYLE_MASK"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_STYLE_MASK</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L210">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_STYLE_MASK</span>  = <span class="SNum">0x0000000F</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_PS_USERSTYLE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.PS_USERSTYLE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L208">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">PS_USERSTYLE</span>   = <span class="SNum">7</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_RASTERCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.RASTERCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L235">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">RASTERCAPS</span>      = <span class="SNum">38</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_RASTER_FONTTYPE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.RASTER_FONTTYPE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L142">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">RASTER_FONTTYPE</span>   = <span class="SNum">0x0001</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_RUSSIAN_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.RUSSIAN_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L197">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">RUSSIAN_CHARSET</span>     = <span class="SNum">204</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SCALINGFACTORX"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SCALINGFACTORX</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L248">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SCALINGFACTORX</span>  = <span class="SNum">114</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SCALINGFACTORY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SCALINGFACTORY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L249">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SCALINGFACTORY</span>  = <span class="SNum">115</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SHADEBLENDCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SHADEBLENDCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L254">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SHADEBLENDCAPS</span>  = <span class="SNum">120</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SHIFTJIS_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SHIFTJIS_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L183">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SHIFTJIS_CHARSET</span>    = <span class="SNum">128</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SIZEPALETTE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SIZEPALETTE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L241">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SIZEPALETTE</span>     = <span class="SNum">104</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SRCAND"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SRCAND</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L75">[src]</a></td></tr></table>
<p>dest = source AND dest</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SRCAND</span>         = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x008800C6</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SRCCOPY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SRCCOPY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L73">[src]</a></td></tr></table>
<p>dest = source</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SRCCOPY</span>        = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00CC0020</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SRCERASE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SRCERASE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L77">[src]</a></td></tr></table>
<p>dest = source AND (NOT dest )</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SRCERASE</span>       = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00440328</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SRCINVERT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SRCINVERT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L76">[src]</a></td></tr></table>
<p>dest = source XOR dest</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SRCINVERT</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00660046</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SRCPAINT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SRCPAINT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L74">[src]</a></td></tr></table>
<p>dest = source OR dest</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SRCPAINT</span>       = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00EE0086</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SYMBOL_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SYMBOL_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L182">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SYMBOL_CHARSET</span>      = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SYSTEM_FIXED_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SYSTEM_FIXED_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L178">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SYSTEM_FIXED_FONT</span>   = <span class="SNum">16</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SYSTEM_FONT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.SYSTEM_FONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L175">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">SYSTEM_FONT</span>         = <span class="SNum">13</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TECHNOLOGY"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.TECHNOLOGY</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L217">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">TECHNOLOGY</span>      = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TEXTCAPS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.TEXTCAPS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L233">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">TEXTCAPS</span>        = <span class="SNum">34</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_THAI_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.THAI_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L195">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">THAI_CHARSET</span>        = <span class="SNum">222</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TRANSPARENT"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.TRANSPARENT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L212">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">TRANSPARENT</span> = <span class="SNum">1</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TRUETYPE_FONTTYPE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.TRUETYPE_FONTTYPE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L144">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">TRUETYPE_FONTTYPE</span> = <span class="SNum">0x0004</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TURKISH_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.TURKISH_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L193">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">TURKISH_CHARSET</span>     = <span class="SNum">162</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_VERTRES"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.VERTRES</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L221">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">VERTRES</span>         = <span class="SNum">10</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_VERTSIZE"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.VERTSIZE</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L219">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">VERTSIZE</span>        = <span class="SNum">6</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_VIETNAMESE_CHARSET"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.VIETNAMESE_CHARSET</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L194">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">VIETNAMESE_CHARSET</span>  = <span class="SNum">163</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_VREFRESH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.VREFRESH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L250">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">VREFRESH</span>        = <span class="SNum">116</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_WHITENESS"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.WHITENESS</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L87">[src]</a></td></tr></table>
<p>dest = WHITE</p>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">WHITENESS</span>      = <span class="SKwd">cast</span>(<span class="SCst">DWORD</span>) <span class="SNum">0x00FF0062</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_WHITE_BRUSH"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.WHITE_BRUSH</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L162">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">WHITE_BRUSH</span>         = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_WHITE_PEN"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdi32.WHITE_PEN</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L169">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">WHITE_PEN</span>           = <span class="SNum">6</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FONTENUMPROCA"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdi32.FONTENUMPROCA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L415">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">FONTENUMPROCA</span> = <span class="SKwd">func</span>(<span class="SKwd">const</span> *<span class="SCst">LOGFONTA</span>, <span class="SKwd">const</span> *<span class="SCst">TEXTMETRICA</span>, <span class="SCst">DWORD</span>, <span class="SCst">LPARAM</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_FONTENUMPROCW"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdi32.FONTENUMPROCW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L416">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">FONTENUMPROCW</span> = <span class="SKwd">func</span>(<span class="SKwd">const</span> *<span class="SCst">LOGFONTW</span>, <span class="SKwd">const</span> *<span class="SCst">TEXTMETRICW</span>, <span class="SCst">DWORD</span>, <span class="SCst">LPARAM</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HFONT"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdi32.HFONT</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L11">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">HFONT</span>   = <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HGDIOBJ"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdi32.HGDIOBJ</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L10">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">HGDIOBJ</span> = <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_HPEN"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdi32.HPEN</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L12">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">HPEN</span>    = <span class="SItr">#null</span> <span class="SKwd">const</span> *<span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_BitBlt"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.BitBlt</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L542">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">BitBlt</span>(hdc: <span class="SCst">HDC</span>, x, y, cx, cy: <span class="STpe">s32</span>, hdcSrc: <span class="SCst">HDC</span>, x1, y1: <span class="STpe">s32</span>, rop: <span class="SCst">DWORD</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_ChoosePixelFormat"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.ChoosePixelFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L483">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">ChoosePixelFormat</span>(hdc: <span class="SCst">HDC</span>, ppfd: <span class="SKwd">const</span> *<span class="SCst">PIXELFORMATDESCRIPTOR</span>)-&gt;<span class="STpe">s32</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateCompatibleBitmap"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateCompatibleBitmap</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L520">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateCompatibleBitmap</span>(hdc: <span class="SCst">HDC</span>, cx, cy: <span class="STpe">s32</span>)-&gt;<span class="SCst">HBITMAP</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateCompatibleDC"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateCompatibleDC</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L512">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateCompatibleDC</span>(hdc: <span class="SCst">HDC</span>)-&gt;<span class="SCst">HDC</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateDIBSection"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateDIBSection</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L626">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateDIBSection</span>(hdc: <span class="SCst">HDC</span>, pbmi: <span class="SKwd">const</span> *<span class="SCst">BITMAPINFO</span>, usage: <span class="SCst">UINT</span>, ppvBits: *<span class="SItr">#null</span> *<span class="STpe">void</span>, hSection: <span class="SCst">HANDLE</span>, offset: <span class="SCst">DWORD</span>)-&gt;<span class="SCst">HBITMAP</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateFontIndirectA"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateFontIndirectA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L585">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateFontIndirectA</span>(lplf: <span class="SKwd">const</span> *<span class="SCst">LOGFONTA</span>)-&gt;<span class="SCst">HFONT</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateFontIndirectW"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateFontIndirectW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L593">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateFontIndirectW</span>(lplf: <span class="SKwd">const</span> *<span class="SCst">LOGFONTW</span>)-&gt;<span class="SCst">HFONT</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreatePen"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreatePen</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L609">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreatePen</span>(iStyle: <span class="STpe">s32</span>, cWidth: <span class="STpe">s32</span>, color: <span class="SCst">COLORREF</span>)-&gt;<span class="SCst">HPEN</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_CreateSolidBrush"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.CreateSolidBrush</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L601">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">CreateSolidBrush</span>(color: <span class="SCst">COLORREF</span>)-&gt;<span class="SCst">HBRUSH</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DeleteDC"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.DeleteDC</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L528">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">DeleteDC</span>(hdc: <span class="SCst">HDC</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DeleteObject"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.DeleteObject</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L535">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">DeleteObject</span>(ho: <span class="SCst">HGDIOBJ</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_DescribePixelFormat"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.DescribePixelFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L504">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Discardable]</span>
<span class="SKwd">func</span> <span class="SFct">DescribePixelFormat</span>(hdc: <span class="SCst">HDC</span>, iPixelFormat: <span class="STpe">s32</span>, nBytes: <span class="SCst">UINT</span>, ppfd: *<span class="SCst">PIXELFORMATDESCRIPTOR</span>)-&gt;<span class="STpe">s32</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_EnumFontFamiliesA"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.EnumFontFamiliesA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L438">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">EnumFontFamiliesA</span>(hdc: <span class="SCst">HDC</span>, lpLogfont: <span class="SCst">LPCSTR</span>, lpProc: <span class="SCst">FONTENUMPROCA</span>, lParam: <span class="SCst">LPARAM</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_EnumFontFamiliesExA"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.EnumFontFamiliesExA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L440">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">EnumFontFamiliesExA</span>(hdc: <span class="SCst">HDC</span>, lpLogfont: <span class="SKwd">const</span> *<span class="SCst">LOGFONTA</span>, lpProc: <span class="SCst">FONTENUMPROCA</span>, lParam: <span class="SCst">LPARAM</span>, dwFlags: <span class="SCst">DWORD</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_EnumFontFamiliesExW"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.EnumFontFamiliesExW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L441">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">EnumFontFamiliesExW</span>(hdc: <span class="SCst">HDC</span>, lpLogfont: <span class="SKwd">const</span> *<span class="SCst">LOGFONTW</span>, lpProc: <span class="SCst">FONTENUMPROCW</span>, lParam: <span class="SCst">LPARAM</span>, dwFlags: <span class="SCst">DWORD</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_EnumFontFamiliesW"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.EnumFontFamiliesW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L439">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">EnumFontFamiliesW</span>(hdc: <span class="SCst">HDC</span>, lpLogfont: <span class="SCst">LPCWSTR</span>, lpProc: <span class="SCst">FONTENUMPROCW</span>, lParam: <span class="SCst">LPARAM</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GdiFlush"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GdiFlush</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L436">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdiFlush</span>()-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetBitmapBits"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetBitmapBits</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L563">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetBitmapBits</span>(hbit: <span class="SCst">HBITMAP</span>, cb: <span class="SCst">LONG</span>, lpvBits: <span class="SCst">LPVOID</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetDIBits"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetDIBits</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L618">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Discardable]</span>
<span class="SKwd">func</span> <span class="SFct">GetDIBits</span>(hdc: <span class="SCst">HDC</span>, hbm: <span class="SCst">HBITMAP</span>, start: <span class="SCst">UINT</span>, cLines: <span class="SCst">UINT</span>, lpvBits: <span class="SCst">LPVOID</span>, lpbmi: *<span class="SCst">BITMAPINFO</span>, usage: <span class="SCst">UINT</span>)-&gt;<span class="STpe">s32</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetDeviceCaps"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetDeviceCaps</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L435">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetDeviceCaps</span>(hdc: <span class="SCst">HDC</span>, index: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetFontData"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetFontData</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L577">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetFontData</span>(hdc: <span class="SCst">HDC</span>, dwTable: <span class="SCst">DWORD</span>, dwOffset: <span class="SCst">DWORD</span>, pvBuffer: <span class="SCst">LPVOID</span>, cjBuffer: <span class="SCst">DWORD</span>)-&gt;<span class="SCst">DWORD</span> <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetObjectA"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetObjectA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L432">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetObjectA</span>(h: <span class="SCst">HANDLE</span>, c: <span class="STpe">s32</span>, pv: <span class="SCst">LPVOID</span>)-&gt;<span class="STpe">s32</span></span></div>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetObjectA</span>(h: <span class="SCst">HANDLE</span>, c: <span class="STpe">s32</span>, pv: <span class="SCst">LPVOID</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetObjectW"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetObjectW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L433">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetObjectW</span>(h: <span class="SCst">HANDLE</span>, c: <span class="STpe">s32</span>, pv: <span class="SCst">LPVOID</span>)-&gt;<span class="STpe">s32</span></span></div>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetObjectW</span>(h: <span class="SCst">HANDLE</span>, c: <span class="STpe">s32</span>, pv: <span class="SCst">LPVOID</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetPixel"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetPixel</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L426">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetPixel</span>(hdc: <span class="SCst">HDC</span>, x, y: <span class="STpe">s32</span>)-&gt;<span class="SCst">COLORREF</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_GetStockObject"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.GetStockObject</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L427">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GetStockObject</span>(i: <span class="STpe">s32</span>)-&gt;<span class="SCst">HGDIOBJ</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_LineTo"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.LineTo</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L450">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">LineTo</span>(hdc: <span class="SCst">HDC</span>, x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_MoveTo"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.MoveTo</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L449">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">MoveTo</span>(hdc: <span class="SCst">HDC</span>, x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_RGB"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.RGB</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L419">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Inline]</span>
<span class="SKwd">func</span> <span class="SFct">RGB</span>(r, g, b: <span class="STpe">s32</span>)-&gt;<span class="SCst">COLORREF</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_Rectangle"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.Rectangle</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L451">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">Rectangle</span>(hdc: <span class="SCst">HDC</span>, left, top, right, bottom: <span class="STpe">s32</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SelectObject"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SelectObject</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L434">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SelectObject</span>(hdc: <span class="SCst">HDC</span>, h: <span class="SCst">HGDIOBJ</span>)-&gt;<span class="SCst">HGDIOBJ</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SetBitmapBits"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SetBitmapBits</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L570">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SetBitmapBits</span>(hbit: <span class="SCst">HBITMAP</span>, cb: <span class="SCst">DWORD</span>, lpvBits: <span class="SCst">LPVOID</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SetBkColor"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SetBkColor</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L444">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SetBkColor</span>(hdc: <span class="SCst">HDC</span>, color: <span class="SCst">COLORREF</span>)-&gt;<span class="SCst">COLORREF</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SetBkMode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SetBkMode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L443">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SetBkMode</span>(hdc: <span class="SCst">HDC</span>, mode: <span class="STpe">s32</span>)-&gt;<span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SetPixelFormat"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SetPixelFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L491">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SetPixelFormat</span>(hdc: <span class="SCst">HDC</span>, fmt: <span class="STpe">s32</span>, ppfd: <span class="SKwd">const</span> *<span class="SCst">PIXELFORMATDESCRIPTOR</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SetTextColor"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SetTextColor</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L445">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SetTextColor</span>(hdc: <span class="SCst">HDC</span>, color: <span class="SCst">COLORREF</span>)-&gt;<span class="SCst">COLORREF</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_SwapBuffers"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.SwapBuffers</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L497">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">SwapBuffers</span>(arg1: <span class="SCst">HDC</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TextOutA"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.TextOutA</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L447">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">TextOutA</span>(hdc: <span class="SCst">HDC</span>, x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span>, lpString: <span class="SCst">LPCSTR</span>, c: <span class="STpe">s32</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<table class="api-item"><tr><td><span id="Gdi32_TextOutW"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdi32.TextOutW</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdi32/src/gdi32.swg#L448">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">TextOutW</span>(hdc: <span class="SCst">HDC</span>, x: <span class="STpe">s32</span>, y: <span class="STpe">s32</span>, lpString: <span class="SCst">LPCWSTR</span>, c: <span class="STpe">s32</span>)-&gt;<span class="SCst">BOOL</span></span></div>
<div class="swag-watermark">Generated with <a href="https://swag-lang.org/index.php">swc</a> 0.1.1</div>
</div></div>
</div>
<script>
function getOffsetTop(element,parent){let offsetTop=0;while(element&&element!=parent){offsetTop+=element.offsetTop;element=element.offsetParent}return offsetTop}
document.addEventListener("DOMContentLoaded",function(){let hash=window.location.hash;if(!hash)return;let parent=document.querySelector(".right");let target=parent?parent.querySelector(hash):null;if(target)parent.scrollTop=getOffsetTop(target,parent)});
</script>
</body>
</html>
