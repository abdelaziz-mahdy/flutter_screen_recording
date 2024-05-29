import Cocoa
import FlutterMacOS
import AVFoundation
import ReplayKit

public class FlutterScreenRecordingPlugin: NSObject, FlutterPlugin {
    private var screenRecorder: RPScreenRecorder
    private var videoOutputURL: URL?
    private var audioRecording: AVAudioRecorder?
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?

    override init() {
        self.screenRecorder = RPScreenRecorder.shared()
        super.init()
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_screen_recording", binaryMessenger: registrar.messenger)
        let instance = FlutterScreenRecordingPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startRecordScreen":
            let args = call.arguments as! [String: Any]
            let name = args["name"] as! String
            let title = args["title"] as! String
            let message = args["message"] as! String
            startScreenRecording(name: name, audio: false, title: title, message: message, result: result)
        case "startRecordScreenAndAudio":
            let args = call.arguments as! [String: Any]
            let name = args["name"] as! String
            let title = args["title"] as! String
            let message = args["message"] as! String
            startScreenRecording(name: name, audio: true, title: title, message: message, result: result)
        case "stopRecordScreen":
            stopScreenRecording(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func startScreenRecording(name: String, audio: Bool, title: String, message: String, result: @escaping FlutterResult) {
        let fileName = "\(name).mp4"
        let fileURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(fileName)
        self.videoOutputURL = fileURL

        do {
            self.assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: 1280,
                AVVideoHeightKey: 720
            ]
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput = videoInput, self.assetWriter?.canAdd(videoInput) == true {
                self.assetWriter?.add(videoInput)
            }

            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: 1280,
                kCVPixelBufferHeightKey as String: 720
            ]
            adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput!, sourcePixelBufferAttributes: sourcePixelBufferAttributes)

            if audio {
                startAudioRecording()
            }

            self.assetWriter?.startWriting()
            self.startTime = CMTime.zero
            self.assetWriter?.startSession(atSourceTime: self.startTime!)

            screenRecorder.isMicrophoneEnabled = audio
            screenRecorder.isCameraEnabled = false

            screenRecorder.startCapture(handler: { (sampleBuffer, bufferType, error) in
                if let error = error {
                    print("Error capturing screen: \(error.localizedDescription)")
                    result(FlutterError(code: "ERROR", message: "Screen capture failed", details: error.localizedDescription))
                    return
                }

                if CMSampleBufferDataIsReady(sampleBuffer) {
                    if self.assetWriter?.status == .writing {
                        if self.startTime == CMTime.zero {
                            self.startTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            self.assetWriter?.startSession(atSourceTime: self.startTime!)
                        }

                        switch bufferType {
                        case .video:
                            if self.videoInput?.isReadyForMoreMediaData == true {
                                if let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
                                    let currentTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                    self.adaptor?.append(pixelBuffer, withPresentationTime: currentTime)
                                }
                            }
                        case .audioMic:
                            if audio {
                                if self.audioInput?.isReadyForMoreMediaData == true {
                                    self.audioInput?.append(sampleBuffer)
                                }
                            }
                        default:
                            break
                        }
                    }
                }
            }) { (error) in
                if let error = error {
                    print("Failed to start screen recording: \(error.localizedDescription)")
                    result(FlutterError(code: "ERROR", message: "Screen recording start failed", details: error.localizedDescription))
                } else {
                    print("Screen recording started successfully")
                    result(true)
                }
            }
        } catch {
            result(FlutterError(code: "ERROR", message: "AssetWriter creation failed", details: error.localizedDescription))
        }
    }

    private func stopScreenRecording(result: @escaping FlutterResult) {
        screenRecorder.stopCapture { (error) in
            if let error = error {
                print("Failed to stop screen recording: \(error.localizedDescription)")
                result(FlutterError(code: "ERROR", message: "Screen recording stop failed", details: error.localizedDescription))
            } else {
                print("Screen recording stopped successfully")
                self.videoInput?.markAsFinished()
                if let audioInput = self.audioInput {
                    audioInput.markAsFinished()
                }
                self.assetWriter?.finishWriting {
                    if let audioRecording = self.audioRecording, audioRecording.isRecording {
                        audioRecording.stop()
                    }
                    result(self.videoOutputURL?.path)
                }
            }
        }
    }

    private func startAudioRecording() {
        let audioFilename = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("audio.m4a")
        let settings = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 12000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecording = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecording?.record()

            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVNumberOfChannelsKey: 1,
                AVSampleRateKey: 12000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            if let audioInput = audioInput, self.assetWriter?.canAdd(audioInput) == true {
                self.assetWriter?.add(audioInput)
            }

        } catch {
            print("Failed to start audio recording: \(error.localizedDescription)")
        }
    }
}
