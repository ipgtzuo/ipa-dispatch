import Foundation

enum Shell {
    static func captureData(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments
                if let environment { process.environment = environment }
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func capture(
        _ executable: String,
        _ arguments: [String],
        environment: [String: String]? = nil
    ) async throws -> String {
        let data = try await captureData(executable, arguments, environment: environment)
        return String(decoding: data, as: UTF8.self)
    }
}

private final class LineBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private let isError: Bool
    private let onLine: (String, Bool) -> Void

    init(isError: Bool, onLine: @escaping (String, Bool) -> Void) {
        self.isError = isError
        self.onLine = onLine
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer += String(decoding: data, as: UTF8.self)
        var lines: [String] = []
        while let range = buffer.range(of: "\n") {
            var line = String(buffer[..<range.lowerBound])
            if line.hasSuffix("\r") { line.removeLast() }
            lines.append(line)
            buffer = String(buffer[range.upperBound...])
        }
        lock.unlock()
        for line in lines where !line.isEmpty {
            onLine(line, isError)
        }
    }

    func flush() {
        lock.lock()
        let line = buffer
        buffer = ""
        lock.unlock()
        if !line.isEmpty { onLine(line, isError) }
    }
}

enum ProcessRunner {
    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        onLine: @escaping (String, Bool) -> Void
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let outBuffer = LineBuffer(isError: false, onLine: onLine)
        let errBuffer = LineBuffer(isError: true, onLine: onLine)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                outBuffer.append(data)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                errBuffer.append(data)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if let rest = try? outPipe.fileHandleForReading.readToEnd() {
                    outBuffer.append(rest)
                }
                if let rest = try? errPipe.fileHandleForReading.readToEnd() {
                    errBuffer.append(rest)
                }
                outBuffer.flush()
                errBuffer.flush()
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
