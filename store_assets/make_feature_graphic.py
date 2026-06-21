from PIL import Image, ImageDraw, ImageFont

W, H = 1024, 500
BG = (0, 0, 0)
PANEL = (22, 22, 26)
STROKE = (42, 42, 50)
WHITE = (244, 244, 245)
MUTED = (161, 161, 170)

FONT_PATH = "assets/font/Urbanist/Urbanist-VariableFont_wght.ttf"


def font(size, weight=400):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_axes([weight])
    except Exception:
        pass
    return f


canvas = Image.new("RGB", (W, H), BG)
draw = ImageDraw.Draw(canvas)

# --- Left: rounded app-icon tile using the real logo ---
tile = 300
margin = 70
icon = Image.open("assets/branding/app_icon_primary.png").convert("RGB").resize((tile, tile), Image.LANCZOS)

radius = 64
mask = Image.new("L", (tile, tile), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, tile, tile], radius=radius, fill=255)

tile_y = (H - tile) // 2
# subtle panel/stroke so the black icon reads against the black background
draw.rounded_rectangle(
    [margin - 2, tile_y - 2, margin + tile + 2, tile_y + tile + 2],
    radius=radius + 2, fill=STROKE,
)
canvas.paste(icon, (margin, tile_y), mask)

# --- Right: app name + tagline ---
text_x = margin + tile + 70
name_font = font(96, 800)
tag_font = font(40, 500)

name = "Boomerang"
tag = "Share your moments."

nb = draw.textbbox((0, 0), name, font=name_font)
tb = draw.textbbox((0, 0), tag, font=tag_font)
nh = nb[3] - nb[1]
th = tb[3] - tb[1]
gap = 26
block_h = nh + gap + th
start_y = (H - block_h) // 2

draw.text((text_x, start_y - nb[1]), name, font=name_font, fill=WHITE)
draw.text((text_x, start_y + nh + gap - tb[1]), tag, font=tag_font, fill=MUTED)

out = "store_assets/play_feature_graphic_1024x500.png"
canvas.save(out, "PNG")
print("saved", out, canvas.size)
