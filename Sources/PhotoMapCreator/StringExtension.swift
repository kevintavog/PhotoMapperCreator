import Foundation

extension String
{
    public func substring(offset: Int, end: Int) -> String
    {
        return substringWithRange(NSMakeRange(0, end - offset))
    }

    // Returns a substring as denoted by an NSRange
    public func substringWithRange(_ range: NSRange) -> String
    {
        let startIndex = self.index(self.startIndex, offsetBy: range.location)
        let endIndex = self.index(startIndex, offsetBy: range.length)
        return String(self[startIndex..<endIndex])
    }

    public func substringFromOffset(_ offset: Int) -> String
    {
        let startIndex = self.index(self.startIndex, offsetBy: offset)
        return String(self[startIndex...])
    }
}
