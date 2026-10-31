# Capture icon rasters

`icons.svg` is the master. `icons.32px.png` and `icons.40px.png` hold its exact
DevMode CPU rasterization at the two common startup sizes, with fourfold supersampling.
`IconAtlas.setRaster` supplies them before icon sets are created; all other sizes retain
the SVG path. The adjacent application tile is a separate product asset.

Regenerate and verify from the repository root:

```text
bin/swc.dm.exe run -f bin/apps/modules/swagcapture/tools/rasterize.icons.swgs --num-cores 3
tools/apps.bat dm test swagcapture --test-file icons.rasters.test.swg
```

Generation is manual asset maintenance; application builds include the PNG files directly.
