class VipsThumbnailInvoker
{
    enum Error : Swift.Error {
        case runFailed(error: String)
    }

    // The output folder must exit or this will fail
    static func scaleImages(_ fileList: [String], _ outputFolder: String, _ imageHeight: Int) throws
    {
        let sizeOption = "10000x" + String(imageHeight)

        _ = try runVipsThumbnail([
            "-d", 
            "-s", 
            sizeOption,
            "-o", 
            outputFolder + "%s.JPG[optimize_coding,strip]"]
            + fileList)
    }


    static var vipsThumbnailPath: String { return "/usr/local/bin/vipsthumbnail" }

    static fileprivate func runVipsThumbnail(_ arguments: [String]) throws -> String
    {
        let process = ProcessInvoker.run(vipsThumbnailPath, arguments: arguments)
        if process.exitCode == 0 {
            return process.output
        }

        throw Error.runFailed(error: "vipsthumbnail failed: \(process.exitCode); error: '\(process.error)'")
    }
}
