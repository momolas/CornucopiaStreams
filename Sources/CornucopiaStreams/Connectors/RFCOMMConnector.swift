//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
#if canImport(IOBluetooth) && !targetEnvironment(macCatalyst)
import CornucopiaCore
import IOBluetooth
import Foundation

fileprivate let logger = Cornucopia.Core.Logger()

extension Cornucopia.Streams {

    /// A connector for MFi-program compliant devices external accessories.
    final class RFCOMMConnector: BaseConnector {

        static let forbiddenCharsetAddress = CharacterSet(charactersIn: "0123456789ABCDEF-:").inverted
        static let numberOfCharactersForAddress = 17

        private var bridge: RFCOMMBridge? = nil

        typealias ConnectionContinuation = CheckedContinuation<StreamPair, Swift.Error>
        var continuation: ConnectionContinuation? = nil
        var device: IOBluetoothDevice? = nil
        var channelID: BluetoothRFCOMMChannelID = 0

        /// Connect
        override func connect(timeout: TimeInterval) async throws -> StreamPair {

            // Note: RFCOMM connection logic handles its own timeouts internally
            try await self.cancellationCheckPoint()
            let url = self.meta.url
            guard let host = url.host?.uppercased() else { throw Error.invalidUrl }
            guard host.count == Self.numberOfCharactersForAddress, host.rangeOfCharacter(from: Self.forbiddenCharsetAddress) == nil else { throw Error.invalidUrl }

            try await self.cancellationCheckPoint()
            guard let device = IOBluetoothDevice(addressString: host) else { throw Error.unableToConnect("\(host) not found") }
            if let port = url.port { self.channelID = BluetoothRFCOMMChannelID(port) }

            try await self.cancellationCheckPoint()
            let sppServiceUUID = IOBluetoothSDPUUID.uuid32(kBluetoothSDPUUID16ServiceClassSerialPort.rawValue)
            guard let sppServiceRecord = device.getServiceRecord(for: sppServiceUUID) else { throw Error.unableToConnect("\(host) does not provide RFCOMM") }
            try await self.cancellationCheckPoint()
            guard sppServiceRecord.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { throw Error.unableToConnect("\(host) does not have an RFCOMM channel id") }

            try await self.cancellationCheckPoint()
            let bridge = RFCOMMBridge(forDevice: device, channelID: channelID)
            self.bridge = bridge
            let inputStream = RFCOMMChannelInputStream(with: bridge)
            let outputStream = RFCOMMChannelOutputStream(with: bridge)
            try await self.cancellationCheckPoint()
            return (inputStream, outputStream)
        }

        override func cancel() {
            self.bridge?.closeChannel()
            self.bridge = nil
        }

#if DEBUG
        deinit {
            print("\(self) destroyed")
        }
#endif
    }
}

private extension Cornucopia.Streams.RFCOMMConnector {

    @inline(__always)
    func cancellationCheckPoint() async throws {
        if Task.isCancelled { throw Cornucopia.Streams.Error.connectionCancelled }
        await Task.yield()
        if Task.isCancelled { throw Cornucopia.Streams.Error.connectionCancelled }
    }
}
#endif
