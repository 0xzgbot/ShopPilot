import Foundation
import ShopPilotCore

@main
struct ShopPilotGoldenPathMain {
    static func main() async {
        print("=== ShopPilot Demoable Golden Path ===")
        do {
            let result = try await DemoableGoldenPath.run()
            print(result.summary)
            print("gcodeLines=\(result.gcodeLineCount) streamed=\(result.streamedLines) completed=\(result.completed)")
            if result.completed && result.gcodeLineCount > 0 {
                print("RESULT: PASS")
                exit(0)
            } else {
                print("RESULT: FAIL (incomplete stream)")
                exit(1)
            }
        } catch {
            print("RESULT: FAIL — \(error.localizedDescription)")
            exit(1)
        }
    }
}
