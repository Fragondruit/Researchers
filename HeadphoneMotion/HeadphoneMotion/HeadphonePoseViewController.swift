
import UIKit
import SceneKit
import AVFoundation
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

class HeadphonePoseViewController: UIViewController, CMHeadphoneMotionManagerDelegate {
    
    @IBOutlet weak var sceneView: SCNView!
    @IBOutlet weak var camView: UIView!
    @IBOutlet weak var motionButton: UIButton!
    @IBOutlet weak var referenceButton: UIButton!
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    var photoOutput: AVCapturePhotoOutput!
    
    var motionFileURL:URL!
    var deviceMotionData = Array(repeating: [] , count:16)
    private var motionManager = CMHeadphoneMotionManager()
    private var headNode: SCNNode?
    private var referenceFrame = matrix_identity_float4x4
    var samplef:Float = 10
    var saveMotionData:Bool = false
    
    let mirrorTransform = simd_float4x4([
        simd_float4(-1.0, 0.0, 0.0, 0.0),
        simd_float4( 0.0, 1.0, 0.0, 0.0),
        simd_float4( 0.0, 0.0, 1.0, 0.0),
        simd_float4( 0.0, 0.0, 0.0, 1.0)
    ])
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.bringSubviewToFront(referenceButton)
        view.bringSubviewToFront(motionButton)

        let scene = SCNScene(named: "head.obj")!
        
        headNode = scene.rootNode.childNodes.first

        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        scene.rootNode.addChildNode(cameraNode)
        cameraNode.position = SCNVector3(x: 0, y: 0, z: 2.0)
        cameraNode.camera?.zNear = 0.05

        let lightNode = SCNNode()
        lightNode.light = SCNLight()
        lightNode.light!.type = .omni
        lightNode.position = SCNVector3(x: 0, y: 10, z: 10)
        scene.rootNode.addChildNode(lightNode)

        let ambientLightNode = SCNNode()
        ambientLightNode.light = SCNLight()
        ambientLightNode.light!.type = .ambient
        ambientLightNode.light!.color = UIColor.darkGray
        scene.rootNode.addChildNode(ambientLightNode)

        sceneView.scene = scene
        
        if UIImagePickerController.availableCaptureModes(for: .front) != nil {
            
            // camera exists, check authoriation status
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) {
                    accessGranted in
                    guard accessGranted == true else {return}
                }
            case .authorized:
                break
            default:
                print("Access denied!")
                return
            }
            
            //
            captureSession = AVCaptureSession()
            captureSession.sessionPreset = .medium
            
            guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)  //.video
                else {
                    print("Unable to access camera!")
                    return
            }
            do {
                let input = try AVCaptureDeviceInput(device: videoDevice)
                photoOutput = AVCapturePhotoOutput()
                if captureSession.canAddInput(input) && captureSession.canAddOutput(photoOutput) {
                    captureSession.addInput(input)
                    captureSession.addOutput(photoOutput)
                    setupLivePreview()
                }
            }
            catch let error  {
                print("Error Unable to initialize back camera:  \(error.localizedDescription)")
            }
            
        } else {
            // no camera is available, pop up alert
            
            let alertVC = UIAlertController(
                title: "No camera",
                message: "Sorry, this device has no camera",
                preferredStyle: .alert)
            let okAction = UIAlertAction(
                title: "OK",
                style: .default,
                handler: nil)
            alertVC.addAction(okAction)
            present(alertVC, animated: true, completion: nil)
        }

        motionManager.delegate = self
        
        updateButtonState()
        if let deviceMotion = motionManager.deviceMotion {
            referenceFrame = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix).inverse
        }
        startTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.captureSession.stopRunning()
        motionManager.stopDeviceMotionUpdates()
        print("Stop device motion updates")
    }
    
    func setupLivePreview() {
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.connection?.videoOrientation = .portrait
        camView.layer.addSublayer(videoPreviewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { //[weak self] in
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.videoPreviewLayer.frame = self.camView.bounds
            }
        }
    }
    
    private func updateButtonState() {
        motionButton.isEnabled = motionManager.isDeviceMotionAvailable
                              && CMHeadphoneMotionManager.authorizationStatus() != .denied
        let motionTitle = self.saveMotionData ? "Stop Recording" : "Start Recording"
        motionButton.setTitle(motionTitle, for: [.normal])
        referenceButton.isHidden = !motionManager.isDeviceMotionActive
    }
    
    private func startTracking() {
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
                if let strongSelf = weakSelf {
                    if let deviceMotion = maybeDeviceMotion {
                        strongSelf.headphoneMotionManager(strongSelf.motionManager, didUpdate:deviceMotion)
                    } else if let error = maybeError {
                        strongSelf.headphoneMotionManager(strongSelf.motionManager, didFail:error)
                    }
                }
            }
            print("Started device motion updates")
        }
        updateButtonState()
    }
    
    // stackoverflow.com/questions/24097826/read-and-write-data-from-text-file
    func witeToFile(text:  Array<[Any]>){
        let format = DateFormatter()
        format.dateFormat="yyyyMMdd-HHmmss"
        let currentFileName = "MotionData-\(format.string(from: Date())).txt"
        print(currentFileName)
        
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.motionFileURL = documentsDirectory.appendingPathComponent(currentFileName)
        print("writing to motion data file url: '\(motionFileURL!)'")
        
        if FileManager.default.fileExists(atPath: motionFileURL.absoluteString) {
        // probably won't happen. want to do something about it?
            print("motion data file \(motionFileURL.absoluteString) exists")
        }
        let content = String(describing: text)
//        print(content)
        do {
            try content.write(to: motionFileURL, atomically: false, encoding: String.Encoding.utf8)
            print("file saved.")
        } catch let error as NSError {
            print(error.localizedDescription)
        }
    }
    
    // MARK: - UIViewController
    
    override var shouldAutorotate: Bool {
        return true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
    
    // MARK: - IBActions

    @IBAction func startMotionTrackingButtonTapped(_ sender: UIButton)
    {
        if !self.saveMotionData{
            self.saveMotionData = true
        }else {
            self.saveMotionData = false
            self.witeToFile(text: deviceMotionData)
            deviceMotionData  = Array(repeating: [] , count:16)
            updateButtonState()
        }
    }
    
    @IBAction func referenceFrameButtonWasTapped(_ sender: UIButton)
    {
        if let deviceMotion = motionManager.deviceMotion {
            referenceFrame = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix).inverse
        }
    }
    // MARK: - CMHeadphoneMotionManagerDelegate
    
    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones did connect")
        updateButtonState()
    }
    
    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        print("Headphones did disconnect")
        updateButtonState()
    }
    
    // MARK: Headphone Device Motion Handlers
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didUpdate deviceMotion: CMDeviceMotion) {
        let rotation = float4x4(rotationMatrix: deviceMotion.attitude.rotationMatrix)
        
        let accx = deviceMotion.userAcceleration.x;
        let accy = deviceMotion.userAcceleration.y;
        let accz = deviceMotion.userAcceleration.z;
                
//        rotation[3,0] = Float(0.5*accx)*samplef;
//        rotation[3,1] = Float(0.5*accy)*samplef;
//        rotation[3,2] = Float(0.5*accz)*samplef;
        
        headNode?.simdTransform = self.mirrorTransform * rotation * referenceFrame
        updateButtonState()
//        print(rotation)
        
        if self.saveMotionData{
            // acc
            self.deviceMotionData[0].append(accx)
            self.deviceMotionData[1].append(accy)
            self.deviceMotionData[2].append(accz)
            // attitude
            self.deviceMotionData[3].append(deviceMotion.attitude.pitch)
            self.deviceMotionData[4].append(deviceMotion.attitude.roll)
            self.deviceMotionData[5].append(deviceMotion.attitude.yaw)
            // rotationRate
            self.deviceMotionData[6].append(deviceMotion.rotationRate.x)
            self.deviceMotionData[7].append(deviceMotion.rotationRate.y)
            self.deviceMotionData[8].append(deviceMotion.rotationRate.z)
            // gravity
            self.deviceMotionData[9].append(deviceMotion.gravity.x)
            self.deviceMotionData[10].append(deviceMotion.gravity.y)
            self.deviceMotionData[11].append(deviceMotion.gravity.z)
            // magneticField
            self.deviceMotionData[12].append(deviceMotion.magneticField.field.x)
            self.deviceMotionData[13].append(deviceMotion.magneticField.field.y)
            self.deviceMotionData[14].append(deviceMotion.magneticField.field.z)
            // timestamp
            self.deviceMotionData[15].append(deviceMotion.timestamp)
            print(self.deviceMotionData[0].count ?? 0)
        }
    }
    
    func headphoneMotionManager(_ motionManager: CMHeadphoneMotionManager, didFail error: Error) {
        updateButtonState()
    }

}
