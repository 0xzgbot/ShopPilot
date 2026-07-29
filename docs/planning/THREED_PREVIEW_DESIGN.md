# ShopPilot — 3D Relief Preview in SwiftUI (SceneKit/Metal)

**Date:** 2026-07-28  
**Status:** Living design doc — update as implementation progresses.

---

## Overview

The 3D relief preview renders a mesh-based model on the canvas using SceneKit with Metal rendering backend. This provides real-time rotation, zoom, pan, and lighting interaction for viewing relief geometry before generating toolpaths.

---

## Architecture

### SceneView Wrapper

```swift
import SwiftUI
import SceneKit

struct ReliefSceneView: NSViewRepresentable {
    let scene: SCNScene
    @Binding var selectedToolpathId: UUID?
    
    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.autoenablesDefaultLighting = true
        view.allowsCameraControl = true  // orbit, zoom, pan
        view.showsStatistics = false
        return view
    }
    
    func updateNSView(_ nsView: SCNView, context: Context) {
        nsView.scene = scene
    }
}
```

### Camera Controls

- **Orbit:** Left-click drag (SceneKit default)
- **Zoom:** Scroll wheel or pinch (SceneKit default)  
- **Pan:** Right-click drag or Ctrl+drag
- **Reset view:** Button in toolbar → `cameraNode.position = SCNVector3(0, 0, distance)`

### Lighting Setup

```swift
func setupLighting(scene: SCNScene) {
    // Key light — top-right-front
    let keyLight = SCNLight()
    keyLight.type = .directional
    keyLight.color = NSColor.white
    keyLight.intensity = 800
    
    let keyNode = SCNNode()
    keyNode.light = keyLight
    keyNode.eulerAngles = SCNVector3(-Float.pi/4, Float.pi/6, 0)
    scene.rootNode.addChildNode(keyNode)
    
    // Fill light — softer, opposite side
    let fillLight = SCNLight()
    fillLight.type = .directional
    fillLight.intensity = 300
    
    let fillNode = SCNNode()
    fillNode.light = fillLight
    fillNode.eulerAngles = SCNVector3(Float.pi/6, -Float.pi/4, 0)
    scene.rootNode.addChildNode(fillNode)
    
    // Rim light — back edge for depth perception
    let rimLight = SCNLight()
    rimLight.type = .directional
    rimLight.intensity = 200
    
    let rimNode = SCNNode()
    rimNode.light = rimLight
    rimNode.eulerAngles = SCNVector3(0, Float.pi, 0)
    scene.rootNode.addChildNode(rimNode)
}
```

### Mesh Rendering

- **STL/OBJ import:** Parse mesh vertices/faces into `SCNGeometry` sources
- **Material:** Phong shading with diffuse color from material library (wood grain, plastic, metal)
- **Z-height visualization:** Optional false-color overlay showing elevation (blue = low, red = high)

```swift
func createMeshGeometry(vertices: [SCNVector3], normals: [SCNVector3], indices: [UInt32]) -> SCNGeometry {
    let source = SCNGeometrySource(vertices: vertices)
    let normalSource = SCNGeometrySource(normals: normals)
    
    let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
    
    return SCNGeometry(sources: [source, normalSource], elements: [element])
}
```

### Toolpath Overlay

- **Active toolpath:** Render as semi-transparent wireframe overlay on the mesh
- **Color coding:** Different colors for roughing (green), finishing (blue), engraving (orange)
- **Visibility toggle:** Checkbox in layer tree to show/hide toolpath preview

---

## Performance Considerations

### Level of Detail (LOD)

- **High LOD:** Full mesh resolution when zoomed in close (< 10mm view)
- **Medium LOD:** Simplified mesh (50% vertex reduction) at medium zoom
- **Low LOD:** Coarse proxy mesh for orbit/pan when far away (> 100mm view)

### Caching

- Pre-compute geometry on toolpath generation, not during interaction
- Cache SceneKit scene graph per material + mesh combination
- Invalidate cache when mesh or material changes

### Threading

- Mesh parsing (STL/OBJ) runs on background thread
- SceneKit rendering is single-threaded — keep updates off the main thread where possible
- Use `SCNTransaction` for animated camera transitions

---

## Integration with Stage System

The 3D preview appears in:

1. **Design stage:** View imported vectors as 2D + optional 3D preview overlay
2. **Model stage:** Full SceneKit view for component manipulation (extrude, combine, sculpt)
3. **Cut stage:** Toolpath simulation with animated camera following tool position

### Cut Stage Simulation

```swift
func animateToolpath(scene: SCNScene, toolpath: Toolpath) {
    let toolNode = SCNNode(geometry: cylinderGeometry(radius: 2))
    scene.rootNode.addChildNode(toolNode)
    
    let animation = CAKeyframeAnimation(keyPath: "position")
    animation.values = toolpath.waypoints.map { SCNVector3ToNSPoint($0) }
    animation.calculationMode = .cubic
    animation.duration = Double(toolpath.estimatedTime)
    animation.isRemovedOnCompletion = false
    
    toolNode.add(animation, forKey: "moveAlongPath")
}
```

---

## Metal Backend Notes

SceneKit uses Metal by default on macOS 10.15+. For custom rendering effects (e.g., real-time shading previews), we can drop to `MTKView` directly:

- **Custom shader:** Fragment shader for false-color elevation mapping
- **Compute kernel:** Real-time mesh simplification on GPU
- **Fallback:** SceneKit provides sufficient performance for v1.0; Metal direct access is a v1.1+ enhancement

---

## Notes

- No Vectric proprietary assets or rendering algorithms used
- SceneKit API surface documented in Apple Developer documentation
- All mesh parsing (STL/OBJ) implemented from open format specifications
- False-color elevation visualization uses standard gradient mapping, not derived from Aspire/VCarve implementations
