#global public
#global namespace Testing

using Swag, Core, Core.Math

// Granularity of a [[Testing.dumpPainter]] snapshot.
//
// Only 'Full' records texture coordinates, and they are the one part of a snapshot that is not
// self-contained: glyph coordinates depend on the packing order of a glyph cache shared by the
// whole process, so a drawing that uses a font shared with another test must be recorded at
// 'Batches' or below to stay reproducible whatever the test order.
enum DumpLevel
{
    Commands     // Commands and batch sizes, with no vertex detail.
    Batches      // Adds per-batch bounds, colors and antialiasing coverage.
    Full         // Adds per-batch texture coordinates.
}

// Serializes the display list recorded by 'painter' into a stable, human readable snapshot.
//
// The result is meant to be stored as a golden file and compared verbatim, so every value that
// is not reproducible across runs or machines is normalized away:
//
// + Texture handles, font and render target addresses, and shader uniform locations are replaced
//   by 'tex#N', 'font#N', 'rt#N', 'shader#N' and 'p#N' indices assigned in first-use order.
// + Font labels keep only the file name of the underlying typeface, never its directory.
// + Floating point values are rounded to three decimals and printed without an exponent.
//
// The snapshot opens with one '#' legend line per remapped object, then a blank line, then one
// line per command. Lines are separated by a single '\n' and the result ends with a '\n'.
//
// 'painter' must have completed a `begin()` / `end()` pass; the painter is only read, never
// modified. A lower 'level' keeps snapshots of composite drawings (widgets, whole windows)
// readable while still catching command level regressions.
func dumpPainter(painter: const *Painter, level = DumpLevel.Full)->String
{
    var dump: CommandDump
    dump.level = level
    dump.run(painter)

    var result: retval
    if !dump.legend.isEmpty()
    {
        result += dump.legend
        result += "\n"
    }

    result += dump.body
    return result
}

private
{
    // Rounds to three decimals and prints without trailing zeros, so that '1.0' and '-0.0' both
    // have a single spelling. Values that differ by less than 0.0005 collapse to the same text,
    // which is what makes a snapshot stable across compilers and optimization levels.
    func fmtF(value: f32)->String
    {
        var v = Math.round(value * 1000) / 1000
        if v == 0 do
            v = 0

        var result: retval
        result.appendFormat("%{f3}", v)
        while result.back() == '0'u8 do
            result.removeBack()
        if result.back() == '.'u8 do
            result.removeBack()
        return result
    }

    // Normalized texture coordinates need more digits than geometry: on a large atlas the half
    // texel inset that separates a correct sample from a bleeding one is far below 0.001. These
    // values come from exact divisions of small integers, so the extra digits stay stable.
    func fmtNorm(value: f32)->String
    {
        var v = Math.round(value * 1000000) / 1000000
        if v == 0 do
            v = 0

        var result: retval
        result.appendFormat("%{f6}", v)
        while result.back() == '0'u8 do
            result.removeBack()
        if result.back() == '.'u8 do
            result.removeBack()
        return result
    }

    func fmtColor(color: Color)->String
    {
        return Format.toString("%{X08}", color.argb)
    }

    func(T) fmtEnum(value: T)->String
    {
        var v = value
        return Reflection.enumName(T, &v, fullyQualified: false)
    }

    #[Swag.NoCopy]
    struct CommandDump
    {
        level:  DumpLevel = Full
        legend: String
        body:   String

        // Remap tables. The index of an entry is the number printed in the snapshot, so the
        // first object of each kind that a drawing touches is always '#0'.
        textures: Array'TextureHandle
        fonts:    Array'#null const *Font
        targets:  Array'#null const *RenderTarget
        shaders:  Array'#null const *ShaderBase
        params:   Array'ShaderParamHandle
    }

    impl CommandDump
    {
        mtd texRef(texture: Texture)->String
        {
            for it, [idx] in .textures where it == texture.handle do
                return Format.toString("tex#%", idx)

            .textures.add(texture.handle)
            let idx = .textures.count - 1
            .legend.appendFormat("# tex#% %x% %\n", idx, texture.width, texture.height, fmtEnum(texture.pixelFormat))
            return Format.toString("tex#%", idx)
        }

        mtd fontRef(font: const *Font)->String
        {
            for it, [idx] in .fonts where it == font do
                return Format.toString("font#%", idx)

            .fonts.add(font)
            let idx = .fonts.count - 1

            // A typeface loaded from a file is named by its path. Keeping only the file name makes
            // the label identical whatever the checkout directory is.
            let label = Path.fileName(font.cache.typeFace.fullname)
            .legend.appendFormat("# font#% % size=% mode=%\n", idx, label, font.size, fmtEnum(font.mode))
            return Format.toString("font#%", idx)
        }

        mtd targetRef(target: #null const *RenderTarget)->String
        {
            if !target do
                return String.from("none")

            for it, [idx] in .targets where it == target do
                return Format.toString("rt#%", idx)

            .targets.add(target)
            let idx = .targets.count - 1
            .legend.appendFormat("# rt#% %x%\n", idx, target.colorBuffer.width, target.colorBuffer.height)
            return Format.toString("rt#%", idx)
        }

        mtd shaderRef(shader: #null const *ShaderBase)->String
        {
            if !shader do
                return String.from("none")

            for it, [idx] in .shaders where it == shader do
                return Format.toString("shader#%", idx)

            .shaders.add(shader)
            return Format.toString("shader#%", .shaders.count - 1)
        }

        // A shader parameter handle is a uniform location assigned by the driver at link time,
        // so it is remapped like any other opaque handle.
        mtd paramRef(param: ShaderParamHandle)->String
        {
            for it, [idx] in .params where it == param do
                return Format.toString("p#%", idx)

            .params.add(param)
            return Format.toString("p#%", .params.count - 1)
        }

        mtd run(painter: const *Painter)
        {
            for &cmd in painter.commandBuffer do
                .dumpCommand(painter, cmd)
        }

        mtd dumpCommand(painter: const *Painter, cmd: const *Command)
        {
            .body += fmtEnum(cmd.id)

            switch cmd.id
            {
            case .Clear:
                .body.appendFormat(" %", fmtColor(cmd.clear.color))

            case .ColorMask:
                .body += " "
                .body += cmd.colorMask.r ? "r" : "-"
                .body += cmd.colorMask.g ? "g" : "-"
                .body += cmd.colorMask.b ? "b" : "-"
                .body += cmd.colorMask.a ? "a" : "-"

            case .Transform:
                let tr = cmd.transform.tr
                .body.appendFormat(" % % % % % %", fmtF(tr.m11), fmtF(tr.m12), fmtF(tr.m21), fmtF(tr.m22), fmtF(tr.tx), fmtF(tr.ty))

            case .DrawTriangles:
                .dumpTriangles(painter, cmd.drawTriangles.start, cmd.drawTriangles.count)

            case .BindTexture0:
                .dumpTexture0(cmd)

            case .SetClippingRect:
                let r = cmd.clippingRect.rect
                .body.appendFormat(" % % % %", fmtF(r.x), fmtF(r.y), fmtF(r.width), fmtF(r.height))

            case .StartClippingRegion, .SetClippingRegionMode:
                .body.appendFormat(" %", fmtEnum(cmd.clippingRegion.mode))

            case .SetBlendingMode:
                .body.appendFormat(" %", fmtEnum(cmd.blendingMode.mode))

            case .UpdateFont:
                .body.appendFormat(" %", .fontRef(cmd.font.fontRef))

            case .BindTextureFont:
                .body.appendFormat(" % atlas=%", .fontRef(cmd.textureFont.font), cmd.textureFont.atlasIndex)

            case .BindRenderTarget:
                .body.appendFormat(" % paintAlpha=%", .targetRef(cmd.renderTgt.tgt), cmd.renderTgt.paintAlpha)

            case .ReleaseRenderTarget:
                .body.appendFormat(" %", .targetRef(cmd.renderTgt.tgt))

            case .SetShader:
                .body.appendFormat(" %", .shaderRef(cmd.shader.shader))

            case .SetShaderParam:
                .body.appendFormat(" % %=", .paramRef(cmd.shaderParam.param), cmd.shaderParam.type.name)
                if cmd.shaderParam.type == s32 do
                    .body.appendFormat("%", cmd.shaderParam._s32)
                else do
                    .body += fmtF(cmd.shaderParam._f32)

            case .SetFontEffect:
                .dumpFontEffect(cmd)
            }

            .body += "\n"
        }

        mtd dumpTexture0(cmd: const *Command)
        {
            let p = &cmd.texture0
            .body.appendFormat(" % uv=% interp=%", fmtEnum(p.type), fmtEnum(p.uvMode), fmtEnum(p.interpolationMode))

            if p.type == .Hatch do
                .body.appendFormat(" hatch=%", fmtEnum(p.hatch))
            if p.texture.isValid() do
                .body.appendFormat(" %", .texRef(p.texture))

            .body.appendFormat(" bound=(%,%)-(%,%)", fmtF(p.boundRect.x), fmtF(p.boundRect.y), fmtF(p.boundRect.z), fmtF(p.boundRect.w))

            // For a sub-rectangle brush this carries the normalized, half-texel inset source
            // rectangle, which is the value a sampling regression would move.
            if p.uvMode == .FillSubRect do
                .body.appendFormat(" src=(%,%)-(%,%)", fmtNorm(p.textureRect.x), fmtNorm(p.textureRect.y), fmtNorm(p.textureRect.z), fmtNorm(p.textureRect.w))

            switch p.type
            {
            case .LinearGradient: .body.appendFormat(" from=(%,%) to=(%,%)", fmtF(p.gradientStart.x), fmtF(p.gradientStart.y), fmtF(p.gradientEnd.x), fmtF(p.gradientEnd.y))
            case .RadialGradient: .body.appendFormat(" center=(%,%) radius=%..%", fmtF(p.gradientStart.x), fmtF(p.gradientStart.y), fmtF(p.gradientRadius0), fmtF(p.gradientRadius1))
            case .SweepGradient:  .body.appendFormat(" center=(%,%) angle=%..%", fmtF(p.gradientStart.x), fmtF(p.gradientStart.y), fmtF(p.gradientAngle0), fmtF(p.gradientAngle1))
            }

            if p.gradientStopCount
            {
                .body.appendFormat(" spread=% stops=[", fmtEnum(p.gradientSpread))
                for [i] in p.gradientStopCount
                {
                    if i do
                        .body += " "
                    .body.appendFormat("%:%", fmtF(p.gradientStops[i].offset), fmtColor(p.gradientStops[i].color))
                }

                .body += "]"
            }
        }

        mtd dumpFontEffect(cmd: const *Command)
        {
            let e = &cmd.fontEffect
            if !e.enabled
            {
                .body += " off"
                return
            }

            .body.appendFormat(" dilate=% soft=%", fmtF(e.faceDilate), fmtF(e.faceSoftness))
            if e.outlineWidth do
                .body.appendFormat(" outline=%:%", fmtF(e.outlineWidth), fmtColor(e.outlineColor))
            if e.glowOuter do
                .body.appendFormat(" glow=%:%", fmtF(e.glowOuter), fmtColor(e.glowColor))
            if e.bevel do
                .body.appendFormat(" bevel=%", fmtF(e.bevel))
        }

        // Vertices are summarized, never dumped one by one: a single glyph run is dozens of
        // vertices whose exact coordinates carry no reviewable information, while the batch size,
        // the bounding box and the color set do.
        mtd dumpTriangles(painter: const *Painter, start, count: u32)
        {
            .body.appendFormat(" n=%", count)
            if .level == .Commands or !count do
                return

            var bbMin = Vector2{Swag.F32.Max, Swag.F32.Max}
            var bbMax = Vector2{Swag.F32.Min, Swag.F32.Min}
            var uvMin = Vector2{Swag.F32.Max, Swag.F32.Max}
            var uvMax = Vector2{Swag.F32.Min, Swag.F32.Min}

            var colors:   Array'u32
            var solid = true
            var hasUv = false
            var extraCol: u32

            for [i] in count
            {
                let v = painter.vertexBuffer[cast(u64) (start + i)]

                bbMin.x = Math.min(bbMin.x, v.pos.x)
                bbMin.y = Math.min(bbMin.y, v.pos.y)
                bbMax.x = Math.max(bbMax.x, v.pos.x)
                bbMax.y = Math.max(bbMax.y, v.pos.y)

                // Only the glyph emitter produces non-zero texture coordinates today; reporting
                // them on the sole condition that they are set keeps solid fills terse and makes
                // any future emitter that starts using them show up on its own.
                if v.uv.x != 0 or v.uv.y != 0
                {
                    hasUv   = true
                    uvMin.x = Math.min(uvMin.x, v.uv.x)
                    uvMin.y = Math.min(uvMin.y, v.uv.y)
                    uvMax.x = Math.max(uvMax.x, v.uv.x)
                    uvMax.y = Math.max(uvMax.y, v.uv.y)
                }

                if v.cov != 1 do
                    solid = false

                var known = false
                for c in colors where c == v.color
                {
                    known = true
                    break
                }

                if !known
                {
                    if colors.count < 4 do
                        colors.add(v.color)
                    else do
                        extraCol += 1
                }
            }

            .body.appendFormat(" bbox=(%,%)-(%,%)", fmtF(bbMin.x), fmtF(bbMin.y), fmtF(bbMax.x), fmtF(bbMax.y))
            if hasUv and .level == .Full do
                .body.appendFormat(" uv=(%,%)-(%,%)", fmtF(uvMin.x), fmtF(uvMin.y), fmtF(uvMax.x), fmtF(uvMax.y))

            .body += " colors=["
            for c, [i] in colors
            {
                if i do
                    .body += " "
                .body.appendFormat("%{X08}", c)
            }

            if extraCol do
                .body.appendFormat(" +%", extraCol)
            .body += "]"

            .body += solid ? " cov=solid" : " cov=aa"
        }
    }
}
