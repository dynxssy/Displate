import base64, io, sys
from pathlib import Path
from PIL import Image

root = Path(sys.argv[1])  # contains displate/, unload/, breeze/ with shot-*.png and icon.png
out = Path(sys.argv[2])
template = Path(sys.argv[3]).read_text()

def data_uri(path, max_width):
    image = Image.open(path).convert("RGBA")
    if image.width > max_width:
        image = image.resize((max_width, round(image.height * max_width / image.width)), Image.LANCZOS)
    buffer = io.BytesIO()
    image.save(buffer, "WEBP", quality=88, method=6)
    return "data:image/webp;base64," + base64.b64encode(buffer.getvalue()).decode()

values = {}
for app in ["displate", "unload", "breeze"]:
    folder = root / app
    values[f"{{{{{app.upper()}_LIGHT}}}}"] = data_uri(folder / "shot-light.png", 960)
    values[f"{{{{{app.upper()}_DARK}}}}"] = data_uri(folder / "shot-dark.png", 960)
    values[f"{{{{ICON_{app.upper()}}}}}"] = data_uri(folder / "icon.png", 160)

html = template
for key, value in values.items():
    assert key in html, key
    html = html.replace(key, value)
out.write_text(html)
print(f"wrote {out} ({len(html) / 1_000_000:.2f} MB)")
