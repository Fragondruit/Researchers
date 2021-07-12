import Foundation
import AVFoundation
import UIKit

protocol CameraManagerDelegate {
    func frameCaptured(isRecorded: Bool)
    func videoCreated(_ url: URL)
}

class CameraManager: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var captureSession = AVCaptureSession()
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    
    private var videoOutput = AVCaptureVideoDataOutput()
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var adapter: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime = Double.zero
    
    var delegate: CameraManagerDelegate?
    
    var isRecording = false
    
    func checkCameraAccess(handler: @escaping (Bool) -> Void) {
        
        // check camera availability
        guard UIImagePickerController.availableCaptureModes(for: .front) != nil else {
            return handler(false)
        }
        
        // camera exists, check authoriation status
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { accessGranted in
                if accessGranted == true {
                    handler(true)
                } else {
                    handler(false)
                }
            }
            return
        case .authorized:
            return handler(true)
        default:
            return handler(false)
        }
    }
    
    func startCamera(camView: UIView) {
        checkCameraAccess() { accessGranted in
            guard accessGranted else {
                return print("Camera access denied!")
            }
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
                return print("Unable to access camera!")
            }
            
            let input: AVCaptureInput
            do {
                input = try AVCaptureDeviceInput(device: videoDevice)
            } catch let error  {
                return print("Error Unable to initialize back camera:  \(error.localizedDescription)")
            }
            guard self.captureSession.canAddInput(input) else {return print("can't add input")}
            self.captureSession.addInput(input)
            
            guard self.captureSession.canAddOutput(self.videoOutput) else {return print("can't add output")}
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue.main)
            self.captureSession.addOutput(self.videoOutput)
            
            self.videoPreviewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
            self.videoPreviewLayer.videoGravity = .resizeAspectFill
            self.videoPreviewLayer.connection?.videoOrientation = .portrait
            camView.layer.addSublayer(self.videoPreviewLayer)
            
            self.captureSession.sessionPreset = .medium
            DispatchQueue.global(qos: .userInitiated).async { //[weak self] in
                self.captureSession.startRunning()
                print("Camera started")
                DispatchQueue.main.async {
                    self.videoPreviewLayer.frame = camView.bounds
                }
            }
        }
    }
    
    func stopCamera() {
        captureSession.stopRunning()
    }
    
    // MARK: Delegates
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        if assetWriterInput?.isReadyForMoreMediaData == true {
            delegate?.frameCaptured(isRecorded: true)
            if startTime == .zero { startTime = timestamp }
            let time = CMTime(seconds: timestamp - startTime, preferredTimescale: CMTimeScale(600))
            adapter?.append(CMSampleBufferGetImageBuffer(sampleBuffer)!, withPresentationTime: time)
        } else {
            delegate?.frameCaptured(isRecorded: false)
        }
    }
    
    // MARK: Recording and saving
    func startRecording() {
        guard !isRecording else {return}
        
        let format = DateFormatter()
        format.dateFormat="yyyyMMdd-HHmmss"
        let dateStr = format.string(from: Date())
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsDirectory.appendingPathComponent("MotionVideo-\(dateStr).mov")
        
        do {
            let writer = try AVAssetWriter(outputURL: fileURL, fileType: .mov)
            let settings = videoOutput.recommendedVideoSettingsForAssetWriter(writingTo: .mov)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.mediaTimeScale = CMTimeScale(bitPattern: 600)
            input.expectsMediaDataInRealTime = true
            input.transform = CGAffineTransform(rotationAngle: .pi/2)
            adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
            if writer.canAdd(input) { writer.add(input) }
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            assetWriter = writer
            assetWriterInput = input
            isRecording = true
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }
    
    func stopRecording() {
        guard isRecording else {return}
        guard assetWriterInput?.isReadyForMoreMediaData == true, assetWriter!.status != .failed else { return }
        assetWriterInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            if let url = self?.assetWriter?.outputURL {self?.delegate?.videoCreated(url)}
            self?.isRecording = false
            self?.assetWriter = nil
            self?.assetWriterInput = nil
            self?.startTime = .zero
        }
        
        
    }
    
}
