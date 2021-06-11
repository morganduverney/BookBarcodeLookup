//
//  ViewController.swift
//  BookBarcodeLookup
//
//  Created by Morgan Duverney on 6/11/21.
//

// Find related tutorial at https://www.raywenderlich.com/12663654-vision-framework-tutorial-for-ios-scanning-barcodes
// This project has been altered from original tutorial for a different use case

import UIKit
import Vision
import AVFoundation
import SafariServices

class ViewController: UIViewController {
  // MARK: - Private Variables
  var captureSession = AVCaptureSession()

  // create vision request
  lazy var detectBarcodeRequest = VNDetectBarcodesRequest { request, error in
    guard error == nil else {
      self.showAlert(withTitle: "Barcode error", message: error?.localizedDescription ?? "error")
      return
    }
    self.processClassification(request)
  }

  // MARK: - Override Functions
  override func viewDidLoad() {
    super.viewDidLoad()
    checkPermissions()
    setupCameraLiveView()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    captureSession.stopRunning()
  }
}


extension ViewController {
  // MARK: - Camera
  private func checkPermissions() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [self] granted in
        if !granted {
          showPermissionsAlert()
        }
      }
    case .denied, .restricted:
      showPermissionsAlert()
    default:
      return
    }
  }

  private func setupCameraLiveView() {
    //  set session quality
    captureSession.sessionPreset = .hd1280x720
    
    // ensure capture device is available for input
    let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    guard let device = videoDevice,
          let videoDeviceInput = try? AVCaptureDeviceInput(device: device), captureSession.canAddInput(videoDeviceInput)
    else {
      showAlert(withTitle: "Unable to find camera", message: "There seems to be a problem with the camera on your device.")
      return
    }
    
    // set capture device as input
    captureSession.addInput(videoDeviceInput)
    
    // create output location for video input
    let captureOutput = AVCaptureVideoDataOutput()
    
    // set up video feed for vision framework
    captureOutput.videoSettings =
      [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
    captureOutput.setSampleBufferDelegate(
      self,
      queue: DispatchQueue.global(qos: DispatchQoS.QoSClass.default))
    
     // add output to session
    captureSession.addOutput(captureOutput)
    
    // configure view for camera
    configurePreviewLayer()
    
    // run the capture session
    captureSession.startRunning()
  }

  // MARK: - Vision
  func processClassification(_ request: VNRequest) {
    // store results of the barcode request
    guard let barcodes = request.results else { return }
    DispatchQueue.main.async { [self] in
      if captureSession.isRunning {
        view.layer.sublayers?.removeSubrange(1...)
        
        for barcode in barcodes {
          // cast potential barcode as VNBarcodeObservation and is a barcode with high confidence
          guard let potentialBarcode = barcode as? VNBarcodeObservation,
                potentialBarcode.confidence > 0.9,
                // ensure that the barcode is the type expected (in this case a 13-digit ISBN for a book)
                // https://developer.apple.com/documentation/vision/vnbarcodesymbology
                potentialBarcode.symbology == .EAN13
                else { return }
          observationHandler(payload: potentialBarcode.payloadStringValue)
        }
      }
    }
  }

  // MARK: - Handler
  func observationHandler(payload: String?) {
    // create url from ISBN in payload
    guard let payloadString = payload,
          let url = URL(string: "https://www.barcodelookup.com/\(payloadString)") else { return }
    // open safari at detail page for relevant product
    let safariVC = SFSafariViewController(url: url)
    safariVC.delegate = self
    present(safariVC, animated: true, completion: nil)
  }
}


// MARK: - AVCaptureDelegation
// conform to AVCaptureVideoDataOutputSampleBufferDelegate for video feed configuration
extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    // get image from the sample
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
      return
    }
    // create request handler with the image
    let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
    // perform detectBarcodeRequest with the handler and catch error as needed
    do {
      try imageRequestHandler.perform([detectBarcodeRequest])
    } catch {
      print(error)
    }
  }
}


// MARK: - Helper
// UI stuff
extension ViewController {
  private func configurePreviewLayer() {
    let cameraPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    cameraPreviewLayer.videoGravity = .resizeAspectFill
    cameraPreviewLayer.connection?.videoOrientation = .portrait
    cameraPreviewLayer.frame = view.frame
    view.layer.insertSublayer(cameraPreviewLayer, at: 0)
  }

  private func showAlert(withTitle title: String, message: String) {
    DispatchQueue.main.async {
      let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
      alertController.addAction(UIAlertAction(title: "OK", style: .default))
      self.present(alertController, animated: true)
    }
  }

  private func showPermissionsAlert() {
    showAlert(
      withTitle: "Camera Permissions",
      message: "Please open Settings and grant permission for this app to use your camera.")
  }
}


// MARK: - SafariViewControllerDelegate
extension ViewController: SFSafariViewControllerDelegate {
  func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
    captureSession.startRunning()
  }
}
