<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php include('common/start-head.php'); ?><title>Module gdiplus</title>
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
<li><a href="#Gdiplus_GdiplusStartupInput">Gdiplus.GdiplusStartupInput</a></li>
<li><a href="#Gdiplus_GpRectF">Gdiplus.GpRectF</a></li>
<h3>Constants</h3>
<li><a href="#Gdiplus_GdipFillModeAlternate">Gdiplus.GdipFillModeAlternate</a></li>
<li><a href="#Gdiplus_GdipFontStyleRegular">Gdiplus.GdipFontStyleRegular</a></li>
<li><a href="#Gdiplus_GdipLineJoinRound">Gdiplus.GdipLineJoinRound</a></li>
<li><a href="#Gdiplus_GdipOk">Gdiplus.GdipOk</a></li>
<li><a href="#Gdiplus_GdipPixelFormat32bppPARGB">Gdiplus.GdipPixelFormat32bppPARGB</a></li>
<li><a href="#Gdiplus_GdipPixelOffsetModeHighQuality">Gdiplus.GdipPixelOffsetModeHighQuality</a></li>
<li><a href="#Gdiplus_GdipSmoothingModeHighQuality">Gdiplus.GdipSmoothingModeHighQuality</a></li>
<li><a href="#Gdiplus_GdipTextRenderingHintAAGridFit">Gdiplus.GdipTextRenderingHintAAGridFit</a></li>
<li><a href="#Gdiplus_GdipUnitPixel">Gdiplus.GdipUnitPixel</a></li>
<h3>Type Aliases</h3>
<li><a href="#Gdiplus_GpBitmap">Gdiplus.GpBitmap</a></li>
<li><a href="#Gdiplus_GpBrush">Gdiplus.GpBrush</a></li>
<li><a href="#Gdiplus_GpFontFamily">Gdiplus.GpFontFamily</a></li>
<li><a href="#Gdiplus_GpGraphics">Gdiplus.GpGraphics</a></li>
<li><a href="#Gdiplus_GpImage">Gdiplus.GpImage</a></li>
<li><a href="#Gdiplus_GpMatrix">Gdiplus.GpMatrix</a></li>
<li><a href="#Gdiplus_GpPath">Gdiplus.GpPath</a></li>
<li><a href="#Gdiplus_GpPen">Gdiplus.GpPen</a></li>
<li><a href="#Gdiplus_GpSolidFill">Gdiplus.GpSolidFill</a></li>
<li><a href="#Gdiplus_GpStatus">Gdiplus.GpStatus</a></li>
<li><a href="#Gdiplus_GpStringFormat">Gdiplus.GpStringFormat</a></li>
<h3>Functions</h3>
<li><a href="#Gdiplus_GdipAddPathString">Gdiplus.GdipAddPathString</a></li>
<li><a href="#Gdiplus_GdipCreateBitmapFromScan0">Gdiplus.GdipCreateBitmapFromScan0</a></li>
<li><a href="#Gdiplus_GdipCreateFontFamilyFromName">Gdiplus.GdipCreateFontFamilyFromName</a></li>
<li><a href="#Gdiplus_GdipCreatePath">Gdiplus.GdipCreatePath</a></li>
<li><a href="#Gdiplus_GdipCreatePen1">Gdiplus.GdipCreatePen1</a></li>
<li><a href="#Gdiplus_GdipCreateSolidFill">Gdiplus.GdipCreateSolidFill</a></li>
<li><a href="#Gdiplus_GdipCreateStringFormat">Gdiplus.GdipCreateStringFormat</a></li>
<li><a href="#Gdiplus_GdipDeleteBrush">Gdiplus.GdipDeleteBrush</a></li>
<li><a href="#Gdiplus_GdipDeleteFontFamily">Gdiplus.GdipDeleteFontFamily</a></li>
<li><a href="#Gdiplus_GdipDeleteGraphics">Gdiplus.GdipDeleteGraphics</a></li>
<li><a href="#Gdiplus_GdipDeletePath">Gdiplus.GdipDeletePath</a></li>
<li><a href="#Gdiplus_GdipDeletePen">Gdiplus.GdipDeletePen</a></li>
<li><a href="#Gdiplus_GdipDeleteStringFormat">Gdiplus.GdipDeleteStringFormat</a></li>
<li><a href="#Gdiplus_GdipDisposeImage">Gdiplus.GdipDisposeImage</a></li>
<li><a href="#Gdiplus_GdipDrawPath">Gdiplus.GdipDrawPath</a></li>
<li><a href="#Gdiplus_GdipFillPath">Gdiplus.GdipFillPath</a></li>
<li><a href="#Gdiplus_GdipGetImageGraphicsContext">Gdiplus.GdipGetImageGraphicsContext</a></li>
<li><a href="#Gdiplus_GdipGetPathWorldBounds">Gdiplus.GdipGetPathWorldBounds</a></li>
<li><a href="#Gdiplus_GdipGraphicsClear">Gdiplus.GdipGraphicsClear</a></li>
<li><a href="#Gdiplus_GdipSetPenLineJoin">Gdiplus.GdipSetPenLineJoin</a></li>
<li><a href="#Gdiplus_GdipSetPixelOffsetMode">Gdiplus.GdipSetPixelOffsetMode</a></li>
<li><a href="#Gdiplus_GdipSetSmoothingMode">Gdiplus.GdipSetSmoothingMode</a></li>
<li><a href="#Gdiplus_GdipSetTextRenderingHint">Gdiplus.GdipSetTextRenderingHint</a></li>
<li><a href="#Gdiplus_GdiplusShutdown">Gdiplus.GdiplusShutdown</a></li>
<li><a href="#Gdiplus_GdiplusStartup">Gdiplus.GdiplusStartup</a></li>
</div></div>
<div class="right"><div class="right-page">
<h1>Module gdiplus</h1>
<h1>Content</h1>
<table class="api-item"><tr><td><span id="Gdiplus_GdiplusStartupInput"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdiplus.GdiplusStartupInput</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L33">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">GdiplusStartupInput</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">DebugEventCallback</td><td class="code-type">#null *void</td><td></td></tr>
<tr><td class="code-type">GdiplusVersion</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">SuppressBackgroundThread</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">SuppressExternalCodecs</td><td class="code-type">s32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdiplus_GpRectF"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Gdiplus.GpRectF</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L41">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">GpRectF</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">height</td><td class="code-type">f32</td><td></td></tr>
<tr><td class="code-type">width</td><td class="code-type">f32</td><td></td></tr>
<tr><td class="code-type">x</td><td class="code-type">f32</td><td></td></tr>
<tr><td class="code-type">y</td><td class="code-type">f32</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Gdiplus_GdipFillModeAlternate"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipFillModeAlternate</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L24">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipFillModeAlternate</span>          = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipFontStyleRegular"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipFontStyleRegular</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L25">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipFontStyleRegular</span>           = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipLineJoinRound"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipLineJoinRound</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L30">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipLineJoinRound</span>              = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipOk"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipOk</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L23">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipOk</span>                         = <span class="SNum">0</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipPixelFormat32bppPARGB"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipPixelFormat32bppPARGB</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L31">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipPixelFormat32bppPARGB</span>      = <span class="SNum">0x000E200B</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipPixelOffsetModeHighQuality"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipPixelOffsetModeHighQuality</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L28">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipPixelOffsetModeHighQuality</span> = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipSmoothingModeHighQuality"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipSmoothingModeHighQuality</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L27">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipSmoothingModeHighQuality</span>   = <span class="SNum">4</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipTextRenderingHintAAGridFit"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipTextRenderingHintAAGridFit</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L29">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipTextRenderingHintAAGridFit</span> = <span class="SNum">3</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipUnitPixel"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Gdiplus.GdipUnitPixel</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L26">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">GdipUnitPixel</span>                  = <span class="SNum">2</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpBitmap"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpBitmap</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L13">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpBitmap</span>       = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpBrush"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpBrush</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L14">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpBrush</span>        = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpFontFamily"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpFontFamily</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L16">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpFontFamily</span>   = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpGraphics"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpGraphics</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L11">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpGraphics</span>     = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpImage"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpImage</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L12">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpImage</span>        = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpMatrix"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpMatrix</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L20">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpMatrix</span>       = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpPath"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpPath</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L18">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpPath</span>         = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpPen"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpPen</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L19">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpPen</span>          = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpSolidFill"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpSolidFill</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L15">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpSolidFill</span>    = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpStatus"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpStatus</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L10">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpStatus</span>       = <span class="STpe">s32</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GpStringFormat"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Gdiplus.GpStringFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L17">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">GpStringFormat</span> = <span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipAddPathString"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipAddPathString</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L71">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipAddPathString</span>(path: *<span class="SCst">GpPath</span>, text: <span class="SCst">LPCWSTR</span>, length: <span class="STpe">s32</span>, family: *<span class="SCst">GpFontFamily</span>, style: <span class="STpe">s32</span>, emSize: <span class="STpe">f32</span>, layoutRect: <span class="SKwd">const</span> *<span class="SCst">GpRectF</span>, format: *<span class="SCst">GpStringFormat</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreateBitmapFromScan0"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreateBitmapFromScan0</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L57">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreateBitmapFromScan0</span>(width, height, stride: <span class="STpe">s32</span>, format: <span class="STpe">s32</span>, scan0: <span class="SItr">#null</span> [*] <span class="STpe">u8</span>, bitmap: *<span class="SItr">#null</span> *<span class="SCst">GpBitmap</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreateFontFamilyFromName"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreateFontFamilyFromName</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L65">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreateFontFamilyFromName</span>(name: <span class="SCst">LPCWSTR</span>, collection: <span class="SItr">#null</span> *<span class="STpe">void</span>, fontFamily: *<span class="SItr">#null</span> *<span class="SCst">GpFontFamily</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreatePath"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreatePath</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L69">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreatePath</span>(fillMode: <span class="STpe">s32</span>, path: *<span class="SItr">#null</span> *<span class="SCst">GpPath</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreatePen1"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreatePen1</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L73">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreatePen1</span>(color: <span class="STpe">u32</span>, width: <span class="STpe">f32</span>, unit: <span class="STpe">s32</span>, pen: *<span class="SItr">#null</span> *<span class="SCst">GpPen</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreateSolidFill"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreateSolidFill</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L76">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreateSolidFill</span>(color: <span class="STpe">u32</span>, brush: *<span class="SItr">#null</span> *<span class="SCst">GpSolidFill</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipCreateStringFormat"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipCreateStringFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L67">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipCreateStringFormat</span>(formatAttributes: <span class="STpe">s32</span>, language: <span class="STpe">u16</span>, format: *<span class="SItr">#null</span> *<span class="SCst">GpStringFormat</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeleteBrush"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeleteBrush</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L77">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeleteBrush</span>(brush: *<span class="SCst">GpBrush</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeleteFontFamily"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeleteFontFamily</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L66">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeleteFontFamily</span>(fontFamily: *<span class="SCst">GpFontFamily</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeleteGraphics"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeleteGraphics</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L60">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeleteGraphics</span>(graphics: *<span class="SCst">GpGraphics</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeletePath"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeletePath</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L70">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeletePath</span>(path: *<span class="SCst">GpPath</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeletePen"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeletePen</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L75">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeletePen</span>(pen: *<span class="SCst">GpPen</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDeleteStringFormat"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDeleteStringFormat</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L68">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDeleteStringFormat</span>(format: *<span class="SCst">GpStringFormat</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDisposeImage"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDisposeImage</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L58">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDisposeImage</span>(image: *<span class="SCst">GpImage</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipDrawPath"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipDrawPath</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L78">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipDrawPath</span>(graphics: *<span class="SCst">GpGraphics</span>, pen: *<span class="SCst">GpPen</span>, path: *<span class="SCst">GpPath</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipFillPath"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipFillPath</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L79">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipFillPath</span>(graphics: *<span class="SCst">GpGraphics</span>, brush: *<span class="SCst">GpBrush</span>, path: *<span class="SCst">GpPath</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipGetImageGraphicsContext"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipGetImageGraphicsContext</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L59">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipGetImageGraphicsContext</span>(image: *<span class="SCst">GpImage</span>, graphics: *<span class="SItr">#null</span> *<span class="SCst">GpGraphics</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipGetPathWorldBounds"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipGetPathWorldBounds</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L72">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipGetPathWorldBounds</span>(path: *<span class="SCst">GpPath</span>, bounds: *<span class="SCst">GpRectF</span>, matrix: <span class="SItr">#null</span> *<span class="SCst">GpMatrix</span>, pen: <span class="SItr">#null</span> *<span class="SCst">GpPen</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipGraphicsClear"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipGraphicsClear</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L64">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipGraphicsClear</span>(graphics: *<span class="SCst">GpGraphics</span>, color: <span class="STpe">u32</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipSetPenLineJoin"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipSetPenLineJoin</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L74">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipSetPenLineJoin</span>(pen: *<span class="SCst">GpPen</span>, lineJoin: <span class="STpe">s32</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipSetPixelOffsetMode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipSetPixelOffsetMode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L62">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipSetPixelOffsetMode</span>(graphics: *<span class="SCst">GpGraphics</span>, pixelOffsetMode: <span class="STpe">s32</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipSetSmoothingMode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipSetSmoothingMode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L61">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipSetSmoothingMode</span>(graphics: *<span class="SCst">GpGraphics</span>, smoothingMode: <span class="STpe">s32</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdipSetTextRenderingHint"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdipSetTextRenderingHint</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L63">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdipSetTextRenderingHint</span>(graphics: *<span class="SCst">GpGraphics</span>, mode: <span class="STpe">s32</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdiplusShutdown"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdiplusShutdown</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L52">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdiplusShutdown</span>(token: <span class="STpe">u64</span>)</span></div>
<table class="api-item"><tr><td><span id="Gdiplus_GdiplusStartup"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Gdiplus.GdiplusStartup</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/gdiplus/src/gdiplus.swg#L51">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">GdiplusStartup</span>(token: *<span class="STpe">u64</span>, input: <span class="SKwd">const</span> *<span class="SCst">GdiplusStartupInput</span>, output: <span class="SItr">#null</span> *<span class="STpe">void</span>)-&gt;<span class="SCst">GpStatus</span></span></div>
<div class="swag-watermark">Generated with <a href="https://swag-lang.org/index.php">swc</a> 0.1.1</div>
</div></div>
</div>
<script>
function getOffsetTop(element,parent){let offsetTop=0;while(element&&element!=parent){offsetTop+=element.offsetTop;element=element.offsetParent}return offsetTop}
document.addEventListener("DOMContentLoaded",function(){let hash=window.location.hash;if(!hash)return;let parent=document.querySelector(".right");let target=parent?parent.querySelector(hash):null;if(target)parent.scrollTop=getOffsetTop(target,parent)});
</script>
</body>
</html>
