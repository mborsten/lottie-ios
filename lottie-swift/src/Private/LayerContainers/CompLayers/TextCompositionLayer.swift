//
//  TextCompositionLayer.swift
//  lottie-swift
//
//  Created by Brandon Withrow on 1/25/19.
//

import Foundation
import CoreGraphics
import QuartzCore
import CoreText

/// Needed for NSMutableParagraphStyle...
#if os(OSX)
import AppKit
#else
import UIKit
#endif

class DisabledTextLayer: CATextLayer {
  override func action(forKey event: String) -> CAAction? {
    return nil
  }
}

extension TextJustification {
  var textAlignment: NSTextAlignment {
    switch self {
    case .left:
      return .left
    case .right:
      return .right
    case .center:
      return .center
    }
  }
  
  var caTextAlignement: CATextLayerAlignmentMode {
    switch self {
    case .left:
      return .left
    case .right:
      return .right
    case .center:
      return .center
    }
  }
  
}

class TextCompositionLayer: CompositionLayer {
  
  let rootNode: TextAnimatorNode?
  let textDocument: KeyframeInterpolator<TextDocument>?
  let interpolatableAnchorPoint: KeyframeInterpolator<Vector3D>?
  let interpolatableScale: KeyframeInterpolator<Vector3D>?
  
  let textLayer: DisabledTextLayer = DisabledTextLayer()
  let textStrokeLayer: DisabledTextLayer = DisabledTextLayer()
  var textProvider: AnimationTextProvider
  
  init(textLayer: TextLayerModel, textProvider: AnimationTextProvider) {
    var rootNode: TextAnimatorNode?
    for animator in textLayer.animators {
      rootNode = TextAnimatorNode(parentNode: rootNode, textAnimator: animator)
    }
    self.rootNode = rootNode
    self.textDocument = KeyframeInterpolator(keyframes: textLayer.text.keyframes)
    
    self.textProvider = textProvider
    
    // TODO: this has to be somewhere that can be interpolated
    // TODO: look for inspiration from other composite layer
    self.interpolatableAnchorPoint = KeyframeInterpolator(keyframes: textLayer.transform.anchorPoint.keyframes)
    self.interpolatableScale = KeyframeInterpolator(keyframes: textLayer.transform.scale.keyframes)
    
    super.init(layer: textLayer, size: .zero)
    contentsLayer.addSublayer(self.textLayer)
    contentsLayer.addSublayer(self.textStrokeLayer)
    self.textLayer.masksToBounds = false
    self.textStrokeLayer.masksToBounds = false
    self.textLayer.isWrapped = true
    self.textStrokeLayer.isWrapped = true
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override init(layer: Any) {
    /// Used for creating shadow model layers. Read More here: https://developer.apple.com/documentation/quartzcore/calayer/1410842-init
    guard let layer = layer as? TextCompositionLayer else {
      fatalError("init(layer:) Wrong Layer Class")
    }
    self.rootNode = nil
    self.textDocument = nil
    
    self.textProvider = DefaultTextProvider()
    
    self.interpolatableAnchorPoint = nil
    self.interpolatableScale = nil
    
    super.init(layer: layer)
  }
  
  override func displayContentsWithFrame(frame: CGFloat, forceUpdates: Bool) {
    guard let textDocument = textDocument else { return }
    
    textLayer.contentsScale = self.renderScale
    textStrokeLayer.contentsScale = self.renderScale
    
    let documentUpdate = textDocument.hasUpdate(frame: frame)
    let animatorUpdate = rootNode?.updateContents(frame, forceLocalUpdate: forceUpdates) ?? false
    guard documentUpdate == true || animatorUpdate == true else { return }
    
    let text = textDocument.valueForFrame(frame) as! TextDocument
    let anchorPoint = interpolatableAnchorPoint?.valueForFrame(frame) as! Vector3D
    let scale = interpolatableScale?.valueForFrame(frame) as! Vector3D
    rootNode?.rebuildOutputs(frame: frame)
    
    let fillColor = rootNode?.textOutputNode.fillColor ?? text.fillColorData.cgColorValue
    let strokeColor = rootNode?.textOutputNode.strokeColor ?? text.strokeColorData?.cgColorValue
    let strokeWidth = rootNode?.textOutputNode.strokeWidth ?? CGFloat(text.strokeWidth ?? 0)
    let tracking = (CGFloat(text.fontSize) * (rootNode?.textOutputNode.tracking ?? CGFloat(text.tracking))) / 1000.0
    
    let matrix = rootNode?.textOutputNode.xform ?? CATransform3DIdentity
    let ctFont = CTFontCreateWithName(text.fontFamily as CFString, CGFloat(text.fontSize), nil)
    
    let textString = textProvider.textFor(keypathName: self.keypathName, sourceText: text.text)
    
    var attributes: [NSAttributedString.Key : Any] = [
      NSAttributedString.Key.font: ctFont,
      NSAttributedString.Key.foregroundColor: fillColor,
      NSAttributedString.Key.kern: tracking,
    ]
    
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.lineSpacing = CGFloat(text.lineHeight)
    paragraphStyle.alignment = text.justification.textAlignment
    attributes[NSAttributedString.Key.paragraphStyle] = paragraphStyle
    
    let baseAttributedString = NSAttributedString(string: textString, attributes: attributes )
    
    if let strokeColor = strokeColor {
      textStrokeLayer.isHidden = false
      attributes[NSAttributedString.Key.strokeColor] = strokeColor
      attributes[NSAttributedString.Key.strokeWidth] = strokeWidth
    } else {
      textStrokeLayer.isHidden = true
    }
    
    let size: CGSize
    let attributedString: NSAttributedString = NSAttributedString(string: textString, attributes: attributes )
    
    if let frameSize = text.textFrameSize {
      size = CGSize(width: frameSize.x, height: frameSize.y)
    } else {
      let framesetter = CTFramesetterCreateWithAttributedString(attributedString)
      
      size = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                                                          CFRange(location: 0,length: 0),
                                                          nil,
                                                          CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                                 height: CGFloat.greatestFiniteMagnitude),
                                                          nil)
    }
    
    let baselinePosition = CTFontGetAscent(ctFont)
    let textAnchor: CGPoint
    switch text.justification {
    case .left:
      textAnchor = CGPoint(x: 0, y: baselinePosition)
    case .right:
      textAnchor = CGPoint(x: size.width, y: baselinePosition)
    case .center:
      textAnchor = CGPoint(x: size.width * 0.5, y: baselinePosition)
    }
    let anchor = textAnchor + anchorPoint.pointValue
    let normalizedAnchor = CGPoint(x: anchor.x.remap(fromLow: 0, fromHigh: size.width, toLow: 0, toHigh: 1),
                                   y: anchor.y.remap(fromLow: 0, fromHigh: size.height, toLow: 0, toHigh: 1))
    
    if textStrokeLayer.isHidden == false {
      if text.strokeOverFill ?? false {
        textStrokeLayer.removeFromSuperlayer()
        contentsLayer.addSublayer(textStrokeLayer)
      } else {
        textLayer.removeFromSuperlayer()
        contentsLayer.addSublayer(textLayer)
      }
      textStrokeLayer.anchorPoint = normalizedAnchor
      textStrokeLayer.opacity = Float(rootNode?.textOutputNode.opacity ?? 1)
      textStrokeLayer.transform = CATransform3DIdentity
      textStrokeLayer.frame = CGRect(origin: .zero, size: size)
      textStrokeLayer.position = text.textFramePosition?.pointValue ?? CGPoint.zero
      textStrokeLayer.transform = matrix
      textStrokeLayer.string = attributedString
      textStrokeLayer.alignmentMode = text.justification.caTextAlignement
    }
    
    textLayer.anchorPoint = normalizedAnchor
    textLayer.opacity = Float(rootNode?.textOutputNode.opacity ?? 1)
    textLayer.transform = CATransform3DIdentity
    textLayer.frame = CGRect(origin: .zero, size: size)
    textLayer.position = text.textFramePosition?.pointValue ?? CGPoint.zero
    textLayer.transform = matrix
    textLayer.string = baseAttributedString
    textLayer.alignmentMode = text.justification.caTextAlignement
  }
}
