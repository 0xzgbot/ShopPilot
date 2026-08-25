import ShopPilotCore
let v = VectorPath(name: "o", points: [VectorPoint(x: 0, y: 0), VectorPoint(x: 30, y: 0), VectorPoint(x: 30, y: 30), VectorPoint(x: 60, y: 30)], isClosed: false)
let r = VCarveEngine.compute(vectors: [v], params: VCarveParams(medialAxisPass: true))
for l in r.gcodeLines.prefix(8) { print("[\(l)]") }
print("hasM3:", r.gcodeLines.contains { $0.hasPrefix("M3 S") })
