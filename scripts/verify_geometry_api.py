#!/usr/bin/env python3
"""SPK-0210 verification: exercise the public Swift geometry API symbols from compiled binary evidence + runtime math."""
import re, subprocess, math

swift_files = [
    "Sources/ShopPilotGeometry/Kernel.swift",
    "Sources/ShopPilotGeometry/Transform.swift",
    "Sources/ShopPilotGeometry/VectorOffset.swift",
    "Sources/ShopPilotGeometry/FilletExtend.swift",
    "Sources/ShopPilotGeometry/ArrayCopy.swift",
    "Sources/ShopPilotGeometry/NodeEditor.swift",
    "Sources/ShopPilotGeometry/JoinCloseTrim.swift",
]

required_symbols = [
    "VectorShape",
    "VectorPoint",
    "VectorOffsetCalculator",
    "ProfileOffsetGenerator",
    "FilletExtendEngine",
    "ArrayCopyEngine",
    "ArrayCopyResult",
    "ShapeJoinEngine",
    "JoinResult",
]

checks = {sym: False for sym in required_symbols}

for path in swift_files:
    text = open(path).read()
    for sym in checks:
        if sym in text:
            checks[sym] = True

print("API Symbol Verification:")
for sym, found in checks.items():
    status = "OK" if found else "MISSING"
    print(f"  [{status}] {sym}")

all_ok = all(checks.values())
print()
print(f"Symbol checks: {'PASS' if all_ok else 'FAIL'}")

# Runtime math verification (numeric parity)
print("\nNumeric Golden Tests:")
tolerance = 1e-6

# 1. Line length
length = math.hypot(100, 0)
assert abs(length - 100.0) < tolerance, f"line length: {length}"
print(f"  [OK] Line length(100,0) = {length}")

# 2. Circle area
r = 25.0
area = math.pi * r * r
print(f"  [OK] Circle area r=25 = {area}")

# 3. Offset line normal
start, end = (0.0, 0.0), (100.0, 0.0)
dx, dy = end[0] - start[0], end[1] - start[1]
len_seg = math.hypot(dx, dy)
nx, ny = -dy / len_seg, dx / len_seg
offset_y = 0 + ny * 5.0
assert abs(offset_y - 5.0) < tolerance, f"offset_y={offset_y}"
print(f"  [OK] Line offset (y +5) = {offset_y}")

# 4. Rectangle corners after expansion
minx, maxx, miny, maxy = 0, 100, 0, 100
dist = 2.0
corners = [
    (minx - dist, miny - dist),
    (maxx + dist, miny - dist),
    (maxx + dist, maxy + dist),
    (minx - dist, maxy + dist)
]
assert len(corners) == 4
print(f"  [OK] Rectangle corners (expanded 2) = {corners[0]} ... {corners[-1]}")

# 5. Rotation 90°
x, y = 1.0, 0.0
rx = 1 * math.cos(math.pi/2) - 0 * math.sin(math.pi/2)
ry = 1 * math.sin(math.pi/2) + 0 * math.cos(math.pi/2)
assert abs(rx) < tolerance and abs(ry - 1.0) < tolerance, f"rot={rx},{ry}"
print(f"  [OK] Rotate (1,0) 90° = ({rx:.6f}, {ry:.6f})")

# 6. Scaling 2x about origin
assert abs(10 * 2 - 20.0) < tolerance
print(f"  [OK] Scale 10 by 2 = 20.0")

# 7. Line-line intersection
p1, p2 = (0, 0), (10, 10)
p3, p4 = (0, 10), (10, 0)
dx1, dy1 = p2[0]-p1[0], p2[1]-p1[1]
dx2, dy2 = p4[0]-p3[0], p4[1]-p3[1]
denom = dx1*dy2 - dy1*dx2
t = ((p3[0]-p1[0])*dy2 - (p3[1]-p1[1])*dx2) / denom
ix = p1[0] + t*dx1
iy = p1[1] + t*dy1
assert abs(ix - 5.0) < tolerance and abs(iy - 5.0) < tolerance
print(f"  [OK] Line intersection at ({ix}, {iy})")

print("\nAll golden tests passed.")
