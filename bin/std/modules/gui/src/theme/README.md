# Theme raster derivatives

The SVG files are the masters. Their adjacent PNG files contain the exact CPU-rasterized
pixels for frequently requested sizes, including the existing supersampling policy.
Both palettes tint the same masks. Less common sizes and resource overrides continue to
rasterize their SVG at runtime.

Regenerate after changing the SVG or rasterizer, from the repository root:

```text
bin/swc.dm.exe run -f bin/std/modules/gui/tools/rasterize-theme.swgs --num-cores 6
tools/std.bat dm test gui --test-file theme.rasters.swg --test-file theme.resources.swg
tools/std.bat dm test gui -bc release --test-file theme.rasters.swg
```

The ten default TrueType faces are embedded as lossless zlib streams to reduce executable size.
Regenerate them after changing a source font, from the repository root:

```text
bin/swc.dm.exe run -f bin/std/modules/gui/tools/compress-theme-fonts.swgs
```

`Resources.Bundle.load` decodes compressed embedded resources transparently, so resource names,
disk overrides, and the `TypeFace` input remain ordinary `.ttf` bytes.

This is an asset-maintenance operation, not a compilation step. Normal builds include the
checked-in PNG bytes directly. Keep the generated sizes and `paint/theme.rasters.swg` in
sync, and measure executable growth before expanding the set. DevMode tests compare every
decoded byte against the current SVG renderer and preserve the GUI goldens. Release allows one
coverage quantization level for its different floating-point policy; neither test accepts
displaced or resized geometry.
