//
//  IIAutoDetectorCapture.swift
//  CaptureDetector
//
//  Created by Adolph on 2018/5/23.
//  Copyright © 2018年 iceboxi. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

class IIAutoDetectorCapture: NSObject {
    var captureSession: AVCaptureSession = AVCaptureSession()
    lazy var previewLayer: CALayer = {
        let layer = CALayer()
        layer.anchorPoint = CGPoint.zero
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
    var borderDetectColor: UIColor = UIColor(red: 0.2, green: 0.6, blue: 0.86, alpha: 0.5)
    var borderDetectLastRectangleFeature: CIRectangleFeature?
    
    init(with superView: UIView) {
        super.init()
        previewLayer.bounds = superView.bounds
    }
    
    @objc func enableBorderDetection() {
        self.borderDetectFrame = true
    }
    
    func startRunning() {
        captureSession.startRunning()
        timeKeeper = Timer.scheduledTimer(timeInterval: 0.5, target: self, selector: #selector(IIAutoDetectorCapture.enableBorderDetection), userInfo: nil, repeats: true)
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
        
        captureSession.commitConfiguration()
        
        if (self.currentDevice?.isFocusModeSupported(.continuousAutoFocus))! {
            try! self.currentDevice?.lockForConfiguration()
            self.currentDevice?.focusMode = .continuousAutoFocus
            self.currentDevice?.unlockForConfiguration()
        }
    }
    
    func takePicture() {
        if ciImage == nil || isWriting {
            return
        }
        captureSession.stopRunning()
        
        let cgImage = context.createCGImage(ciImage, from: ciImage.extent)
        ALAssetsLibrary().writeImage(toSavedPhotosAlbum: cgImage, metadata: ciImage.properties) { (url, error) in
            if error == nil {
                print("保存成功")
                print(url!)
            } else {
                // TODO: add error block?
            }
            self.captureSession.startRunning()
        }
    }
}

extension IIAutoDetectorCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool {
            let sampleBufferValid: Bool = CMSampleBufferIsValid(sampleBuffer)
            if !sampleBufferValid {
                return
            }
            
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
            
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
            
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
                self.ciImage = crop(self.ciImage, by: rectangleFeature)
                outputImage = drawOverlay(on: outputImage, with: rectangleFeature)
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
}

// MARK: - Crop Image
extension IIAutoDetectorCapture {
    func crop(_ image: CIImage, by feature: CIRectangleFeature) -> CIImage! {
        return crop(image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
    }
    
    func crop(_ image: CIImage, by feature: CIQRCodeFeature) -> CIImage! {
        return crop(image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
    }
    
    func crop(_ image: CIImage, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        return image.applyingFilter("CIPerspectiveCorrection", parameters: [
            "inputTopLeft":    CIVector(cgPoint: topLeft),
            "inputTopRight":   CIVector(cgPoint: topRight),
            "inputBottomLeft": CIVector(cgPoint: bottomLeft),
            "inputBottomRight":CIVector(cgPoint: bottomRight)])
    }
}

// MARK: - CIDetector
extension IIAutoDetectorCapture {
    func prepareRectangleDetector() -> CIDetector {
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh, CIDetectorAspectRatio: 1.0]
        return CIDetector(ofType: CIDetectorTypeRectangle, context: nil, options: options)!
    }
    
    func prepareQRCodeDetector() -> CIDetector {
        let options = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        return CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: options)!
    }
    
    func drawOverlay(on image: CIImage, with feature: CIRectangleFeature) -> CIImage! {
        return drawOverlay(on: image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
    }
    
    func drawOverlay(on image: CIImage, with feature: CIQRCodeFeature) -> CIImage! {
        return drawOverlay(on: image, topLeft: feature.topLeft, topRight: feature.topRight, bottomLeft: feature.bottomLeft, bottomRight: feature.bottomRight)
    }
    
    func drawOverlay(on image: CIImage, topLeft: CGPoint, topRight: CGPoint, bottomLeft: CGPoint, bottomRight: CGPoint) -> CIImage {
        var overlay = CIImage(color: CIColor(color: borderDetectColor))
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
                resultImage = drawOverlay(on: image, with: feature)
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
                resultImage = drawOverlay(on: image, with: feature)
                decode = feature.messageString!
            }
        }
        return (resultImage, decode)
    }
}
