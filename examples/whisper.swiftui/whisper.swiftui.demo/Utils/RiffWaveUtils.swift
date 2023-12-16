import Foundation
import AudioKit
import AVFoundation

func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    let floats = stride(from: 44, to: data.count, by: 2).map {
        return data[$0..<$0 + 2].withUnsafeBytes {
            let short = Int16(littleEndian: $0.load(as: Int16.self))
            return max(-1.0, min(Float(short) / 32767.0, 1.0))
        }
    }
    return floats
}

func decodeAudioFile(_ url: URL) throws -> [Float] {
    var options = FormatConverter.Options()

    // any options left nil will adopt the value of the input file
    options.format = .wav
    options.sampleRate = 16000
    options.bitDepth = 24
    options.bitRate = 16
    options.channels = 1

    // Get the document directory URL
    guard let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
        print("Failed to access documents directory")
        return []
    }
    
    // Create a destination URL for the .wav file
    let destinationUrl = documentsDirectoryURL.appendingPathComponent("convertedFile.wav")

    let converter = FormatConverter(inputURL: url, outputURL: destinationUrl, options: options)

    converter.start { error in
        // the error will be nil on success
        // TODO: Throws error
    }

    if let outputURL = converter.outputURL {
        let decodedData = try decodeWaveFile(outputURL)

        try FileManager.default.removeItem(at: outputURL)
        return decodedData
    }

    // TODO: Handle error
    return []
}
