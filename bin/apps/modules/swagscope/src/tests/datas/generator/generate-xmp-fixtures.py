#!/usr/bin/env python3
"""Generate small WebP and JPEG images with the same synthetic XMP packet."""

from pathlib import Path

from PIL import Image, ImageDraw


DATA = Path(__file__).resolve().parents[1]
XMP = b'''<?xpacket begin=""?>
<x:xmpmeta xmlns:x="adobe:ns:meta/">
 <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
  <rdf:Description xmlns:dc="http://purl.org/dc/elements/1.1/"
                   xmlns:xmp="http://ns.adobe.com/xap/1.0/"
                   dc:title="Watershed field study"
                   xmp:CreateDate="2026-06-14T10:30:00Z">
   <dc:creator><rdf:Seq><rdf:li>Generated Field Team</rdf:li></rdf:Seq></dc:creator>
   <dc:description>Generated test image; no real people or places.</dc:description>
   <dc:rights>CC0 1.0</dc:rights>
   <dc:subject><rdf:Bag><rdf:li>watershed</rdf:li><rdf:li>field notes</rdf:li></rdf:Bag></dc:subject>
  </rdf:Description>
 </rdf:RDF>
</x:xmpmeta>
<?xpacket end="w"?>'''

image = Image.new("RGB", (48, 32), (236, 230, 214))
draw = ImageDraw.Draw(image)
draw.rectangle((0, 0, 15, 31), fill=(190, 215, 165))
draw.rectangle((16, 0, 31, 31), fill=(105, 170, 190))
draw.rectangle((32, 0, 47, 31), fill=(238, 166, 74))
image.save(DATA / "viewer.xmp.webp", format="WEBP", quality=90, method=6, xmp=XMP)
image.save(DATA / "viewer.xmp.jpg", format="JPEG", quality=90, xmp=XMP)
for name in ("viewer.xmp.webp", "viewer.xmp.jpg"):
    path = DATA / name
    print(f"{name}: {path.stat().st_size} bytes")
