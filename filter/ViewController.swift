//
//  ViewController.swift
//  filter
//
//  Created by Ricol Wang on 22/7/20.
//  Copyright © 2020 DeepSpace. All rights reserved.
//

import UIKit
import KinsaGradientSlider

typealias TFun = () -> CGImage?
typealias TFilter = (CGFloat, CGFloat, CGFloat) -> CGImage?
typealias TComplete = (UIImage) -> Void
typealias TCalculateColor = (UIColor, UIColor, CGFloat) -> UIColor
typealias TGradientSliderUpdate =  (GradientSlider, CGFloat, Bool) -> Void

class ViewController: UIViewController
{
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var sliderHue: GradientSlider!
    @IBOutlet weak var sliderSaturation: GradientSlider!
    @IBOutlet weak var sliderBrightness: GradientSlider!
    @IBOutlet weak var btnReset: UIButton!
    @IBOutlet weak var btnPreview: UIButton!
    @IBOutlet weak var btnUndo: UIButton!
    @IBOutlet weak var btnRedo: UIButton!
    @IBOutlet weak var lblHue: UILabel!
    @IBOutlet weak var lblSaturation: UILabel!
    @IBOutlet weak var lblBrightness: UILabel!
    @IBOutlet weak var viewEffect: UIVisualEffectView!
    
    let image = UIImage(named: "Neon-Source.png")! //load the default png, if necessary, we can resize the image and apply filters on a smaller png to improve performance.
    let context = CIContext()
    let filterHue = CIFilter(name: "CIHueAdjust")! //filter for Hue
    let filterSaturationAndBrightness = CIFilter(name: "CIColorControls")! //filter for saturation and brightness
    let significant_change: CGFloat = 0.05 //only change greater than this can triggle the filter
    let thumb_size_normal: CGFloat = 10 //normal value for slider thumb size
    let thumb_size_big: CGFloat = 50 //big value for slider thumb size while moving the slider
    let queue = OperationQueue() //operation queue for filter operation
    
    var ciimage: CIImage!
    var hue: CGFloat = 0.5 //default value for hue
    var saturation: CGFloat = 0.5 //default value for saturation
    var brightness: CGFloat = 0 //default value for brightness
    var slider_values: [GradientSlider: CGFloat]! //dictionary for finding value for each slider
    var slider_colors: [GradientSlider: TCalculateColor]! //dictionary for finding color updating closure for each slider
    var previous_operation: FilterOperation? //track previous operation to avoid unneccessary image update
    var apply_filter: TFilter? //the filter closure
    var action_block: TGradientSliderUpdate? //the closure for updating thumb color while moving the slider
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        
        imageView.image = image
        ciimage = CIImage(image: image)
        
        //load ciimage as the input source of the filters
        filterHue.setValue(ciimage, forKey: kCIInputImageKey)
        
        //this is the closure that will apply filters on the image
        apply_filter = { (hue, saturation, brightness) in
            self.filterHue.setValue(hue * 2 * CGFloat.pi, forKey: kCIInputAngleKey)
            self.filterSaturationAndBrightness.setValue(self.filterHue.outputImage, forKey: kCIInputImageKey)
            self.filterSaturationAndBrightness.setValue(saturation, forKey: kCIInputSaturationKey)
            self.filterSaturationAndBrightness.setValue(brightness, forKey: kCIInputBrightnessKey)
            if let output = self.filterSaturationAndBrightness.outputImage { return self.context.createCGImage(output, from: output.extent) }
            return nil
        }
        
        //these are functions for calculating the thumb color while moving the sliders
        //calcuate thumb color for sliderHue
        func calculate_hue_color(min: UIColor, max: UIColor, value: CGFloat) -> UIColor
        {
            return UIColor(hue: value, saturation: 1, brightness: 1, alpha: 1)
        }
        
        //calculate thumb color for sliderSaturation
        func calculate_saturation_color(min: UIColor, max: UIColor, value: CGFloat) -> UIColor
        {
            return UIColor(hue: 0, saturation: value, brightness: 1, alpha: 1)
        }
        
        //calculate thumb color for sliderBrightness
        func calcualte_brightness_color(min: UIColor, max: UIColor, value: CGFloat) -> UIColor
        {
            var saturation_min: CGFloat = 0, saturation_max: CGFloat = 0, brightness_min: CGFloat = 0, brightness_max: CGFloat = 0
            min.getHue(nil, saturation: &saturation_min, brightness: &brightness_min, alpha: nil)
            max.getHue(nil, saturation: &saturation_max, brightness: &brightness_max, alpha: nil)
            return UIColor(hue: 0, saturation: (saturation_max - saturation_min) * (value - (-1)) / 2.0 + saturation_min, brightness: (brightness_max - brightness_min) * (value - (-1)) / 2.0 + brightness_min, alpha: 1)
        }
        
        slider_colors = [sliderHue: calculate_hue_color(min:max:value:), sliderSaturation: calculate_saturation_color(min:max:value:), sliderBrightness: calcualte_brightness_color(min:max:value:)]
        
        //define closure for updating slider thumb color and its size while moving the slider
        let block: TGradientSliderUpdate = { slider, value, finished in
            slider.thumbColor = self.slider_colors[slider]?(slider.minColor, slider.maxColor, slider.value) ?? UIColor.white
            slider.thumbSize = finished ? self.thumb_size_normal : self.thumb_size_big
            slider.thumbInternalViewSizePercentage = 100
        }
        sliderHue.actionBlock = block
        sliderSaturation.actionBlock = block
        sliderBrightness.actionBlock = block
        self.action_block = block
        
        //create a blue effect view as the background for the bottom control view
        viewEffect.effect = UIBlurEffect(style: .dark)
    }
    
    override func viewWillAppear(_ animated: Bool)
    {
        super.viewWillAppear(animated)
        
        for btn in [btnUndo, btnReset, btnRedo, btnPreview] { btn?.roundCorner() }
        btnResetOnTapped(nil)
    }
    
    override var preferredStatusBarStyle: UIStatusBarStyle
    {
        return .lightContent
    }
    
    // MARK: - IBAction Methods
    
    @IBAction func onSliderValueChanged(_ sender: GradientSlider)
    {
        let percentage = sender.value / sender.maximumValue
        slider_values = [sliderHue: hue, sliderSaturation: saturation, sliderBrightness: brightness]
        if abs(percentage - slider_values[sender]!) < significant_change { return } //only changes greater than the significant_change will apply filter
        
        hue = sliderHue.value
        saturation = sliderSaturation.value
        brightness = sliderBrightness.value
        
        //define an operation and run in operation queue
        let operation = FilterOperation()
        print("[\(operation)]: Applying...H: \(hue), S: \(saturation), B: \(brightness)")
        
        //define the closure that will apply filters and run in background to avoid blocking UI
        operation.fun = { () -> CGImage? in
            return self.apply_filter?(self.hue, self.saturation, self.brightness)
        }
        
        //complete closure. once the operation finishes, it will return an image(UIImage).
        operation.complete = { image in
            if operation == self.previous_operation //only show latest updated image, no need to show older image
            {
                DispatchQueue.main.async {
                    self.imageView.image = image
                    print("[\(operation)]: Complete.")
                }
            }else
            {
                print("[\(operation)]: not the same operation. ignored...")
            }
        }
        
        queue.cancelAllOperations() //cancel all previous operations in the queue. no needed anymore
        previous_operation = operation
        queue.addOperation(operation)
    }
    
    @IBAction func btnResetOnTapped(_ sender: Any?)
    {
        //cancel all operations in the queue
        queue.cancelAllOperations()
        //reset image
        imageView.image = image
        previous_operation = nil
        hue = 0.5
        saturation = 0.5
        brightness = 0
        //update sliders
        sliderHue.value = hue
        sliderSaturation.value = saturation
        sliderBrightness.value = brightness
        self.action_block?(sliderHue, sliderHue.value, true)
        self.action_block?(sliderSaturation, sliderSaturation.value, true)
        self.action_block?(sliderBrightness, sliderBrightness.value, true)
    }
}

class FilterOperation: Operation
{
    var complete: TComplete?
    var fun: TFun?
    
    override func start()
    {
        if let output = fun?()
        {
            if !isCancelled
            {
                complete?(UIImage(cgImage: output))
            }else
            {
                print("[\(self)]: cancelled.")
            }
        }
    }
}

extension UIButton
{
    func roundCorner(value: CGFloat = 5)
    {
        self.layer.cornerRadius = value
        self.layer.masksToBounds = true
    }
}
