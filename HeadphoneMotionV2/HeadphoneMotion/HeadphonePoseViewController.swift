
import UIKit
import SceneKit
import Photos

class HeadphonePoseViewController: UIViewController, CameraManagerDelegate, HeadphoneMotionManagerDelegate {
    
    @IBOutlet weak var sceneView: SCNView!
    @IBOutlet weak var camView: UIView!
    
    var camManager = CameraManager()
    var motionManager = HeadphoneMotionManager()
    private var headNode: SCNNode?
    private var syncRates = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupHead()
        
        camManager.delegate = self
        camManager.startCamera(camView: self.camView)
        
        motionManager.delegate = self
        motionManager.startTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        camManager.stopCamera()
        motionManager.stopTracking()
        print("Stop device motion updates")
    }
    
    private func setupHead() {
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
    }
    
    // MARK: Delegate protocols
    func rotationUpdated(_ rotation: simd_float4x4) {
        if !syncRates {
            headNode?.simdTransform = rotation
            motionManager.updateData()
        }
    }
    func filesCreated(_ urls: [URL]) {
        DispatchQueue.main.async {
            let activityViewController = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            activityViewController.completionWithItemsHandler = { (activityType, completed:Bool, returnedItems:[Any]?, error: Error?) in
                if completed {
                    for url in urls {
                        do {
                            try FileManager.default.removeItem(at: url)
                        } catch let error as NSError {
                            print("Error deleting file: \(error.domain)")
                        }
                    }
                }
            }
            self.present(activityViewController, animated: false)
        }
    }
    func frameCaptured(isRecorded: Bool) {
        if syncRates {
            headNode?.simdTransform = motionManager.getRotation() ?? matrix_identity_float4x4
            if isRecorded { motionManager.updateData() }
        }
    }
    func videoCreated(_ url: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }) { saved, error in
            if let errorDef = error {return print("Error while saving video: \(errorDef.localizedDescription)")}
            guard saved else {return}
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as NSError {
                print("Error deleting video file: \(error.domain)")
            }
            DispatchQueue.main.async {
                let alertController = UIAlertController(title: "Video saved to photos library", message: nil, preferredStyle: .alert)
                let defaultAction = UIAlertAction(title: "OK", style: .default, handler: nil)
                alertController.addAction(defaultAction)
                self.present(alertController, animated: true, completion: nil)
            }
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
    @IBAction func recordingButtonPressed(_ sender: UIButton) {
        if !motionManager.isRecording && !camManager.isRecording {
            motionManager.startRecording()
            camManager.startRecording()
            sender.setTitle("Stop Recording", for: [.normal])
        } else {
            motionManager.stopRecording()
            camManager.stopRecording()
            sender.setTitle("Start Recording", for: [.normal])
        }
    }
    @IBAction func referenceButtonPressed(_ sender: UIButton) {
        motionManager.updateReference()
    }
    @IBAction func syncButtonPressed(_ sender: UIButton) {
        syncRates = !syncRates
        sender.setTitle(syncRates ? "Unsync Framerate" : "Sync Framerate", for: [.normal])
    }
}
