"""生成 App 图标（1024x1024）：渐变底 + 时钟环 + 绿色对勾徽标。"""
from PIL import Image, ImageDraw
import os

SIZE = 1024
TOP = (74, 128, 247)
BOTTOM = (30, 76, 214)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


img = Image.new("RGB", (SIZE, SIZE), TOP)
draw = ImageDraw.Draw(img)

# 竖向渐变
for y in range(SIZE):
    t = y / (SIZE - 1)
    draw.line([(0, y), (SIZE, y)], fill=lerp(TOP, BOTTOM, t))

# 时钟环
cx, cy, r = 470, 480, 292
draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255), width=62)

# 指针
draw.line([(cx, cy), (cx, cy - 166)], fill=(255, 255, 255), width=58)
draw.line([(cx, cy), (cx + 130, cy + 44)], fill=(255, 255, 255), width=58)
draw.ellipse([cx - 34, cy - 34, cx + 34, cy + 34], fill=(255, 255, 255))

# 对勾徽标
bx, by, br = 792, 792, 148
draw.ellipse([bx - br, by - br, bx + br, by + br], fill=(52, 199, 89))
draw.line([(bx - 64, by + 2), (bx - 14, by + 56), (bx + 70, by - 50)],
          fill=(255, 255, 255), width=40, joint="curve")

out_dir = os.path.join(os.path.dirname(__file__), "..", "Sources", "Resources",
                       "Assets.xcassets", "AppIcon.appiconset")
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "icon-1024.png")
img.save(out_path, "PNG")
print("saved", os.path.abspath(out_path), img.size)
