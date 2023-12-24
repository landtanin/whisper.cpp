//
//  SwiftViewController.swift
//  whisper.objc
//
//  Created by Tanin on 16/12/2023.
//

import UIKit
import AudioKit
import AVFoundation

// Constants
let NUM_BUFFERS = 3
let MAX_AUDIO_SEC = 30
let SAMPLE_RATE = 16000

let NUM_BYTES_PER_BUFFER: UInt32 = 16 * 1024

class StateInp {
    var ggwaveId: Int
    var isCapturing: Bool
    var isTranscribing: Bool
    var isRealtime: Bool
    var labelReceived: UILabel?

    var queue: AudioQueueRef?
    var dataFormat: AudioStreamBasicDescription
    var buffers: [AudioQueueBufferRef?]

    var n_samples: Int
    var audioBufferI16: UnsafeMutablePointer<Int16>?
    var audioBufferF32: UnsafeMutablePointer<Float>?

    var ctx: OpaquePointer? // Assuming whisper_context is defined elsewhere
    weak var vc: TrancribeVC?

    init() {
        ggwaveId = 0
        isCapturing = false
        isTranscribing = false
        isRealtime = false
        labelReceived = nil

        queue = nil
        dataFormat = AudioStreamBasicDescription()
        buffers = Array(repeating: nil, count: NUM_BUFFERS)

        n_samples = 0
        audioBufferI16 = nil
        audioBufferF32 = nil

        ctx = nil
        vc = nil
    }
}

protocol TrancribeVC: UIViewController {
    func onTranscribe(_ sender: UIButton?)
    func stopCapturing()
}

class SwiftViewController: UIViewController, TrancribeVC {
    
    var stateInp = StateInp()
    
    var labelStatusInp: UILabel!
    var buttonToggleCapture: UIButton!
    var buttonTranscribe: UIButton!
    var textviewResult: UITextView!
    var transcribeFile: UIButton!
    var buttonRealtime: UIButton!
    
    var audioQueue: AudioQueueRef?
    var audioBuffers: [AudioQueueBufferRef?] = Array(repeating: nil, count: NUM_BUFFERS)
    var isTranscribing = false
    var isRealtime = false
    // TODO: Memory should be managed smartly using malloc and free
    var audioBufferI16: UnsafeMutablePointer<Int16>?
    var audioBufferF32: UnsafeMutablePointer<Float>?
    
    private let audioInputCallback: AudioQueueInputCallback = { inUserData, inAQ, inBuffer, inStartTime, inNumberPacketDescriptions, inPacketDescs in
        
        guard let inUserData = inUserData else { return }
        // sample code for callback https://github.com/watson-developer-cloud/swift-sdk/blob/8359f8d2000c53d11d0757d5413f411ac34fac4e/Sources/SpeechToTextV1/WebSockets/SpeechToTextRecorder.swift#L94
        let stateInp = Unmanaged<StateInp>.fromOpaque(inUserData).takeUnretainedValue()
        
        if !stateInp.isCapturing {
            print("Not capturing, ignoring audio")
            return
        }
        
        let n = Int(inBuffer.pointee.mAudioDataByteSize) / 2
        print("Captured \(n) new samples")
        
        if stateInp.n_samples + n > MAX_AUDIO_SEC * SAMPLE_RATE {
            print("Too much audio data, ignoring")
            
            DispatchQueue.main.async {
                guard let vc = stateInp.vc else { return }
                vc.stopCapturing()
            }
            
            return
        }
        
        for i in 0..<n {
            stateInp.audioBufferI16?[stateInp.n_samples + i] = (inBuffer.pointee.mAudioData.load(fromByteOffset: i * 2, as: Int16.self))
        }
        
        stateInp.n_samples += n
        
        // Put the buffer back in the queue
        AudioQueueEnqueueBuffer(stateInp.queue!, inBuffer, 0, nil)
        
        if stateInp.isRealtime {
            // Dispatch onTranscribe() to the main thread
            DispatchQueue.main.async {
                guard let vc = stateInp.vc else { return }
                vc.onTranscribe(nil)
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Whisper.cpp initialization
        if let modelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin") {
            print("Loading model from \(modelPath)")
            
            
            var params = whisper_context_default_params()
    #if targetEnvironment(simulator)
            params.use_gpu = false
            print("Running on the simulator, using CPU")
    #endif
            let context = whisper_init_from_file_with_params(modelPath, params)
            stateInp.ctx = context
            
            // Check if the model was loaded successfully
            if stateInp.ctx == nil {
                print("Failed to load model")
                return
            }
        } else {
            print("Model file not found")
            return
        }
        
        // Initialize audio format and buffers
        setupAudioFormat()
        stateInp.n_samples = 0
        stateInp.audioBufferI16 = UnsafeMutablePointer<Int16>.allocate(capacity: MAX_AUDIO_SEC * SAMPLE_RATE)
        stateInp.audioBufferF32 = UnsafeMutablePointer<Float>.allocate(capacity: MAX_AUDIO_SEC * SAMPLE_RATE)
        
        stateInp.isTranscribing = false
        stateInp.isRealtime = false
        
        setupUI()
    }
    
    
    func setupAudioFormat() {
        stateInp.dataFormat = AudioStreamBasicDescription(
            mSampleRate: Float64(SAMPLE_RATE),
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2,
            mFramesPerPacket: 1,
            mBytesPerFrame: 2,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 16,
            mReserved: 0
        )
    }
    
    private func setupUI() {
        // Status Label
        labelStatusInp = UILabel()
        labelStatusInp.translatesAutoresizingMaskIntoConstraints = false
        labelStatusInp.text = "Status: Idle"
        view.addSubview(labelStatusInp)
        
        // Toggle Capture Button
        buttonToggleCapture = UIButton(type: .system)
        buttonToggleCapture.setTitle("Start Capturing", for: .normal)
        buttonToggleCapture.translatesAutoresizingMaskIntoConstraints = false
        buttonToggleCapture.addTarget(self, action: #selector(toggleCapture), for: .touchUpInside)
        view.addSubview(buttonToggleCapture)
        
        // Transcribe Button
        buttonTranscribe = UIButton(type: .system)
        buttonTranscribe.setTitle("Transcribe - not needed", for: .normal)
        buttonTranscribe.translatesAutoresizingMaskIntoConstraints = false
        buttonTranscribe.addTarget(self, action: #selector(onTranscribe), for: .touchUpInside)
        view.addSubview(buttonTranscribe)
        
        // Text View for Results
        textviewResult = UITextView()
        textviewResult.translatesAutoresizingMaskIntoConstraints = false
        textviewResult.layer.borderColor = UIColor.gray.cgColor
        textviewResult.layer.borderWidth = 1.0
        textviewResult.layer.cornerRadius = 5.0
        view.addSubview(textviewResult)
        
        // Transcribe File Button
        transcribeFile = UIButton(type: .system)
        transcribeFile.setTitle("Transcribe File", for: .normal)
        transcribeFile.translatesAutoresizingMaskIntoConstraints = false
        transcribeFile.addTarget(self, action: #selector(transcribeExistingFile), for: .touchUpInside)
        view.addSubview(transcribeFile)
        
        // Realtime Transcription Button
        buttonRealtime = UIButton(type: .system)
        buttonRealtime.setTitle("Realtime Transcription toggle", for: .normal)
        buttonRealtime.translatesAutoresizingMaskIntoConstraints = false
        buttonRealtime.addTarget(self, action: #selector(onRealtime), for: .touchUpInside)
        view.addSubview(buttonRealtime)
        
        // Constraints
        NSLayoutConstraint.activate([
            labelStatusInp.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            labelStatusInp.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            buttonToggleCapture.topAnchor.constraint(equalTo: labelStatusInp.bottomAnchor, constant: 20),
            buttonToggleCapture.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            buttonTranscribe.topAnchor.constraint(equalTo: buttonToggleCapture.bottomAnchor, constant: 20),
            buttonTranscribe.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            textviewResult.topAnchor.constraint(equalTo: buttonTranscribe.bottomAnchor, constant: 20),
            textviewResult.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            textviewResult.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.9),
            textviewResult.heightAnchor.constraint(equalToConstant: 300),
            
            transcribeFile.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            transcribeFile.topAnchor.constraint(equalTo: textviewResult.bottomAnchor, constant: 20),
            
            buttonRealtime.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            buttonRealtime.topAnchor.constraint(equalTo: transcribeFile.bottomAnchor, constant: 20)
        ])
    }
    
    @objc func toggleCapture(_ sender: UIButton) {
        guard !stateInp.isCapturing else {
            stopCapturing()
            return
        }
        
        print("Start capturing")

        stateInp.n_samples = 0
        stateInp.vc = self
        
        var dataFormat = stateInp.dataFormat
        
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(stateInp).toOpaque())
        var status = AudioQueueNewInput(&dataFormat,
                                        audioInputCallback,
                                        pointer,
                                        CFRunLoopGetCurrent(),
                                        CFRunLoopMode.commonModes.rawValue,
                                        0,
                                        &stateInp.queue)

        if status == noErr {
            for i in 0..<NUM_BUFFERS {
                AudioQueueAllocateBuffer(stateInp.queue!, NUM_BYTES_PER_BUFFER, &stateInp.buffers[i])
                AudioQueueEnqueueBuffer(stateInp.queue!, stateInp.buffers[i]!, 0, nil)
            }

            stateInp.isCapturing = true
            status = AudioQueueStart(stateInp.queue!, nil)
            if status == noErr {
                labelStatusInp.text = "Status: Capturing"
                sender.setTitle("Stop Capturing", for: .normal)
                sender.backgroundColor = .red
            }
        }

        if status != noErr {
            stopCapturing()
        }
    }
    
    func stopCapturing() {
        print("Stop capturing")

        labelStatusInp.text = "Status: Idle"
        buttonToggleCapture.setTitle("Start Capturing", for: .normal)
        buttonToggleCapture.backgroundColor = .gray

        stateInp.isCapturing = false

        if let queue = stateInp.queue {
            AudioQueueStop(queue, true)
            for i in 0..<NUM_BUFFERS {
                if let buffer = stateInp.buffers[i] {
                    AudioQueueFreeBuffer(queue, buffer)
                }
            }
            AudioQueueDispose(queue, true)
            stateInp.queue = nil
            
            print("Stop capturing done")
        } else {
            print("Stop capturing failed")
        }
    }
    
    @IBAction func onRealtime(_ sender: UIButton) {
        stateInp.isRealtime.toggle()

        if stateInp.isRealtime {
            buttonRealtime.backgroundColor = .green
        } else {
            buttonRealtime.backgroundColor = .gray
        }

        print("Realtime: \(stateInp.isRealtime ? "ON" : "OFF")")
    }

    // called in audio input callback
    @IBAction func onTranscribe(_ sender: UIButton?) {
        guard !stateInp.isTranscribing, let context = stateInp.ctx else {
            return
        }

        print("Processing \(stateInp.n_samples) samples")

        stateInp.isTranscribing = true

        // Dispatch the model to a background thread
        DispatchQueue.global(qos: .default).async { [unowned self] in
            // Process captured audio
            // Convert I16 to F32
            if let audioBufferI16 = self.stateInp.audioBufferI16, let audioBufferF32 = self.stateInp.audioBufferF32 {
                for i in 0..<self.stateInp.n_samples {
                    audioBufferF32[i] = Float(audioBufferI16[i]) / 32768.0
                }
            }
            
            // Run the model
            let maxThreads = max(1, min(8, ProcessInfo.processInfo.processorCount - 2))
            var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            "en".withCString { en in
                // Adapted from whisper.objc
                params.print_realtime   = true
                params.print_progress   = false
                params.print_timestamps = true
                params.print_special    = false
                params.translate        = false
                params.language         = en
                params.n_threads        = Int32(maxThreads)
                params.offset_ms        = 0
                params.no_context       = true
                params.single_segment   = stateInp.isRealtime
            }
            
            let startTime = CACurrentMediaTime()

            whisper_reset_timings(context)
            
            // This is where transcription happens
            // Implement the transcription logic here
            if (whisper_full(stateInp.ctx, params, stateInp.audioBufferF32, Int32(stateInp.n_samples)) != 0) {
                print("Failed to run the model")
            } else {
                whisper_print_timings(context)
            }

            let endTime = CACurrentMediaTime()

            print("\nProcessing time: \(endTime - startTime), on \(maxThreads) threads")

            // Result text
            var transcription = ""

            // Assuming whisper_full_n_segments and whisper_full_get_segment_text are defined and accessible
            for i in 0..<whisper_full_n_segments(context) {
                transcription += String.init(cString: whisper_full_get_segment_text(context, i))
            }

            let tRecording = Float(self.stateInp.n_samples) / Float(self.stateInp.dataFormat.mSampleRate)

            // Append processing time
            transcription += "\n\n[recording time: \(tRecording) s]"
            transcription += "  \n[processing time: \(endTime - startTime) s]"

            // Dispatch the result to the main thread
            DispatchQueue.main.async {
                self.textviewResult.text = transcription
                self.stateInp.isTranscribing = false
            }
        }
    }
    
    // MARK: - Transcribe uploaded files
    
    @objc func transcribeExistingFile() {
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
        let converter = FormatConverter(inputURL: inputURL, outputURL: outputURL, options: options)
        
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

