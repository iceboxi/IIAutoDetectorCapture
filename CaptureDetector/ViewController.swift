//
//  ViewController.swift
//  CaptureDetector
//
//  Created by Adolph on 2018/5/23.
//  Copyright © 2018年 iceboxi. All rights reserved.
//

import UIKit

class ViewController: UIViewController {
    @IBOutlet weak var detectorModeSelector: UISegmentedControl!
    
    var capture: IIAutoDetectorCapture!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if TARGET_OS_SIMULATOR != 0 {
            let alert = UIAlertController(title: "提示", message: "不支援模擬器", preferredStyle: .alert)
            self.present(alert, animated: true, completion: nil)
        } else {
            capture = IIAutoDetectorCapture(with: self.view)
            self.view.layer.insertSublayer(capture.previewLayer, at: 0)
            capture.setupCaptureSession()
            capture.startRunning()
            
            detectorModeSelector.selectedSegmentIndex = 0
            handleDetectorSelectionChange(detectorModeSelector)
        }
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        capture.previewLayer.bounds.size = size
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func handleDetectorSelectionChange(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 0:
            capture.detector = capture.prepareRectangleDetector()
            break
        case 1:
            capture.detector = capture.prepareQRCodeDetector()
            break
        default:
            print("")
        }
    }
    
    @IBAction func takePicture(_ sender: UIButton) {
        capture.takePicture()
    }
}


