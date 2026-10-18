#!/usr/bin/env python3
"""Convert local parish GeoJSON to small SVG paths, without source attributes.

Usage: python3 scripts/prepare_freguesia_map.py [lisboa-freguesias.geojson]
Only administrative outlines are retained. Analytical values remain in snapshots.
"""
import hashlib
import json
import math
from pathlib import Path
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]) if len(sys.argv) > 1 else root / 'data_sources/lisboa-freguesias.geojson'
data = json.loads(source.read_text())
features = data['features']

def rings(feature):
    geometry = feature['geometry']
    if geometry['type'] == 'Polygon':
        return geometry['coordinates']
    if geometry['type'] == 'MultiPolygon':
        return [ring for polygon in geometry['coordinates'] for ring in polygon]
    raise ValueError(f"Unsupported geometry: {geometry['type']}")

points = [point for feature in features for ring in rings(feature) for point in ring]
latitude = sum(p[1] for p in points) / len(points)
x_factor = math.cos(math.radians(latitude))
west, east = min(p[0] for p in points), max(p[0] for p in points)
south, north = min(p[1] for p in points), max(p[1] for p in points)
scale = 440 / max((east - west) * x_factor, north - south)
width, height = (east - west) * x_factor * scale + 16, (north - south) * scale + 16

def project(point):
    return ((point[0] - west) * x_factor * scale + 8, (north - point[1]) * scale + 8)

def simplify(points, tolerance=0.35):
    if len(points) <= 2:
        return points
    ax, ay = points[0]
    bx, by = points[-1]
    dx, dy = bx - ax, by - ay
    length = dx * dx + dy * dy
    distances = []
    for x, y in points[1:-1]:
        t = max(0, min(1, ((x - ax) * dx + (y - ay) * dy) / length)) if length else 0
        distances.append(math.hypot(x - ax - t * dx, y - ay - t * dy))
    distance = max(distances)
    if distance <= tolerance:
        return [points[0], points[-1]]
    index = distances.index(distance) + 1
    return simplify(points[:index + 1], tolerance)[:-1] + simplify(points[index:], tolerance)

paths = {}
for feature in features:
    name = feature['properties']['NOME'].strip()
    assert name not in paths, f'Duplicate parish: {name}'
    sections = []
    for ring in rings(feature):
        projected = [project(point) for point in ring]
        middle = len(projected) // 2
        simplified = simplify(projected[:middle + 1])[:-1] + simplify(projected[middle:])
        sections.append('M' + 'L'.join(f'{x:.1f},{y:.1f}' for x, y in simplified) + 'Z')
    paths[name] = ''.join(sections)
assert len(paths) == 24, f'Expected 24 parishes, found {len(paths)}'
output = {
    'source': 'Câmara Municipal de Lisboa — limites de freguesias',
    'source_url': 'https://gisapps.cm-lisboa.pt/arcgis/rest/services/SGPI_Open/LXSGPI_Temas/MapServer/4',
    'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
    'projection': 'Local equirectangular; north up; simplified at 0.35 SVG units',
    'view_box': f'0 0 {width:.1f} {height:.1f}',
    'paths': paths,
}
target = root / 'site/_data/freguesia_map.json'
target.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n')
print(f'Prepared {len(paths)} parish outlines: {target}')
