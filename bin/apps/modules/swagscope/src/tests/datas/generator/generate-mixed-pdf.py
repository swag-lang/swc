from io import BytesIO
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas
from reportlab.lib.utils import ImageReader

out = Path(__file__).resolve().parents[1] / 'viewer.mixed-text-scan.pdf'
# Create a lightly skewed, noisy paper scan entirely from synthetic pixels and Pillow's built-in font.
width, height = 1275, 1650
im = Image.new('RGB', (width, height), (246, 245, 238))
draw = ImageDraw.Draw(im)
draw.rectangle((58, 54, width-58, height-54), outline=(176, 175, 166), width=3)
draw.text((110, 120), 'FIELD STATION / WEEKLY OBSERVATION', fill=(55, 60, 55))
draw.line((110, 158, width-110, 158), fill=(90, 95, 90), width=2)
draw.text((110, 208), 'Scanned attachment — words exist only in the image.', fill=(62, 62, 58))
draw.text((110, 252), 'ALPHA is intentionally not searchable on this page.', fill=(62, 62, 58))
draw.text((110, 340), 'Station       Water level       Condition', fill=(50, 55, 50))
draw.line((110, 368, width-110, 368), fill=(130, 130, 120), width=2)
for i, row in enumerate([
    'North Marsh     38.4 cm          stable',
    'Old Quarry      11.7 cm          low',
    'River Gate      43.2 cm          rising',
    'Willow Bend     26.9 cm          stable',
]):
    y = 402 + i * 56
    draw.text((110, y), row, fill=(62, 62, 58))
    draw.line((110, y+38, width-110, y+38), fill=(214, 212, 203), width=1)
draw.text((110, 760), 'Operator note: values and sites are fictional test data.', fill=(65, 65, 61))
# Tiny deterministic scan grain, avoiding external font or image inputs.
pix = im.load()
for y in range(0, height, 13):
    for x in range(0, width, 17):
        r, g, b = pix[x, y]
        pix[x, y] = (max(0, r-1), max(0, g-1), max(0, b-1))
png = BytesIO()
im.save(png, format='PNG', optimize=False, compress_level=9)

c = canvas.Canvas(str(out), pagesize=letter, pageCompression=1, invariant=1)
c.setTitle('Mixed text and scan fixture')
c.setAuthor('Swag Scope generated test data')
c.setSubject('One searchable report page and one raster-only scanned attachment')
c.setFont('Helvetica-Bold', 16)
c.drawString(72, 730, 'Field station weekly report')
c.setFont('Helvetica', 11)
c.drawString(72, 704, 'ALPHA marker is searchable on this page.')
c.drawString(72, 682, 'The next page is a scan with no text layer.')
c.drawString(72, 630, 'Generated fictional content for Swag Scope PDF coverage tests.')
c.showPage()
c.drawImage(ImageReader(BytesIO(png.getvalue())), 0, 0, width=letter[0], height=letter[1], preserveAspectRatio=True)
c.showPage()
c.save()
