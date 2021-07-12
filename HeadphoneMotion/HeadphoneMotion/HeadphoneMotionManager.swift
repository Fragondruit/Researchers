import Foundation
import CoreMotion
import simd

extension float4x4 {
    init(rotationMatrix r: CMRotationMatrix) {
        self.init([
            simd_float4(Float(-r.m11), Float(r.m13), Float(r.m12), 0.0),
            simd_float4(Float(-r.m31), Float(r.m33), Float(r.m32), 0.0),
            simd_float4(Float(-r.m21), Float(r.m23), Float(r.m22), 0.0),
            simd_float4(          0.0,          0.0,          0.0, 1.0)
        ])
    }
}

protocol HeadphoneMotionManagerDelegate {
    func rotationUpdated(_ rotation: simd_float4x4)
    func filesCreated(_ urls: [URL])
}

class HeadphoneMotionManager: NSObject, CMHeadphoneMotionManagerDelegate {
    
    let mirrorFrame = simd_float4x4([
        simd_float4(-1.0, 0.0, 0.0, 0.0),
        simd_float4( 0.0, 1.0, 0.0, 0.0),
        simd_float4( 0.0, 0.0, 1.0, 0.0),
        simd_float4( 0.0, 0.0, 0.0, 1.0)
    ])
    
    private var motionManager = CMHeadphoneMotionManager()
    private var referenceFrame = matrix_identity_float4x4
    
    var isRecording = false
    private var motionData = Array(repeating: [] , count: 16)
    private var rotationData: [[Float]] = []
    private var axesData:  [[Double]] = []
    
    var delegate: HeadphoneMotionManagerDelegate?
    
    override init() {
        super.init()
        motionManager.delegate = self
    }
    
    func startTracking() {
        
        switch CMHeadphoneMotionManager.authorizationStatus() {
        case .authorized:
            print("User previously allowed motion tracking")
        case .restricted:
            print("User access to motion updates is restricted")
        case .denied:
            print("User denied access to motion updates; will not start motion tracking")
            return
        case .notDetermined:
            print("Permission for device motion tracking unknown; will prompt for access")
        default:
            break
        }
        
        if !motionManager.isDeviceMotionActive {
            weak var weakSelf = self
            motionManager.startDeviceMotionUpdates(to: OperationQueue.main) { (maybeDeviceMotion, maybeError) in
                guard let strongSelf = weakSelf else {return}
                if let deviceMotion = maybeDeviceMotion {
                    strongSelf.headphoneMotionManager(strongSelf.motionManager, didUpdate:deviceMotion)
                } else if let error = maybeError {
                    strongSelf.headphoneMotionManager(strongSelf.motionManager, didFail:error)
                }
            }
            updateReference()
            print("Started device motion updates")
        }
    }
    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
    }
    
    func getRotation(_ deviceMotion: CMDeviceMotion) -> simd_float4x4 {
        let rotation = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix)
        return mirrorFrame * rotation * referenceFrame
    }
    func getRotation() -> simd_float4x4? {
        if let deviceMotion = motionManager.deviceMotion {
            return getRotation(deviceMotion)
        } else {
            return nil
        }
    }
    
    func updateReference() {
        if let deviceMotion = motionManager.deviceMotion {
            referenceFrame = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix).inverse
        }
    }
    
    
    // MARK: - CMHeadphoneMotionManagerDelegate
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones connected")
        updateReference()
        //        updateButtonState()
    }
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones disconnected")
        //        updateButtonState()
    }
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didUpdate deviceMotion: CMDeviceMotion) {
        let rotation = getRotation(deviceMotion)
        delegate?.rotationUpdated(rotation)
//        updateData(deviceMotion)
    }
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didFail error: Error) {
        print("Headphone motion manager failed", error)
    }
    
    
    // MARK: Recording and saving
    func updateData(_ maybeDeviceMotion: CMDeviceMotion? = nil) {
        guard isRecording else {return}
        guard let deviceMotion = maybeDeviceMotion ?? motionManager.deviceMotion else {return}
        
        // acc
        motionData[0].append(deviceMotion.userAcceleration.x)
        motionData[1].append(deviceMotion.userAcceleration.y)
        motionData[2].append(deviceMotion.userAcceleration.z)
        // attitude
        motionData[3].append(deviceMotion.attitude.pitch)
        motionData[4].append(deviceMotion.attitude.roll)
        motionData[5].append(deviceMotion.attitude.yaw)
        // rotationRate
        motionData[6].append(deviceMotion.rotationRate.x)
        motionData[7].append(deviceMotion.rotationRate.y)
        motionData[8].append(deviceMotion.rotationRate.z)
        // gravity
        motionData[9].append(deviceMotion.gravity.x)
        motionData[10].append(deviceMotion.gravity.y)
        motionData[11].append(deviceMotion.gravity.z)
        // magneticField
        motionData[12].append(deviceMotion.magneticField.field.x)
        motionData[13].append(deviceMotion.magneticField.field.y)
        motionData[14].append(deviceMotion.magneticField.field.z)
        // timestamp
        motionData[15].append(deviceMotion.timestamp)
        
        let rotation = getRotation(deviceMotion)
        let flatRotation = (0..<3).flatMap { x in (0..<3).map { y in rotation[x][y] } }
        rotationData.append(flatRotation + [Float(deviceMotion.timestamp)])
        
        let a = deviceMotion.attitude
        axesData.append([a.yaw, a.pitch, a.roll, deviceMotion.timestamp])
    }
    func startRecording() {
        guard !isRecording else {return}
        isRecording = true
        motionData = Array(repeating: [] , count: 16)
        rotationData = []
    }
    func stopRecording() {
        guard isRecording else {return}
        isRecording = false
        
        // https://stackoverflow.com/questions/24097826/read-and-write-data-from-text-file
        let format = DateFormatter()
        format.dateFormat="yyyyMMdd-HHmmss"
        let dateStr = format.string(from: Date())
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let motionFileURL = documentsDirectory.appendingPathComponent("MotionData-\(dateStr).txt")
        print("writing to motion data file url: '\(motionFileURL)'")
        if FileManager.default.fileExists(atPath: motionFileURL.absoluteString) {
            print("motion data file \(motionFileURL.absoluteString) exists")
        } else {
            let content = String(describing: motionData)
            do {
                try content.write(to: motionFileURL, atomically: false, encoding: String.Encoding.utf8)
                print("file saved.")
            } catch let error as NSError {
                print(error.localizedDescription)
            }
        }
        
        let rotationDataStr = rotationData.map {
            $0.map { String($0) }.joined(separator: ",")
        }.joined(separator: "\n")
        let rotationURL = documentsDirectory.appendingPathComponent("RotationData-\(dateStr).csv")
        let axesDataStr = axesData.map {
            $0.map { String($0) }.joined(separator: ",")
        }.joined(separator: "\n")
        let axesURL = documentsDirectory.appendingPathComponent("AxesData-\(dateStr).csv")
        do {
            try rotationDataStr.data(using: .utf8)?.write(to: rotationURL)
            try axesDataStr.data(using: .utf8)?.write(to: axesURL)
            delegate?.filesCreated([rotationURL, axesURL])
       } catch {
           print("Error writing rotation file: \(error.localizedDescription)")
       }
    }
    
}
