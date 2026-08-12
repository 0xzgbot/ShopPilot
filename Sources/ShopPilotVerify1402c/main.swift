import Foundation
import Metal
import ShopPilotCore

// SPK-1402c — Metal honesty: checkMetalAvailability() must reflect a real
// MTLDevice query, not a hardcoded `true`, and isMetalAvailable must be
// false when Metal is disabled in the preview configuration.

enum VerifyError: Error {
    case failed(String)
}

func expect(_ condition: Bool, _ message: String) throws {
    if !condition {
        throw VerifyError.failed(message)
    }
}

func main() throws {
    // 1. The availability check must agree with a real device query on this machine.
    let checked = MetalPreviewRenderer.checkMetalAvailability()
    let devicePresent = MTLCreateSystemDefaultDevice() != nil
    try expect(
        checked == devicePresent,
        "checkMetalAvailability() returned \(checked) but MTLCreateSystemDefaultDevice() != nil is \(devicePresent)"
    )
    print("✓ checkMetalAvailability() == \(checked) matches MTLCreateSystemDefaultDevice() != nil == \(devicePresent)")

    // 2. isMetalAvailable must be false when enableMetal is false, regardless of hardware.
    let configuration = MetalPreviewConfiguration(enableMetal: false)
    let viewport = ViewportState.fitToBounds(
        (minX: 0, minY: 0, maxX: 10, maxY: 10),
        viewportWidth: 800,
        viewportHeight: 600
    )
    let renderer = MetalPreviewRenderer(configuration: configuration, initialViewport: viewport)
    try expect(
        renderer.isMetalAvailable == false,
        "isMetalAvailable should be false when enableMetal is false, got \(renderer.isMetalAvailable)"
    )
    print("✓ isMetalAvailable == \(renderer.isMetalAvailable) when enableMetal == false")

    print("1402c: PASS — Metal availability is honest")
}

do {
    try main()
} catch {
    print("1402c: FAIL — \(error)")
    exit(1)
}
