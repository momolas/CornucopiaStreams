//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import CornucopiaCore
import Foundation
import CSocketHelper
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension Cornucopia.Streams {

    /// A connector for TCP.
    final class TCPConnector: BaseConnector {

        private let connectionQueue = DispatchQueue(label: "Cornucopia.Streams.TCPConnector", qos: .userInitiated)
        private var cancellationFlag: UnsafeMutablePointer<sig_atomic_t>? = nil
        private var pendingSocket: Int32? = nil

        override func connect(timeout: TimeInterval) async throws -> Cornucopia.Streams.StreamPair {

            let url = self.meta.url
            guard let host = url.host, !host.isEmpty else { throw Error.invalidUrl }
            guard let port = url.port, port > 0 else { throw Error.invalidUrl }

            // Convert timeout to milliseconds. 0.0 means no timeout (pass 0 to wait indefinitely)
            let timeoutMs: Int32
            if timeout <= 0 {
                timeoutMs = 0
            } else {
                let milliseconds = timeout * 1_000
                if milliseconds >= Double(Int32.max) {
                    timeoutMs = .max
                } else {
                    timeoutMs = Int32(milliseconds)
                }
            }

            return try await self.connectSocket(to: host, port: port, timeoutMilliseconds: timeoutMs)
        }

        override func cancel() {
            if let flag = self.cancellationFlag {
                flag.pointee = 1
            }
            if let socket = self.pendingSocket {
                _ = csocket_close(socket)
                self.pendingSocket = nil
            }
        }

        private func connectSocket(to host: String, port: Int, timeoutMilliseconds: Int32) async throws -> Cornucopia.Streams.StreamPair {

            let flagPointer = UnsafeMutablePointer<sig_atomic_t>.allocate(capacity: 1)
            flagPointer.initialize(to: 0)
            self.cancellationFlag = flagPointer

            defer {
                flagPointer.deinitialize(count: 1)
                flagPointer.deallocate()
                self.cancellationFlag = nil
            }

            return try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { continuation in
                    self.connectionQueue.async { [weak self] in
                        guard let self = self else {
                            continuation.resume(throwing: Cornucopia.Streams.Error.connectionCancelled)
                            return
                        }
                        host.withCString { cHost in
                            let fd = csocket_connect(cHost, Int32(port), timeoutMilliseconds, flagPointer)
                            if fd >= 0 {
                                self.pendingSocket = fd
                                let inputHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
                                let outputHandle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
                                let inputStream = FileHandleInputStream(fileHandle: inputHandle)
                                let outputStream = FileHandleOutputStream(fileHandle: outputHandle)
                                self.pendingSocket = nil
                                continuation.resume(returning: (inputStream, outputStream))
                            } else {
                                self.pendingSocket = nil
                                switch fd {
                                    case -1:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.unableToConnect("\(host) not found"))
                                    case -2:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.unableToConnect("Can't connect via TCP to \(host):\(port) (select failed)"))
                                    case -3:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.unableToConnect("Connection to \(host):\(port) timed out"))
                                    case -4:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.unableToConnect("Can't connect via TCP to \(host):\(port) (socket error)"))
                                    case -5:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.connectionCancelled)
                                    default:
                                        continuation.resume(throwing: Cornucopia.Streams.Error.unableToConnect("Can't connect via TCP to \(host):\(port)"))
                                }
                            }
                        }
                    }
                }
            }, onCancel: {
                flagPointer.pointee = 1
                if let socket = self.pendingSocket {
                    _ = csocket_close(socket)
                    self.pendingSocket = nil
                }
            })
        }

#if DEBUG
        deinit {
            print("\(self) destroyed")
        }
#endif
    }
}
