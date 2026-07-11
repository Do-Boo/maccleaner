import Foundation
import AppKit

enum Shell {
    struct Result {
        let status: Int32
        let output: String
    }

    /// 일반 프로세스 실행
    @discardableResult
    static func run(_ executable: String, _ args: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        // GUI 앱은 PATH가 제한적이라 Homebrew 경로를 보강
        var env = ProcessInfo.processInfo.environment
        let path = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = path + ":/opt/homebrew/bin:/usr/local/bin"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Result(status: process.terminationStatus, output: String(data: data, encoding: .utf8) ?? "")
    }

    /// zsh를 통해 셸 명령 실행
    @discardableResult
    static func runShell(_ command: String) -> Result {
        run("/bin/zsh", ["-c", command])
    }

    /// 관리자 권한으로 셸 명령 실행 (macOS 암호 입력 창이 뜸)
    /// 반환값: 실패 시 오류 메시지, 성공 시 nil
    static func runAsAdmin(_ command: String) -> String? {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = NSAppleScript(source: "do shell script \"\(escaped)\" with administrator privileges")
        var errorInfo: NSDictionary?
        script?.executeAndReturnError(&errorInfo)
        if let errorInfo, let message = errorInfo[NSAppleScript.errorMessage] as? String {
            return message
        }
        return nil
    }
}
