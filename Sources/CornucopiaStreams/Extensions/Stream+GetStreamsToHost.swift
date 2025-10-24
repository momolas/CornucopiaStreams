//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation
import CoreFoundation
import CSocketHelper

public extension Stream {

    /// Create an input/output stream pair bound to the specified TCP host.
    class func CC_getStreamsToHost(with name: String, port: Int) -> (InputStream?, OutputStream?) {

        var inputStream: InputStream?
        var outputStream: OutputStream?
#if os(watchOS)
        Self.getStreamsToHost(withName: name, port: port, inputStream: &inputStream, outputStream: &outputStream)
#else
        let fileDescriptor = name.withCString { cString in
            csocket_connect(cString, Int32(port), 1_000, nil)
        }
        if fileDescriptor >= 0 {
            let fih = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
            let foh = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: false)
            inputStream = FileHandleInputStream(fileHandle: fih)
            outputStream = FileHandleOutputStream(fileHandle: foh)
        }
#endif
        return (inputStream, outputStream)
    }
}
