from PIL import Image
import os

img = Image.open("/Users/anvirbariana/.gemini/antigravity/brain/918730fb-ca68-421e-b353-efd15ca42890/.user_uploaded/media_1789062689820.png")
img = img.convert("RGBA")

# Use getbbox() on slices or just simple scanning
width, height = img.size
pixels = img.load()

# Find contiguous regions of non-transparent pixels
visited = set()
boxes = []

def fill(start_x, start_y):
    stack = [(start_x, start_y)]
    min_x, min_y, max_x, max_y = start_x, start_y, start_x, start_y
    while stack:
        x, y = stack.pop()
        if (x, y) in visited: continue
        visited.add((x, y))
        
        if x < min_x: min_x = x
        if x > max_x: max_x = x
        if y < min_y: min_y = y
        if y > max_y: max_y = y
        
        for dx, dy in [(-1,0), (1,0), (0,-1), (0,1), (-1,-1), (1,1), (-1,1), (1,-1)]:
            nx, ny = x+dx, y+dy
            if 0 <= nx < width and 0 <= ny < height:
                if (nx, ny) not in visited:
                    r, g, b, a = pixels[nx, ny]
                    if a > 10:
                        stack.append((nx, ny))
    return min_x, min_y, max_x, max_y

for y in range(height):
    for x in range(width):
        if (x, y) not in visited:
            r, g, b, a = pixels[x, y]
            if a > 10:
                bbox = fill(x, y)
                boxes.append(bbox)
            else:
                visited.add((x, y))

# Filter small boxes
boxes = [b for b in boxes if (b[2]-b[0]) > 10 and (b[3]-b[1]) > 10]

top_row = []
bottom_row = []
for b in boxes:
    if b[1] < height / 2:
        top_row.append(b)
    else:
        bottom_row.append(b)

top_row = sorted(top_row, key=lambda b: b[0])
bottom_row = sorted(bottom_row, key=lambda b: b[0])

print(f"Top row sprites: {len(top_row)}")
print(f"Bottom row sprites: {len(bottom_row)}")

out_dir = "assets/sprites"
os.makedirs(out_dir, exist_ok=True)

enemy_names = ["basic_virus", "trojan_horse", "worm1", "worm2", "worm3", "ransomware", "spyware", "rootkit", "ddos_bot"]
tower_names = ["antivirus_cannon", "data_spike", "emp_tower", "sniper_node", "quarantine_zone", "firewall_beam", "overclock_hub"]

for i, b in enumerate(top_row):
    cropped = img.crop((b[0], b[1], b[2]+1, b[3]+1))
    name = enemy_names[i] if i < len(enemy_names) else f"enemy_{i}"
    cropped.save(f"{out_dir}/{name}.png")
    
for i, b in enumerate(bottom_row):
    cropped = img.crop((b[0], b[1], b[2]+1, b[3]+1))
    name = tower_names[i] if i < len(tower_names) else f"tower_{i}"
    cropped.save(f"{out_dir}/{name}.png")

print("Done slicing!")
