<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<?php include('common/start-head.php'); ?><title>Module audio</title>
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
<li><a href="#Audio_Bus">Audio.Bus</a></li>
<li><a href="#Audio_Voice">Audio.Voice</a></li>
<h4>codec</h4>
<li><a href="#Audio_Codec">Audio.Codec</a></li>
<li><a href="#Audio_ICodec___anonymous_struct_2">ICodec.__anonymous_struct_2</a></li>
<h4>file</h4>
<li><a href="#Audio_SoundFile">Audio.SoundFile</a></li>
<h3>Interfaces</h3>
<h4>codec</h4>
<li><a href="#Audio_ICodec">Audio.ICodec</a></li>
<h3>Enums</h3>
<li><a href="#Audio_VoiceCreateFlags">Audio.VoiceCreateFlags</a></li>
<li><a href="#Audio_VoicePlayFlags">Audio.VoicePlayFlags</a></li>
<li><a href="#Audio_VoiceState">Audio.VoiceState</a></li>
<h4>driver</h4>
<li><a href="#Audio_DriverKind">Audio.DriverKind</a></li>
<h4>file</h4>
<li><a href="#Audio_SoundFileEncoding">Audio.SoundFileEncoding</a></li>
<li><a href="#Audio_SoundFileValidityMask">Audio.SoundFileValidityMask</a></li>
<h3>Constants</h3>
<li><a href="#Audio_Voice_DecodedBufferSize">Voice.DecodedBufferSize</a></li>
<li><a href="#Audio_Voice_NumDecodedBuffers">Voice.NumDecodedBuffers</a></li>
<li><a href="#Audio_Voice_StreamBufferSize">Voice.StreamBufferSize</a></li>
<h3>Type Aliases</h3>
<h4>driver</h4>
<li><a href="#Audio_BusHandle">Audio.BusHandle</a></li>
<li><a href="#Audio_VoiceHandle">Audio.VoiceHandle</a></li>
<h3>Functions</h3>
<li><a href="#Audio_convertDBToPercent">Audio.convertDBToPercent</a></li>
<li><a href="#Audio_convertPercentToDB">Audio.convertPercentToDB</a></li>
<li><a href="#Audio_createEngine">Audio.createEngine</a></li>
<li><a href="#Audio_createNoSoundEngine">Audio.createNoSoundEngine</a></li>
<li><a href="#Audio_destroyEngine">Audio.destroyEngine</a></li>
<li><a href="#Audio_getOutputVolume">Audio.getOutputVolume</a></li>
<li><a href="#Audio_setOutputVolume">Audio.setOutputVolume</a></li>
<h4>codec</h4>
<li><a href="#Audio_ICodec_canDecode">ICodec.canDecode</a></li>
<li><a href="#Audio_ICodec_canEncode">ICodec.canEncode</a></li>
<li><a href="#Audio_ICodec_decode">ICodec.decode</a></li>
<li><a href="#Audio_ICodec_init">ICodec.init</a></li>
<li><a href="#Audio_addCodec">Audio.addCodec</a></li>
<h4>file</h4>
<li><a href="#Audio_Wav_loadFile">Wav.loadFile</a></li>
</div></div>
<div class="right"><div class="right-page">
<h1>Module audio</h1>
<h1>Content</h1>
<table class="api-item"><tr><td><span id="Audio_Bus"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Audio.Bus</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/bus.swg#L6">[src]</a></td></tr></table>
<p>Represents a bus. A <a href="#Audio_Voice">Voice</a> can be assigned to one or more buses. If you then change some parameters of the bus (like the volume), then all the voices assigned to it will be impacted.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">Bus</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">handle</td><td class="code-type">#null *void</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_Voice"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Audio.Voice</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L33">[src]</a></td></tr></table>
<p>Represents a playing sound</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.Opaque]</span>
<span class="SKwd">struct</span> <span class="SCst">Voice</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">DecodedBufferSize</td><td class="code-type">u64</td><td></td></tr>
<tr><td class="code-type">NumDecodedBuffers</td><td class="code-type">s32</td><td></td></tr>
<tr><td class="code-type">StreamBufferSize</td><td class="code-type">u64</td><td></td></tr>
<tr><td class="code-type">codec</td><td class="code-type">#null Audio.ICodec</td><td></td></tr>
<tr><td class="code-type">decodedBufferIdx</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">decodedBuffers</td><td class="code-type">[3] Core.Array'(u8)</td><td></td></tr>
<tr><td class="code-type">file</td><td class="code-type">#null *Audio.SoundFile</td><td></td></tr>
<tr><td class="code-type">handle</td><td class="code-type">#null *void</td><td></td></tr>
<tr><td class="code-type">idxInList</td><td class="code-type">u32</td><td></td></tr>
<tr><td class="code-type">playFlags</td><td class="code-type">Audio.VoicePlayFlags</td><td></td></tr>
<tr><td class="code-type">requestedEncoding</td><td class="code-type">Audio.SoundFileEncoding</td><td></td></tr>
<tr><td class="code-type">state</td><td class="code-type">Audio.VoiceState</td><td></td></tr>
<tr><td class="code-type">stream</td><td class="code-type">Core.File.FileStream</td><td></td></tr>
<tr><td class="code-type">streamBuffer</td><td class="code-type">Core.Array'(u8)</td><td></td></tr>
<tr><td class="code-type">streamCurSeek</td><td class="code-type">u64</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_Codec"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Audio.Codec</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L49">[src]</a></td></tr></table>
<p>Base struct for all codec instances</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">Codec</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">dstEncoding</td><td class="code-type">Audio.SoundFileEncoding</td><td><p>The requested encoding</p>
</td></tr>
<tr><td class="code-type">srcEncoding</td><td class="code-type">Audio.SoundFileEncoding</td><td><p>The original encoding</p>
</td></tr>
<tr><td class="code-type">type</td><td class="code-type">const *Audio.Swag.TypeInfoStruct</td><td><p>The real type of the codec</p>
</td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_ICodec___anonymous_struct_2"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">ICodec.__anonymous_struct_2</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L12">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde">{ write, read: <span class="STpe">u64</span> }</span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">read</td><td class="code-type">u64</td><td></td></tr>
<tr><td class="code-type">write</td><td class="code-type">u64</td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_SoundFile"><span class="api-item-title-kind">struct</span> <span class="api-item-title-strong">Audio.SoundFile</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/file/soundfile.swg#L36">[src]</a></td></tr></table>
<p>Represents a sound file. The <span class="code-inline">SoundFile</span> is not necessary fully loaded in memory, in case we want it to be streamed.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">struct</span> <span class="SCst">SoundFile</span></span></div>
<h3>Fields</h3>
<table class="table-enumeration">
<tr><td class="code-type">bitsPerSample</td><td class="code-type">u32</td><td><p>Number of bits per sample in the datas</p>
</td></tr>
<tr><td class="code-type">channelCount</td><td class="code-type">u32</td><td><p>Number of channels (2 for stereo...)</p>
</td></tr>
<tr><td class="code-type">channelMask</td><td class="code-type">u32</td><td><p>Identifier of the channels</p>
</td></tr>
<tr><td class="code-type">dataSeek</td><td class="code-type">u64</td><td><p>The position in the file where the datas are stored</p>
</td></tr>
<tr><td class="code-type">dataSize</td><td class="code-type">u64</td><td><p>Total size, in bytes, of datas</p>
</td></tr>
<tr><td class="code-type">datas</td><td class="code-type">Core.Array'(u8)</td><td><p>Prefetched datas (in encoding format)</p>
</td></tr>
<tr><td class="code-type">duration</td><td class="code-type">f32</td><td><p>Duration, in seconds, of the sound</p>
</td></tr>
<tr><td class="code-type">encoding</td><td class="code-type">Audio.SoundFileEncoding</td><td><p>Encoding type of the datas</p>
</td></tr>
<tr><td class="code-type">frequency</td><td class="code-type">u32</td><td><p>Sound frequency</p>
</td></tr>
<tr><td class="code-type">fullname</td><td class="code-type">Core.String</td><td></td></tr>
<tr><td class="code-type">sampleCount</td><td class="code-type">u64</td><td><p>Total number of samples</p>
</td></tr>
<tr><td class="code-type">validBitsPerSample</td><td class="code-type">u16</td><td><p>Number of valid bits per sample (&lt;= bitsPerSample)</p>
</td></tr>
<tr><td class="code-type">validity</td><td class="code-type">Audio.SoundFileValidityMask</td><td><p>What informations in this struct are valid</p>
</td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_ICodec"><span class="api-item-title-kind">interface</span> <span class="api-item-title-strong">Audio.ICodec</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L7">[src]</a></td></tr></table>
<p>Interface to describe a codec</p>
<div class="code-block"><span class="SCde"><span class="SKwd">interface</span> <span class="SCst">ICodec</span></span></div>
<h3>Functions</h3>
<table class="table-enumeration">
<tr><td class="code-type"><a href="#Audio_ICodec_canDecode">canDecode</a></td><td></td></tr>
<tr><td class="code-type"><a href="#Audio_ICodec_canEncode">canEncode</a></td><td></td></tr>
<tr><td class="code-type"><a href="#Audio_ICodec_decode">decode</a></td><td></td></tr>
<tr><td class="code-type"><a href="#Audio_ICodec_init">init</a></td><td></td></tr>
</table>
<table class="api-item"><tr><td><span id="Audio_VoiceCreateFlags"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.VoiceCreateFlags</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L5">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.EnumFlags]</span>
<span class="SKwd">enum</span> <span class="SCst">VoiceCreateFlags</span></span></div>
<table class="api-item"><tr><td><span id="Audio_VoicePlayFlags"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.VoicePlayFlags</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L14">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.EnumFlags]</span>
<span class="SKwd">enum</span> <span class="SCst">VoicePlayFlags</span></span></div>
<table class="api-item"><tr><td><span id="Audio_VoiceState"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.VoiceState</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L23">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.EnumFlags]</span>
<span class="SKwd">enum</span> <span class="SCst">VoiceState</span></span></div>
<table class="api-item"><tr><td><span id="Audio_DriverKind"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.DriverKind</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/driver/backend.swg#L4">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">enum</span> <span class="SCst">DriverKind</span></span></div>
<table class="api-item"><tr><td><span id="Audio_SoundFileEncoding"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.SoundFileEncoding</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/file/soundfile.swg#L24">[src]</a></td></tr></table>
<p>SoundFile private format.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">enum</span> <span class="SCst">SoundFileEncoding</span></span></div>
<table class="api-item"><tr><td><span id="Audio_SoundFileValidityMask"><span class="api-item-title-kind">enum</span> <span class="api-item-title-strong">Audio.SoundFileValidityMask</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/file/soundfile.swg#L8">[src]</a></td></tr></table>
<p>Determins which informations in the <a href="#Audio_SoundFile">SoundFile</a> struct are valid.</p>
<div class="code-block"><span class="SCde"><span class="SAtr">#[Swag.EnumFlags]</span>
<span class="SKwd">enum</span> <span class="SCst">SoundFileValidityMask</span></span></div>
<table class="api-item"><tr><td><span id="Audio_Voice_DecodedBufferSize"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Voice.DecodedBufferSize</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L49">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">DecodedBufferSize</span> = <span class="SNum">65536</span>'<span class="STpe">u64</span></span></div>
<table class="api-item"><tr><td><span id="Audio_Voice_NumDecodedBuffers"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Voice.NumDecodedBuffers</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L48">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">NumDecodedBuffers</span> = <span class="SNum">3</span></span></div>
<table class="api-item"><tr><td><span id="Audio_Voice_StreamBufferSize"><span class="api-item-title-kind">const</span> <span class="api-item-title-strong">Voice.StreamBufferSize</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/voice.swg#L44">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">const</span> <span class="SCst">StreamBufferSize</span>  = <span class="SNum">16</span> * <span class="SNum">1024</span>'<span class="STpe">u64</span></span></div>
<table class="api-item"><tr><td><span id="Audio_BusHandle"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Audio.BusHandle</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/driver/backend.swg#L12">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">BusHandle</span> = <span class="SItr">#null</span> *<span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Audio_VoiceHandle"><span class="api-item-title-kind">type alias</span> <span class="api-item-title-strong">Audio.VoiceHandle</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/driver/backend.swg#L11">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">alias</span> <span class="SCst">VoiceHandle</span> = <span class="SItr">#null</span> *<span class="STpe">void</span></span></div>
<table class="api-item"><tr><td><span id="Audio_convertDBToPercent"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.convertDBToPercent</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/helpers.swg#L5">[src]</a></td></tr></table>
<p>Convert a DB value to a percent</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">convertDBToPercent</span>(dbVolume: <span class="STpe">f32</span>)-&gt;<span class="STpe">f32</span></span></div>
<table class="api-item"><tr><td><span id="Audio_convertPercentToDB"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.convertPercentToDB</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/helpers.swg#L13">[src]</a></td></tr></table>
<p>Convert a percent value to DB</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">convertPercentToDB</span>(percentVolume: <span class="STpe">f32</span>)-&gt;<span class="STpe">f32</span></span></div>
<table class="api-item"><tr><td><span id="Audio_createEngine"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.createEngine</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/audio.swg#L8">[src]</a></td></tr></table>
<p>Creates the audio engine. Must be called once, before anything else.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">createEngine</span>(kind: <span class="SCst">DriverKind</span> = .<span class="SCst">Default</span>) <span class="SKwd">fail</span></span></div>
<table class="api-item"><tr><td><span id="Audio_createNoSoundEngine"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.createNoSoundEngine</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/audio.swg#L14">[src]</a></td></tr></table>
<p>Creates the audio engine with the no-sound driver.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">createNoSoundEngine</span>() <span class="SKwd">fail</span> =&gt; createEngine</span></div>
<table class="api-item"><tr><td><span id="Audio_destroyEngine"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.destroyEngine</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/audio.swg#L18">[src]</a></td></tr></table>
<p>Destroy the audio engine. Must be called at the end, when engine is no more used.</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">destroyEngine</span>()</span></div>
<table class="api-item"><tr><td><span id="Audio_getOutputVolume"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.getOutputVolume</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/audio.swg#L27">[src]</a></td></tr></table>
<p>Get the general output volume</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">getOutputVolume</span>()-&gt;<span class="STpe">f32</span> =&gt; g_Driver.getOutputVolume</span></div>
<table class="api-item"><tr><td><span id="Audio_setOutputVolume"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.setOutputVolume</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/audio.swg#L24">[src]</a></td></tr></table>
<p>Set the general output volume</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">setOutputVolume</span>(volume: <span class="STpe">f32</span>) <span class="SKwd">fail</span> =&gt; g_Driver.setOutputVolume</span></div>
<table class="api-item"><tr><td><span id="Audio_ICodec_canDecode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">ICodec.canDecode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L10">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">mtd</span> <span class="SFct">canDecode</span>(encoding: <span class="SCst">SoundFileEncoding</span>)-&gt;<span class="STpe">bool</span></span></div>
<table class="api-item"><tr><td><span id="Audio_ICodec_canEncode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">ICodec.canEncode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L9">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">mtd</span> <span class="SFct">canEncode</span>(encoding: <span class="SCst">SoundFileEncoding</span>)-&gt;<span class="STpe">bool</span></span></div>
<table class="api-item"><tr><td><span id="Audio_ICodec_decode"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">ICodec.decode</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L12">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">mtd</span> <span class="SFct">decode</span>(destBuffer: [*] <span class="STpe">void</span>, destLength: <span class="STpe">u64</span>, srcBuffer: [*] <span class="STpe">void</span>, srcLength: <span class="STpe">u64</span>)-&gt;{ write, read: <span class="STpe">u64</span> }</span></div>
<table class="api-item"><tr><td><span id="Audio_ICodec_init"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">ICodec.init</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L11">[src]</a></td></tr></table>
<div class="code-block"><span class="SCde"><span class="SKwd">mtd</span> <span class="SFct">init</span>(srcBuffer: [*] <span class="STpe">void</span>, srcLength: <span class="STpe">u64</span>)-&gt;<span class="STpe">u64</span></span></div>
<table class="api-item"><tr><td><span id="Audio_addCodec"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Audio.addCodec</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/codec/codec.swg#L22">[src]</a></td></tr></table>
<p>Register a codec</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span>(<span class="SCst">T</span>) <span class="SFct">addCodec</span>()</span></div>
<table class="api-item"><tr><td><span id="Audio_Wav_loadFile"><span class="api-item-title-kind">func</span> <span class="api-item-title-strong">Wav.loadFile</span></span></td><td class="api-item-title-src-ref"><a href="https://github.com/swag-lang/swag/blob/master/bin/std/modules/audio/src/file/wav.swg#L242">[src]</a></td></tr></table>
<p>Load a wav file</p>
<div class="code-block"><span class="SCde"><span class="SKwd">func</span> <span class="SFct">loadFile</span>(file: *<span class="SCst">SoundFile</span>, stream: *<span class="SCst">File</span>.<span class="SCst">FileStream</span>, loadDatas = <span class="SKwd">true</span>, loadMetaDatas = <span class="SKwd">false</span>) <span class="SKwd">fail</span></span></div>
<div class="swag-watermark">Generated with <a href="https://swag-lang.org/index.php">swc</a> 0.1.1</div>
</div></div>
</div>
<script>
function getOffsetTop(element,parent){let offsetTop=0;while(element&&element!=parent){offsetTop+=element.offsetTop;element=element.offsetParent}return offsetTop}
document.addEventListener("DOMContentLoaded",function(){let hash=window.location.hash;if(!hash)return;let parent=document.querySelector(".right");let target=parent?parent.querySelector(hash):null;if(target)parent.scrollTop=getOffsetTop(target,parent)});
</script>
</body>
</html>
