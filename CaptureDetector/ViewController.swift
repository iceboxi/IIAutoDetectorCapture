//
//  ViewController.swift
//  CaptureDetector
//
//  Created by Adolph on 2018/5/23.
//  Copyright © 2018年 iceboxi. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

class ViewController: UIViewController {
    @IBOutlet weak var detectorModeSelector: UISegmentedControl!
    
    var captureSession: AVCaptureSession = AVCaptureSession()
    lazy var previewLayer: CALayer = {
        let layer = CALayer()
        layer.anchorPoint = CGPoint.zero
        layer.bounds = view.bounds
        return layer
    }()
    var filter: CIFilter!
    var detector: CIDetector?
    lazy var context: CIContext = {
        let eaglContext = EAGLContext(api: .openGLES2)
        let options = [kCIContextWorkingColorSpace : NSNull()]
        return CIContext(eaglContext: eaglContext!, options: options)
    }()
    var ciImage: CIImage!
    var currentDeviceInput: AVCaptureDeviceInput?
    var currentDevice: AVCaptureDevice?
    var isWriting = false
    var timeKeeper: Timer?
    var borderDetectFrame: Bool = true
    var borderDetectLastRectangleFeature: CIRectangleFeature?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if TARGET_OS_SIMULATOR != 0 {
            let alert = UIAlertController(title: "提示", message: "不支援模擬器", preferredStyle: .alert)
            self.present(alert, animated: true, completion: nil)
        } else {
            self.view.layer.insertSublayer(previewLayer, at: 0)
            setupCaptureSession()
            captureSession.startRunning()
            timeKeeper = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(ViewController.enableBorderDetection), userInfo: nil, repeats: true)
            detectorModeSelector.selectedSegmentIndex = 0
            handleDetectorSelectionChange(detectorModeSelector)
        }
    }
    
    @objc func enableBorderDetection() {
        self.borderDetectFrame = true
    }
    
    func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        self.currentDevice = AVCaptureDevice.default(for: .video)
        let deviceInput = try! AVCaptureDeviceInput(device: self.currentDevice!)
        if captureSession.canAddInput(deviceInput) {
            captureSession.addInput(deviceInput)
            self.currentDeviceInput = deviceInput
        }
        
        let dataOutput = AVCaptureVideoDataOutput()
        dataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String : Int(kCVPixelFormatType_32BGRA)]
        dataOutput.alwaysDiscardsLateVideoFrames = true
        
        if captureSession.canAddOutput(dataOutput) {
            captureSession.addOutput(dataOutput)
        }
        
        dataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "VideoQueue"))
        
        // 为了检测人脸
//        let metadataOutput = AVCaptureMetadataOutput()
//        metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
//
//        if captureSession.canAddOutput(metadataOutput) {
//            captureSession.addOutput(metadataOutput)
//            print(metadataOutput.availableMetadataObjectTypes)
//            metadataOutput.metadataObjectTypes = [AVMetadataObject.ObjectType.face]
//        }
        
        captureSession.commitConfiguration()
        
        if (self.currentDevice?.isFocusModeSupported(.continuousAutoFocus))! {
            try! self.currentDevice?.lockForConfiguration()
            self.currentDevice?.focusMode = .continuousAutoFocus
            self.currentDevice?.unlockForConfiguration()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        previewLayer.bounds.size = size
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func handleDetectorSelectionChange(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            detector = prepareRectangleDetector()
            break
        case 1:
            detector = prepareQRCodeDetector()
            break
        default:
            print("")
        }
    }
    
    @IBAction func takePicture(_ sender: UIButton) {
        if ciImage == nil || isWriting {
            return
        }
        sender.isEnabled = false
        captureSession.stopRunning()
        
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        ALAssetsLibrary().writeImage(toSavedPhotosAlbum: cgImage, metadata: ciImage.properties) { (url, error) in
            if error == nil {
                print("保存成功")
                print(url!)
            } else {
                let alert = UIAlertController(title: "错误", message: error?.localizedDescription, preferredStyle: .alert)
                self.present(alert, animated: true, completion: nil)
            }
            self.captureSession.startRunning()
            sender.isEnabled = true
        }
    }
}

extension ViewController {
    func prepareRectangleDetector() -> CIDetector {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        return CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: options)!
    }
    
    func prepareQRCodeDetector() -> CIDetector {
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        return CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options)!
    }
    
    func drawHighlightOverlayForPoints(_ image: CIImage, topLeft: CGPoint, topRight: CGPoint,
                                       bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        var overlay = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.86, alpha: 0.5))
        overlay = overlay.cropped(to: image.extent)
        overlay = overlay.applyingFilter("CIPerspectiveTransformWithExtent", parameters: [
            "inputExtent": CIVector(cgRect: image.extent),
            "inputTopLeft": CIVector(cgPoint: topLeft),
            "inputTopRight": CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight": CIVector(cgPoint: bottomRight)
            ])
        return overlay.composited(over: image)
    }
    
    func performRectangleDetection(_ image: CIImage) -> CIImage? {
        var resultImage: CIImage?
        if let detector = detector {
            // Get the detections
            let features = detector.features(in: image)
            for feature in features as! [CIRectangleFeature] {
                resultImage = drawHighlightOverlayForPoints(image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
            }
        }
        return resultImage
    }
    
    func performQRCodeDetection(_ image: CIImage) -> (outImage: CIImage?, decode: String) {
        var resultImage: CIImage?
        var decode = ""
        if let detector = detector {
            let features = detector.features(in: image)
            for feature in features as! [CIQRCodeFeature] {
                resultImage = drawHighlightOverlayForPoints(image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
                decode = feature.messageString!
            }
        }
        return (resultImage, decode)
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            let sampleBufferValid: Bool = CMSampleBufferIsValid(sampleBuffer)
            if !sampleBufferValid {
                return
            }
            
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
//            self.currentVideoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
//            self.currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer)
            
            // CVPixelBufferLockBaseAddress(imageBuffer, 0)
            // let width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
            // let height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
            // let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
            // let lumaBuffer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0)
            //
            // let grayColorSpace = CGColorSpaceCreateDeviceGray()
            // let context = CGBitmapContextCreate(lumaBuffer, width, height, 8, bytesPerRow, grayColorSpace, CGBitmapInfo.allZeros)
            // let cgImage = CGBitmapContextCreateImage(context)
            var outputImage = CIImage(cvImageBuffer: imageBuffer)
            
            if self.filter != nil {
                self.filter.setValue(outputImage, forKey: kCIInputImageKey)
                outputImage = self.filter.outputImage!
            }
            
            self.ciImage = outputImage
            if let detector = detector, borderDetectFrame{
                self.borderDetectLastRectangleFeature = biggestRectangle(detector.features(in: self.ciImage) as! [CIRectangleFeature])
                borderDetectFrame = false
            }
            
            if let rectangleFeature = self.borderDetectLastRectangleFeature {
                self.borderDetectFrame = false
                self.ciImage = self.perspectiveCorrectedImage(self.ciImage, feature: rectangleFeature)
                outputImage = self.overlayImageForFeatureInImage(outputImage, feature: rectangleFeature)
            }
            
            
            let orientation = UIDevice.current.orientation
            var t: CGAffineTransform!
            if orientation == UIDeviceOrientation.portrait {
                t = CGAffineTransform(rotationAngle: -CGFloat.pi / 2.0)
            } else if orientation == UIDeviceOrientation.portraitUpsideDown {
                t = CGAffineTransform(rotationAngle: CGFloat.pi / 2.0)
            } else if (orientation == UIDeviceOrientation.landscapeRight) {
                t = CGAffineTransform(rotationAngle: CGFloat.pi)
            } else {
                t = CGAffineTransform(rotationAngle: 0)
            }
            outputImage = outputImage.transformed(by: t)
            
            let cgImage = self.context.createCGImage(outputImage, from: outputImage.extent)
            
            DispatchQueue.main.async {
                self.previewLayer.contents = cgImage
            }
        }
    }
    
    func biggestRectangle(_ rectangles: [CIRectangleFeature]) -> CIRectangleFeature? {
        if rectangles.count == 0 {
            return nil
        }
        
        var biggestRectangle = rectangles.first!
        
        var halfPerimeterValue = 0.0
        
        for rectangle in rectangles {
            let p1 = rectangle.topLeft
            let p2 = rectangle.topRight
            let width = hypotf(Float(p1.x - p2.x), Float(p1.y - p2.y))
            
            let p3 = rectangle.bottomLeft
            let height = hypotf(Float(p1.x - p3.x), Float(p1.y - p3.y))
            
            let currentHalfPermiterValue = Double(height + width)
            if halfPerimeterValue < currentHalfPermiterValue {
                halfPerimeterValue = currentHalfPermiterValue
                biggestRectangle = rectangle
            }
        }
        return biggestRectangle
    }
    
    func perspectiveCorrectedImage(_ image: CIImage, feature: CIRectangleFeature) -> CIImage {
        return image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft":    CIVector(cgPoint: feature.topLeft),
            "inputTopRight":   CIVector(cgPoint: feature.topRight),
            "inputBottomLeft": CIVector(cgPoint: feature.bottomLeft),
            "inputBottomRight":CIVector(cgPoint: feature.bottomRight)])
    }
    
    fileprivate func overlayImageForFeatureInImage(_ image: CIImage, feature: CIRectangleFeature) -> CIImage! {
        var overlay = CIImage(color: CIColor(red: 0.2, green: 0.6, blue: 0.86, alpha: 0.5))
        overlay = overlay.cropped(to: image.extent)
        overlay = overlay.applyingFilter("CIPerspectiveTransformWithExtent",
                                         parameters: [
                "inputExtent": CIVector(cgRect: image.extent),
                "inputTopLeft": CIVector(cgPoint: feature.topLeft),
                "inputTopRight": CIVector(cgPoint: feature.topRight),
                "inputBottomLeft": CIVector(cgPoint: feature.bottomLeft),
                "inputBottomRight": CIVector(cgPoint: feature.bottomRight)]
        )
        return overlay.composited(over: image)
    }
}

