import Foundation

fileprivate struct Location {
    var latitude: Double
    var longitude: Double
}

open class VideoMetadata
{
    fileprivate var fileHandle: FileHandle! = nil
    fileprivate var fileLength: UInt64! = 0

    fileprivate var rootAtoms = [VideoAtom]()

    fileprivate var moovData = [String: String]()
    fileprivate var uuidData = [String: String]()
    fileprivate var xmpAtomData = [String: String]()

    fileprivate var xmpDate: Date? = nil

    open var hasLocation: Bool {
        return videoLocation != nil
    }

    fileprivate var videoLocation: Location? = nil
    open var videoLatitude: Double? { return videoLocation?.latitude }
    open var videoLongitude: Double? { return videoLocation?.longitude }


    public init?(_ filename: String)
    {
        fileHandle = FileHandle(forReadingAtPath: filename)
        if fileHandle == nil {
            return nil
        }

        defer {
            fileHandle.closeFile() 
            fileHandle = nil
        }

        do {
            let attr : NSDictionary? = try FileManager.default.attributesOfItem(atPath: filename) as NSDictionary?
            if attr != nil {
                fileLength = attr!.fileSize()
            }
        } catch {
            return nil
        }

        parse()
    }

    deinit
    {
        if fileHandle != nil {
            fileHandle.closeFile()
        }
    }

    fileprivate func parse()
    {
        // Parse the top-level atoms; we'll drill down as needed later
        var offset: UInt64 = 0
        if let firstAtom = nextAtom(offset) {
            rootAtoms.append(firstAtom)
            offset += firstAtom.length
            while offset < fileLength {
                fileHandle.seek(toFileOffset: offset)
                if let atom = nextAtom(offset) {
                    rootAtoms.append(atom)
                    parseAtom(offset + 8, atomLength: atom.length, children: &atom.children)
                    offset += atom.length
                }
                else {
                    print("Failed reading atom at \(offset)")
                    break
                }
            }
        }

        parseUuidAtom()
        parseMetaAtom()
        parseXmpAtom()


        // Determine the location
        if !hasLocation {
            videoLocation = getLocationFrom(uuidData)
        }

        if !hasLocation {
            videoLocation = getLocationFrom(xmpAtomData)
        }

        if !hasLocation {
            if let moovLocation = moovData["com.apple.quicktime.location.ISO6709"] {
                do {
                    let regex = try NSRegularExpression(pattern: "([\\+-]\\d+\\.\\d+)", options: .caseInsensitive)
                    let matches = regex.matches(in: moovLocation, options: .withoutAnchoringBounds, range: NSMakeRange(0, moovLocation.characters.count))
                    if matches.count >= 2 {
                        if let latitude = Double(moovLocation.substringWithRange(matches[0].range)) {
                            if let longitude = Double(moovLocation.substringWithRange(matches[1].range)) {
                                videoLocation = Location(latitude: latitude, longitude: longitude)
                            }
                        }
                    }

                } catch let error {
                    print("Error parsing moov location (\(moovLocation)): \(error)")
                }
            }
        }
    }

    fileprivate func getLocationFrom(_ data: [String:String]) -> Location?
    {
        if let dataLatitude = data["GPSLatitude"] {
            if let dataLongitude = data["GPSLongitude"] {

                let latMatches = parseUuidLatLong(dataLatitude)
                let lonMatches = parseUuidLatLong(dataLongitude)

                var latitude = convertToGeo(latMatches[0], minutesAndSeconds: latMatches[1])
                var longitude = convertToGeo(lonMatches[0], minutesAndSeconds: lonMatches[1])

                if latMatches[2] == "S" {
                    latitude = latitude * -1.0
                }

                if lonMatches[2] == "W" {
                    longitude = longitude * -1.0
                }
                return Location(latitude: latitude, longitude: longitude)
            }
        }

        return nil
    }

    fileprivate func parseUuidAtom()
    {
        if let uuidAtom = getAtom(rootAtoms, atomPath: ["uuid"]) {

            // The atom data is 16 bytes of unknown data followed by XML
            let uuidReader = DataReader(data: getData(uuidAtom) as NSData)
            if uuidReader.data.length >= 56 {
                // Skip the 16 bytes of unknown data
                let _ = uuidReader.readUInt64()
                let _ = uuidReader.readUInt64()

                // The remaining is xml - atom length - 4 bytes for length - 4 bytes for type - 16 bytes unknown
                let xmlString = uuidReader.readString(length: UInt32(uuidAtom.length - 4 - 4 - 16))
                uuidData = parseXml(xmlString)
            }
        }
    }

    fileprivate func parseXmpAtom()
    {
        if let xmpAtom = getAtom(rootAtoms, atomPath: ["moov", "udta", "XMP_"]) {
            let xmpReader = DataReader(data: getData(xmpAtom) as NSData)
            let xmlString = xmpReader.readString(length: UInt32(xmpAtom.length - 4 - 4))
            xmpAtomData = parseXml(xmlString)
        }
    }

    fileprivate func parseMetaAtom()
    {
        if let keysAtom = getAtom(rootAtoms, atomPath: ["moov", "meta", "keys"]) {
            if let ilstAtom = getAtom(rootAtoms, atomPath: ["moov", "meta", "ilst"]) {

                // Keys are easy - a count of all keys, each item is a length/string combo
                let keyReader = DataReader(data: getData(keysAtom) as NSData)
                let keyCount = Int(keyReader.readUInt64())
                var keys = [String]()
                for _ in 1...keyCount {
                    let fullKeyName = keyReader.readLengthAndString()
                    // Skip "mdta'
                    let keyName = fullKeyName.substring(from: fullKeyName.characters.index(fullKeyName.startIndex, offsetBy: 4))
                    keys.append(keyName)
                }

                // Values are more complex, each element is:
                //      4 bytes     - Unknown
                //      4 bytes     - Index
                //      4 bytes     - length
                //      4 bytes     - 'd' 'a' 't' 'a'
                //      8 bytes     - Unknown, possibly the type
                //      remaining   - data (dataLength - 16)
                let valueReader = DataReader(data: getData(ilstAtom) as NSData)
                var values = [String](repeating: "", count: Int(keyCount))
                for _ in 1...keyCount {
                    let _ = valueReader.readUInt32()                    // Unknown
                    let index = valueReader.readUInt32()
                    let dataLength = valueReader.readUInt32()
                    let _ = valueReader.readUInt32()                    // 'd' 'a' 't' 'a'
                    let _ = valueReader.readUInt64()                    // Unknown, possibly type
                    let value = valueReader.readString(length: dataLength - 16)

                    values.insert(value, at: Int(index - 1))
                }


                for count in 0..<keyCount {
                    moovData[keys[count]] = values[count]
                }
            }
        }
    }

    fileprivate func logTree(_ atom: VideoAtom, parent: String)
    {
        print("\(parent) offset: \(atom.offset), length: \(atom.length)")
        let path = "\(parent)\\\(atom.type)"
        print("\(path) children are:")
        logTreeChildren(atom, parent: path)
    }

    fileprivate func logTreeChildren(_ atom: VideoAtom, parent: String)
    {
        if atom.children.count == 0 {
            parseAtom(atom.offset + 8, atomLength: atom.length, children: &atom.children)
        }

        for child in atom.children {
            print("\(parent)\\\(child.type), @\(child.offset) for \(child.length)")
        }
    }

    fileprivate func getAtom(_ children: [VideoAtom], atomPath: [String]) -> VideoAtom?
    {
        for child in children {
            if child.type == atomPath[0] {
                if atomPath.count == 1 {
                    return child
                } else {
                    parseAtom(child.offset + 8, atomLength: child.length, children: &child.children)
                    return getAtom(child.children, atomPath: Array(atomPath[1...atomPath.count - 1]))
                }
            }
        }

        #if DEBUG_ATOMS
        var childNames = [String]()
        for child in children {
            childNames.append(child.type)
        }

        print("Unable to find '\(atomPath)' in \(childNames)")
        #endif

        return nil
    }

    fileprivate func parseXml(_ xmlString: String) -> [String:String]
    {
        var data = [String:String]()
        do {
            let xmlDoc = try XMLDocument(xmlString: xmlString, options: 0)

            // Add namespaces to get xpath to work
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "exif", stringValue: "http://ns.adobe.com/exif/1.0/") as! XMLNode)
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "xmp", stringValue: "http://ns.adobe.com/xap/1.0/") as! XMLNode)
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "dc", stringValue: "http://purl.org/dc/elements/1.1/") as! XMLNode)
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "rdf", stringValue: "http://www.w3.org/1999/02/22-rdf-syntax-ns#") as! XMLNode)


            let exifNodes = try xmlDoc.nodes(forXPath: "//exif:*")
            for node in exifNodes {
                data[node.localName!] = node.stringValue!
            }

            let xmpNodes = try xmlDoc.nodes(forXPath: "//xmp:CreateDate")
            for node in xmpNodes {
                data[node.localName!] = node.stringValue!
            }

        } catch let error {
            print("Exception parsing xml: \(error)\n\"\(xmlString)\"")
        }
        return data
    }

    fileprivate func parseAtom(_ atomOffset: UInt64, atomLength: UInt64, children: inout [VideoAtom])
    {
        let atomEnd = atomOffset + atomLength
        var offset = atomOffset

        fileHandle.seek(toFileOffset: offset)
        if let firstAtom = nextAtom(offset) {
            children.append(firstAtom)

            offset += firstAtom.length
            while offset < fileLength && offset < atomEnd {
                fileHandle.seek(toFileOffset: offset)
                if let atom = nextAtom(offset) {
                    children.append(atom)

                    if atom.length == 0 {
                        break
                    }

                    offset += atom.length
                }
                else {
                    print("Failed reading atom at \(offset)")
                    break
                }
            }
        }
    }

    fileprivate func nextAtom(_ offset: UInt64) -> VideoAtom?
    {
        let data = fileHandle!.readData(ofLength: 4)
        if data.count == 0 {
            return nil
        }

        var length: UInt32 = 0
        (data as NSData).getBytes(&length, length: 4)
        if length == 0 {
            return nil
        }

        let atomType = fileHandle.readData(ofLength: 4)
        if let type = String(data: atomType, encoding: String.Encoding.utf8) {
            return VideoAtom(type: type, offset: offset, length: UInt64(length.byteSwapped))
        }

        return nil
    }

    fileprivate func getData(_ atom: VideoAtom) -> Data
    {
        fileHandle.seek(toFileOffset: atom.offset + 8)
        return fileHandle.readData(ofLength: Int(atom.length - 8))
    }

    fileprivate func convertToGeo(_ degrees: String, minutesAndSeconds: String) -> Double
    {
        if let degreesNumber = Double(degrees) {
            if let minutesAndSecondsNumber = Double(minutesAndSeconds) {
                return degreesNumber + (minutesAndSecondsNumber / 60.0)
            }
        }

        return 0
    }

    // Splits "47,33.366000N" into ["47", "33.366000", "N"]
    fileprivate func parseUuidLatLong(_ geo: String) -> [String]
    {
        var pieces = [String]()
        let commaIndex = geo.characters.index(of: ",")
        pieces.append(geo.substring(to: commaIndex!))
        
        let start = geo.characters.index(commaIndex!, offsetBy: 1)
        let end = geo.characters.index(before: geo.endIndex)
        pieces.append(geo.substring(with: start..<end ))
        pieces.append(geo.substring(from: geo.characters.index(before: geo.endIndex)))
        return pieces
    }

    fileprivate func byteArrayToString(_ data: Data, offset: Int, length: Int) -> String
    {
        let str = NSMutableString(capacity: length * 3)
        var byte: UInt8 = 0
        for index in offset..<offset+length {
            (data as NSData).getBytes(&byte, range: NSMakeRange(index, 1))
            str.appendFormat("%02X", byte)
            if ((index + 1) % 8) == 0 {
                str.append(" ")
            }
        }
        return str as String
    }
}

class VideoAtom
{
    let offset: UInt64
    let length: UInt64
    let type: String
    var children = [VideoAtom]()


    init(type: String, offset: UInt64, length: UInt64)
    {
//print("atom at \(offset): \(type), \(length) bytes long")
        self.type = type
        self.offset = offset
        self.length = length
    }
}
