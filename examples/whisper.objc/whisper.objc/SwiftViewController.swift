//
//  SwiftViewController.swift
//  whisper.objc
//
//  Created by Tanin on 16/12/2023.
//

import UIKit
import AudioKit
import AVFoundation

class SwiftViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let button = UIButton(type: .system) // or .custom
        button.setTitle("Click Me", for: .normal)
        button.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(button)
        
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        button.addTarget(self, action: #selector(buttonClicked), for: .touchUpInside)
    }
    
    @objc func buttonClicked() {
        var options = FormatConverter.Options()
        options.format = .wav
        options.sampleRate = 16000
        options.bitDepth = 16
        options.channels = 1

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("output-\(UUID()).wav")
        print(outputURL)

        func cb(_ progress: UnsafePointer<Int8>?) -> Int32 {
            let str = String(cString: progress!)
            print(str)
            return 0
        }

        let inputURL = Bundle.main.url(forResource: "long_audio_30", withExtension: "mp3", subdirectory: "")!
//        let inputURL = URL(string: audioFilePath)!
        let converter = FormatConverter(inputURL: inputURL, outputURL: outputURL, options: options)
//        converter.start { error in
//            if error == nil {
//                DispatchQueue.global(qos: .userInitiated).async {
//                    let modelURL = Bundle.main.url(forResource: "ggml-tiny", withExtension: "bin", subdirectory: "")
//                    
//                    // TODO: If file too long, it'll fail.
//                    // TODO: Split the wav file into multiple chunks, get
////                    let audioFile = try! AVAudioFile(forReading: outputURL)
////                    let segmentDuration = 600.0 // 10 mins segment
////                    
////                    var startTime = 0.0
////                    while startTime < audioFile.duration {
////                        let endTime = min(startTime + segmentDuration, audioFile.duration)
////                        let segmentBuffer = audioFile.extractSegment(startTime: startTime, endTime: endTime)
////                        let segmentFileURL = saveSegmentToFile(segmentBuffer)
////                    }
////                    
//                    // read_wav convert file to mono as well
//                    read_wav(modelURL!.absoluteURL.path, outputURL.absoluteURL.path, cb)
//
//                    DispatchQueue.main.async {
//                        print("This is run on the main queue, after the previous code in outer block")
//                    }
//                }
//            }
//        }
        
        converter.start { error in
            if error == nil {
                Task(priority: .userInitiated) {
                    let modelURL = Bundle.main.url(forResource: "ggml-base.en", withExtension: "bin", subdirectory: "")
                    let whisperContext = try! WhisperContext.createContext(path: modelURL!.path())
                    
                    let audioFile = try! AVAudioFile(forReading: outputURL)
                    let segmentDuration: TimeInterval = 300.0 // 5 mins segment
                    
                    var startTime: TimeInterval = 0.0
                    while startTime < audioFile.duration {
                        let endTime = min(startTime + segmentDuration, audioFile.duration)
                        let segmentBuffer = audioFile.extractSegment(startTime: startTime, endTime: endTime)
                        
                        // transcribe
                        guard let channelData = segmentBuffer!.floatChannelData else { return }
                        let frameLength = Int(segmentBuffer!.frameLength)
                        var audioData = [Float](repeating: 0, count: frameLength)
                        
                        for i in 0..<frameLength {
                            audioData[i] = channelData.pointee[i]
                        }
                        
                        let _ = await whisperContext.fullTranscribe(samples: audioData)
//                        print("startTime: \(startTime)\n")
//                        print("text: \(text)\n")
                        
                        startTime = endTime
                    }
                }
            }
        }
    }
    
}

extension AVAudioFile {
    func extractSegment(startTime: TimeInterval, endTime: TimeInterval) -> AVAudioPCMBuffer? {
        let sampleRate = self.fileFormat.sampleRate
        let startFrame = AVAudioFramePosition(startTime * sampleRate)
        let endFrame = AVAudioFramePosition(endTime * sampleRate)
        let frameCount = AVAudioFrameCount(endFrame - startFrame)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: self.processingFormat, frameCapacity: frameCount) else {
            return nil
        }

        do {
            self.framePosition = startFrame // Set the frame position to the start of the segment
            try self.read(into: buffer, frameCount: frameCount)
            return buffer
        } catch {
            print("Error extracting audio segment: \(error)")
            return nil
        }
    }
}

