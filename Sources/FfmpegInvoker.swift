import Foundation
import Spawn

class FfmpegInvoker
{
    enum Error : Swift.Error {
        case runFailed(error: String)
    }

    // The output folder must exit or this will fail. Also, the files must not already exist
    static func generateFrameCapture(_ fileList: [String], _ outputFolder: String) throws
    {
        // Use Ffmpeg to create a frame capture image
        try fileList.forEach { path in
            let baseFilename = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            _ = try runFfmpeg([
                "-nostdin",
                "-nostats",
                "-loglevel",
                "8",
                "-i",
                path, 
                "-ss",
                "00:00:01.0", 
                "-vframes",
                "1",
                outputFolder + "/" + baseFilename + ".JPG"])
        }
    }

    static var ffmpegPath: String { return "/usr/local/bin/ffmpeg" }

    static fileprivate func runFfmpeg(_ arguments: [String]) throws -> String
    {
        do {
            // Process, via ProcessInvoker, hangs when issuing this command. I don't understand why or
            // how to avoid it, so use posix_spawn, via Spawn, instead.
            var output = ""
            let spawn = try Spawn(args: [ffmpegPath] + arguments) { str in
                output = output + str
            }
            let exitCode = spawn.waitForExit()
            if exitCode == 0 {
                return ""
            }

            throw Error.runFailed(error: "ffmpeg failed: \(exitCode) [\(output)]")
        }
        catch {
            throw Error.runFailed(error: "ffmpeg failed: \(error)")
        }
    }
}
