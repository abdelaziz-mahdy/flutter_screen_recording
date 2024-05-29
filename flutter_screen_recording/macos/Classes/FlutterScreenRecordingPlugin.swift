import Cocoa
import FlutterMacOS
import AVFoundation
import ReplayKit

public class FlutterScreenRecordingPlugin: NSObject, FlutterPlugin {
  private var screenRecorder: RPScreenRecorder
  private var videoOutputURL: URL?
  private var audioRecording: AVAudioRecorder?

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

    if audio {
      startAudioRecording()
    }

    screenRecorder.startCapture(handler: { (sampleBuffer, bufferType, error) in
      if error != nil {
        print("Error capturing screen: \(String(describing: error))")
        result(FlutterError(code: "ERROR", message: "Screen capture failed", details: error?.localizedDescription))
        return
      }
      // Handle sample buffer if necessary
    }) { (error) in
      if let error = error {
        print("Failed to start screen recording: \(error.localizedDescription)")
        result(FlutterError(code: "ERROR", message: "Screen recording start failed", details: error.localizedDescription))
      } else {
        print("Screen recording started successfully")
        result(true)
      }
    }
  }

  private func stopScreenRecording(result: @escaping FlutterResult) {
    screenRecorder.stopCapture { (error) in
      if let error = error {
        print("Failed to stop screen recording: \(error.localizedDescription)")
        result(FlutterError(code: "ERROR", message: "Screen recording stop failed", details: error.localizedDescription))
      } else {
        print("Screen recording stopped successfully")
        if let audioRecording = self.audioRecording, audioRecording.isRecording {
          audioRecording.stop()
        }
        result(self.videoOutputURL?.path)
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
    } catch {
      print("Failed to start audio recording: \(error.localizedDescription)")
    }
  }
}
