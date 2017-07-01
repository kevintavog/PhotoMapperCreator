import Foundation

class DataReader
{
    let data: NSData
    var offset: Int

    init(data: NSData)
    {
        self.data = data
        self.offset = 0
    }

    func readString(length: UInt32) -> String
    {
        let length = Int(length)
        let subData = data.subdata(with: NSMakeRange(offset, length))
        offset += length
        return String(data: subData, encoding: String.Encoding.utf8)!
    }

    func readLengthAndString() -> String
    {
        let length = Int(readUInt32()) - 4
        let subData = data.subdata(with: NSMakeRange(offset, length))
        offset += length
        return String(data: subData, encoding: String.Encoding.utf8)!
    }

    func readUInt16() -> UInt16
    {
        let val: UInt16 = read()
        return val.bigEndian
    }

    func readUInt32() -> UInt32
    {
        let val: UInt32 = read()
        return val.bigEndian
    }

    func readUInt64() -> UInt64
    {
        let val: UInt64 = read()
        return val.bigEndian
    }

    func read<T>() -> T
    {
        let size = MemoryLayout<T>.size
        let subData = data.subdata(with: NSMakeRange(offset, size))
        offset += size
        return subData.withUnsafeBytes { (ptr: UnsafePointer<T>) -> T in return ptr.pointee }
    }
}
