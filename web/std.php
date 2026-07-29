<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php include('common/start-head.php'); ?><title>Std</title>
<link rel="icon" type="image/x-icon" href="favicon.ico">
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
</style>

</head>
<body>
<?php include('common/start-body.php'); ?>
<div class="container">
<div class="right"><div class="right-page">
<p>This is the list of all modules that come with the compiler. As they are always in sync, they are considered as <b>standard</b>. They are all part of the same workspace <b>std</b>.</p>
<p>You can find that workspace locally in <span class="code-inline">bin/std</span>, or <a href="https://github.com/swag-lang/swag/tree/master/bin/std">here</a> on GitHub.</p>
<h1 id="Modules">Modules</h1>
<p>| <a href="std.core.php">std.core</a>         | Main core module, the base of everything else</p>
<p>| <a href="std.pixel.php">std.pixel</a>       | An image and a 2D painting module</p>
<p>| <a href="std.gui.php">std.gui</a>           | A user interface module (windows, widgets...)</p>
<p>| <a href="std.audio.php">std.audio</a>       | An audio module to decode and play sounds</p>
<p>| <a href="std.libc.php">std.libc</a>         | Libc wrapper</p>
<h1 id="Wrappers">Wrappers</h1>
<p>Those other modules are just wrappers to external libraries.</p>
<p>| <a href="std.ogl.php">std.ogl</a>           | Opengl wrapper</p>
<p>| <a href="std.freetype.php">std.freetype</a> | Freetype wrapper</p>
<p>| <a href="std.win32.php">std.win32</a>       | Windows <span class="code-inline">win32</span> wrapper (kernel32, user32...)</p>
<p>| <a href="std.gdi32.php">std.gdi32</a>       | Windows <span class="code-inline">gdi32</span> wrapper</p>
<p>| <a href="std.xinput.php">std.xinput</a>     | Windows 'direct X input' wrapper</p>
<p>| <a href="std.xaudio2.php">std.xaudio2</a>   | <span class="code-inline">xaudio2</span> wrapper</p>
<div class="swag-watermark">Generated with <a href="https://swag-lang.org/index.php">swc</a> 0.1.1</div>
</div></div>
</div>
<script>
function getOffsetTop(element,parent){let offsetTop=0;while(element&&element!=parent){offsetTop+=element.offsetTop;element=element.offsetParent}return offsetTop}
document.addEventListener("DOMContentLoaded",function(){let hash=window.location.hash;if(!hash)return;let parent=document.querySelector(".right");let target=parent?parent.querySelector(hash):null;if(target)parent.scrollTop=getOffsetTop(target,parent)});
</script>
</body>
</html>
