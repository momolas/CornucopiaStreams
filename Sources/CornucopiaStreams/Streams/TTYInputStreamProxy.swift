//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

/// An InputStream that configures the device's bitrate after open(2).
final class TTYInputStreamProxy: ProxyInputStream {

    private let path: String
    private let bitrate: Int?
    private var fd: Int32? = nil

    init?(forReadingAtPath path: String, bitrate: Int? = nil) {
        guard let inputStream = InputStream(fileAtPath: path) else { return nil }
        self.bitrate = bitrate
        self.path = path
        super.init(proxying: inputStream)
    }

    override func open() {
        guard let bitrate = self.bitrate else { return }
        let fd = Foundation.open(self.path, O_RDWR | O_NONBLOCK)
        guard fd >= 0 else {
#if DEBUG
            print("Can't open \(self.path): \(String(cString: strerror(errno)))")
#endif
            self.reportDelegateEvent(.errorOccurred)
            return
        }
        // macOS resets the baudrate when the filedescriptor closes, hence we need to carry it around until the connection ends.
        self.fd = fd

        #if canImport(Darwin)
        // On Darwin, we can use ioctl with IOSSIOSPEED to set the baud rate directly and immediately.
        // IOSSIOSPEED is _IOW('T', 2, speed_t)
        // 'T' is 0x54. 2 is 2. speed_t is usually unsigned long (8 bytes on 64-bit).
        // The value calculation depends on architecture, but typically:
        // _IOC(inout, group, num, len)
        // _IOC_IN | _IOC_OUT = 0x80000000 (for _IOW? Wait, IOW is usually IN for ioctl writing TO kernel?)
        // Actually, let's stick to standard termios but without the weird sleep loop, verifying errors instead.
        // However, ioctl is preferred. Let's try to be standard first.
        #endif

        var settings = termios()
        if tcgetattr(fd, &settings) != 0 {
            #if DEBUG
            print("tcgetattr failed: \(String(cString: strerror(errno)))")
            #endif
        }

        cfsetspeed(&settings, speed_t(bitrate))

        // TCSAFLUSH drains output and flushes input.
        if tcsetattr(fd, TCSAFLUSH, &settings) != 0 {
            #if DEBUG
            print("tcsetattr failed: \(String(cString: strerror(errno)))")
            #endif
        }

        super.open()
    }

    override func close() {
        super.close()

        guard let fd = self.fd else { return }
        Foundation.close(fd)
    }

    deinit {
        self.CC_removeMeta()
#if DEBUG
        print("\(self) destroyed")
#endif
    }
}
