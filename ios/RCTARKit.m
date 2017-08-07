//
//  RCTARKit.m
//  RCTARKit
//
//  Created by HippoAR on 7/9/17.
//  Copyright © 2017 HippoAR. All rights reserved.
//

#import "RCTARKit.h"
#import "Plane.h"
@import CoreLocation;

#if __has_include("RCTARKitARCL.h")
#define MODE_ARCL 1
//#import "RCTARKit+ARCL.h"
#import <ARCL/ARCL-Swift.h>
@class SceneLocationView;
//@class LocationNode;
//@class LocationAnnotationNode;
#endif

@interface RCTARKit () <ARSCNViewDelegate> {
    RCTPromiseResolveBlock _resolve;
}

@end


@implementation RCTARKit

+ (instancetype)sharedInstance {
    static RCTARKit *instance = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        if (instance == nil) {
            ARSCNView *arView = [[ARSCNView alloc] init];
            instance = [[self alloc] initWithARView:arView];
        }
    });

    return instance;
}

- (instancetype)initWithARView:(ARSCNView *)arView {
    if ((self = [super init])) {
        self.arView = arView;

        // delegates
        self.arView.delegate = self;
        self.arView.session.delegate = self;

        // configuration(s)
        self.arView.autoenablesDefaultLighting = YES;
        self.arView.scene.rootNode.name = @"root";

        // local reference frame origin
        self.localOrigin = [[SCNNode alloc] init];
        self.localOrigin.name = @"localOrigin";
        [self.arView.scene.rootNode addChildNode:self.localOrigin];

        // camera reference frame origin
        self.cameraOrigin = [[SCNNode alloc] init];
        self.cameraOrigin.name = @"cameraOrigin";
        [self.arView.scene.rootNode addChildNode:self.cameraOrigin];

        // init cahces
        self.nodes = [NSMutableDictionary new];
        self.planes = [NSMutableDictionary new];

        // start ARKit
        [self addSubview:self.arView];
        [self resume];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.arView.frame = self.bounds;
}

- (void)pause {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView pause];
#else
    [self.session pause];
#endif
}

- (void)resume {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView run];
#else
    [self.session runWithConfiguration:self.configuration];
#endif
}


#pragma mark - setter-getter

- (ARSession*)session {
    return self.arView.session;
}

- (BOOL)debug {
    return self.arView.showsStatistics;
}

- (void)setDebug:(BOOL)debug {
    if (debug) {
        self.arView.showsStatistics = YES;
        self.arView.debugOptions = ARSCNDebugOptionShowWorldOrigin | ARSCNDebugOptionShowFeaturePoints;
    } else {
        self.arView.showsStatistics = NO;
        self.arView.debugOptions = SCNDebugOptionNone;
    }
}

- (BOOL)planeDetection {
    ARWorldTrackingSessionConfiguration *configuration = self.session.configuration;
    return configuration.planeDetection == ARPlaneDetectionHorizontal;
}

- (void)setPlaneDetection:(BOOL)planeDetection {
    // plane detection is on by default for ARCL and cannot be configured for now
    ARWorldTrackingSessionConfiguration *configuration = self.session.configuration;
    if (planeDetection) {
        configuration.planeDetection = ARPlaneDetectionHorizontal;
    } else {
        configuration.planeDetection = ARPlaneDetectionNone;
    }
    [self resume];
}

- (BOOL)lightEstimation {
    ARSessionConfiguration *configuration = self.session.configuration;
    return configuration.lightEstimationEnabled;
}

- (void)setLightEstimation:(BOOL)lightEstimation {
    // light estimation is on by default for ARCL and cannot be configured for now
    ARSessionConfiguration *configuration = self.session.configuration;
    configuration.lightEstimationEnabled = lightEstimation;
    [self resume];
}

- (NSDictionary *)readCameraPosition {
    return @{
             @"x": @(self.cameraOrigin.position.x),
             @"y": @(self.cameraOrigin.position.y),
             @"z": @(self.cameraOrigin.position.z)
             };
}

#pragma mark - Lazy loads

-(ARWorldTrackingSessionConfiguration *)configuration {
    if (_configuration) {
        return _configuration;
    }

    if (!ARWorldTrackingSessionConfiguration.isSupported) {}

    _configuration = [ARWorldTrackingSessionConfiguration new];
    _configuration.planeDetection = ARPlaneDetectionHorizontal;
    return _configuration;
}


#pragma mark - methods

- (void)thisImage:(UIImage *)image savedInAlbumWithError:(NSError *)error ctx:(void *)ctx {
    if (error) {
    } else {
        _resolve(@{ @"success": @(YES) });
    }
}

- (void)snapshot:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
    UIImage *image = [self.arView snapshot];
    _resolve = resolve;
    UIImageWriteToSavedPhotosAlbum(image, self, @selector(thisImage:savedInAlbumWithError:ctx:), NULL);
}

- (void)addBox:(NSDictionary *)property {
    float width = [property[@"width"] floatValue];
    float height = [property[@"height"] floatValue];
    float length = [property[@"length"] floatValue];
    float chamfer = [property[@"chamfer"] floatValue];

    SCNBox *geometry = [SCNBox boxWithWidth:width height:height length:length chamferRadius:chamfer];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addSphere:(NSDictionary *)property {
    float radius = [property[@"radius"] floatValue];

    SCNSphere *geometry = [SCNSphere sphereWithRadius:radius];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCylinder:(NSDictionary *)property {
    float radius = [property[@"radius"] floatValue];
    float height = [property[@"height"] floatValue];

    SCNCylinder *geometry = [SCNCylinder cylinderWithRadius:radius height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCone:(NSDictionary *)property {
    float topR = [property[@"topR"] floatValue];
    float bottomR = [property[@"bottomR"] floatValue];
    float height = [property[@"height"] floatValue];

    SCNCone *geometry = [SCNCone coneWithTopRadius:topR bottomRadius:bottomR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addPyramid:(NSDictionary *)property {
    float width = [property[@"width"] floatValue];
    float length = [property[@"length"] floatValue];
    float height = [property[@"height"] floatValue];

    SCNPyramid *geometry = [SCNPyramid pyramidWithWidth:width height:height length:length];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addTube:(NSDictionary *)property {
    float innerR = [property[@"innerR"] floatValue];
    float outerR = [property[@"outerR"] floatValue];
    float height = [property[@"height"] floatValue];
    SCNTube *geometry = [SCNTube tubeWithInnerRadius:innerR outerRadius:outerR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addTorus:(NSDictionary *)property {
    float ringR = [property[@"ringR"] floatValue];
    float pipeR = [property[@"pipeR"] floatValue];

    SCNTorus *geometry = [SCNTorus torusWithRingRadius:ringR pipeRadius:pipeR];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addCapsule:(NSDictionary *)property {
    float capR = [property[@"capR"] floatValue];
    float height = [property[@"height"] floatValue];

    SCNCapsule *geometry = [SCNCapsule capsuleWithCapRadius:capR height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addPlane:(NSDictionary *)property {
    float width = [property[@"width"] floatValue];
    float height = [property[@"height"] floatValue];

    SCNPlane *geometry = [SCNPlane planeWithWidth:width height:height];
    SCNNode *node = [SCNNode nodeWithGeometry:geometry];
    [self addNodeToScene:node property:property];
}

- (void)addText:(NSDictionary *)property {
    // init SCNText
    NSString *text = property[@"text"];
    CGFloat depth = [property[@"depth"] floatValue];
    if (!text) {
        text = @"(null)";
    }
    if (!depth) {
        depth = 0.0f;
    }
    float fontSize = [property[@"fontSize"] floatValue];
    float size = fontSize / 12;
    SCNText *scnText = [SCNText textWithString:text extrusionDepth:depth / size];
    scnText.flatness = 0.1;

    // font
    NSString *font = property[@"font"];
    if (font) {
        scnText.font = [UIFont fontWithName:font size:12];
    } else {
        scnText.font = [UIFont systemFontOfSize:12];
    }

    // chamfer
    float chamfer = [property[@"chamfer"] floatValue];
    if (!chamfer) {
        chamfer = 0.0f;
    }
    scnText.chamferRadius = chamfer / size;

    // color
    CGFloat r = [property[@"r"] floatValue];
    CGFloat g = [property[@"g"] floatValue];
    CGFloat b = [property[@"b"] floatValue];
    if (!r) {
        r = 0.0f;
    }
    if (!g) {
        g = 0.0f;
    }
    if (!b) {
        b = 0.0f;
    }
    SCNMaterial *face = [SCNMaterial new];
    face.diffuse.contents = [[UIColor alloc] initWithRed:r green:g blue:b alpha:1.0f];
    SCNMaterial *border = [SCNMaterial new];
    border.diffuse.contents = [[UIColor alloc] initWithRed:r green:g blue:b alpha:1.0f];
    scnText.materials = @[face, face, border, border, border];

    // init SCNNode
    SCNNode *textNode = [SCNNode nodeWithGeometry:scnText];

    // position textNode
    SCNVector3 min, max;
    [textNode getBoundingBoxMin:&min max:&max];
    textNode.position = SCNVector3Make(-(min.x + max.x) / 2, -(min.y + max.y) / 2, -(min.z + max.z) / 2);

    SCNNode *textOrigin = [[SCNNode alloc] init];
    [textOrigin addChildNode:textNode];
    textOrigin.scale = SCNVector3Make(size, size, size);
    [self addNodeToScene:textOrigin property:property];
}

- (void)addModel:(NSDictionary *)property {
    float scale = [property[@"scale"] floatValue];

    SCNNode *node = [self loadModel:property[@"file"] nodeName:property[@"nodeName"] withAnimation:YES];
    node.scale = SCNVector3Make(scale, scale, scale);
    [self addNodeToScene:node property:property];
}


#pragma mark - Executors of adding node to scene

- (void)addNodeToScene:(SCNNode *)node property:(NSDictionary *)property {
    node.position = [self getPositionFromProperty:property];

    NSString *key = [NSString stringWithFormat:@"%@", property[@"id"]];
    if (key) {
        [self registerNode:node forKey:key];
    }
    [self.localOrigin addChildNode:node];
}

- (SCNVector3)getPositionFromProperty:(NSDictionary *)property {
    float x = [property[@"x"] floatValue];
    float y = [property[@"y"] floatValue];
    float z = [property[@"z"] floatValue];

    if (property[@"x"] == NULL) {
        x = self.cameraOrigin.position.x - self.localOrigin.position.x;
    }
    if (property[@"y"] == NULL) {
        y = self.cameraOrigin.position.y - self.localOrigin.position.y;
    }
    if (property[@"z"] == NULL) {
        z = self.cameraOrigin.position.z - self.localOrigin.position.z;
    }

    return SCNVector3Make(x, y, z);
}

- (void)moveNodeToReferenceFrame:(NSDictionary *)property {}

#pragma mark - Node register

- (void)registerNode:(SCNNode *)node forKey:(NSString *)key {
    [self removeNodeForKey:key];
    [self.nodes setObject:node forKey:key];
}

- (SCNNode *)nodeForKey:(NSString *)key {
    return [self.nodes objectForKey:key];
}

- (void)removeNodeForKey:(NSString *)key {
    SCNNode *node = [self.nodes objectForKey:key];
    if (node == nil) {
        return;
    }
    [node removeFromParentNode];
    [self.nodes removeObjectForKey:key];
}

#pragma mark - Model loader

- (SCNNode *)loadModel:(NSString *)path nodeName:(NSString *)nodeName withAnimation:(BOOL)withAnimation {
    SCNScene *scene = [SCNScene sceneNamed:path];
    SCNNode *node;
    if (nodeName) {
        node = [scene.rootNode childNodeWithName:nodeName recursively:YES];
    } else {
        NSArray *nodeArray = [scene.rootNode childNodes];
        for (SCNNode *eachChild in nodeArray) {
            [node addChildNode:eachChild];
        }
    }

    if (withAnimation) {
        NSMutableArray *animationMutableArray = [NSMutableArray array];
        NSURL *url = [[NSBundle mainBundle] URLForResource:path withExtension:@"dae"];
        SCNSceneSource *sceneSource = [SCNSceneSource sceneSourceWithURL:url options:@{SCNSceneSourceAnimationImportPolicyKey:SCNSceneSourceAnimationImportPolicyPlayRepeatedly} ];

        NSArray *animationIds = [sceneSource identifiersOfEntriesWithClass:[CAAnimation class]];
        for (NSString *eachId in animationIds){
            CAAnimation *animation = [sceneSource entryWithIdentifier:eachId withClass:[CAAnimation class]];
            [animationMutableArray addObject:animation];
        }
        NSArray *animationArray = [NSArray arrayWithArray:animationMutableArray];

        int i = 1;
        for (CAAnimation *animation in animationArray){
            NSString *key = [NSString stringWithFormat:@"ANIM_%d", i];
            [node addAnimation:animation forKey:key];
            i++;
        }
    }

    return node;
}

#pragma mark - ARSCNViewDelegate

- (void)renderer:(id <SCNSceneRenderer>)renderer didAddNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    if (![anchor isKindOfClass:[ARPlaneAnchor class]]) {
        return;
    }

    SCNNode *parent = [node parentNode];
    NSLog(@"plane detected");
    //    NSLog(@"%f %f %f", parent.position.x, parent.position.y, parent.position.z);

    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    //    NSLog(@"%@", @{
    //            @"id": planeAnchor.identifier.UUIDString,
    //            @"alignment": @(planeAnchor.alignment),
    //            @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
    //            @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
    //            @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
    //            @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
    //            });

    if (self.onPlaneDetected) {
        self.onPlaneDetected(@{
                               @"id": planeAnchor.identifier.UUIDString,
                               @"alignment": @(planeAnchor.alignment),
                               @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
                               @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
                               @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
                               @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
                               });
    }

    Plane *plane = [[Plane alloc] initWithAnchor: (ARPlaneAnchor *)anchor isHidden: NO];
    [self.planes setObject:plane forKey:anchor.identifier];
    [node addChildNode:plane];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer willUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didUpdateNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    ARPlaneAnchor *planeAnchor = (ARPlaneAnchor *)anchor;

    SCNNode *parent = [node parentNode];
    //    NSLog(@"%@", parent.name);
    //    NSLog(@"%f %f %f", node.position.x, node.position.y, node.position.z);
    //    NSLog(@"%f %f %f %f", node.rotation.x, node.rotation.y, node.rotation.z, node.rotation.w);


    //    NSLog(@"%@", @{
    //                   @"id": planeAnchor.identifier.UUIDString,
    //                   @"alignment": @(planeAnchor.alignment),
    //                   @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
    //                   @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
    //                   @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
    //                   @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
    //                   });

    if (self.onPlaneUpdate) {
        self.onPlaneUpdate(@{
                             @"id": planeAnchor.identifier.UUIDString,
                             @"alignment": @(planeAnchor.alignment),
                             @"node": @{ @"x": @(node.position.x), @"y": @(node.position.y), @"z": @(node.position.z) },
                             @"center": @{ @"x": @(planeAnchor.center.x), @"y": @(planeAnchor.center.y), @"z": @(planeAnchor.center.z) },
                             @"extent": @{ @"x": @(planeAnchor.extent.x), @"y": @(planeAnchor.extent.y), @"z": @(planeAnchor.extent.z) },
                             @"camera": @{ @"x": @(self.cameraOrigin.position.x), @"y": @(self.cameraOrigin.position.y), @"z": @(self.cameraOrigin.position.z) }
                             });
    }

    Plane *plane = [self.planes objectForKey:anchor.identifier];
    if (plane == nil) {
        return;
    }

    [plane update:(ARPlaneAnchor *)anchor];
}

- (void)renderer:(id <SCNSceneRenderer>)renderer didRemoveNode:(SCNNode *)node forAnchor:(ARAnchor *)anchor {
    [self.planes removeObjectForKey:anchor.identifier];
}


- (void)renderer:(id <SCNSceneRenderer>)renderer didRenderScene:(SCNScene *)scene atTime:(NSTimeInterval)time {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView renderer:renderer didRenderScene:scene atTime:time];
#endif
}


#pragma mark - ARSessionDelegate

- (void)session:(ARSession *)session didUpdateFrame:(ARFrame *)frame {
    simd_float4 pos = frame.camera.transform.columns[3];
    self.cameraOrigin.position = SCNVector3Make(pos.x, pos.y, pos.z);
    // TODO: read euler angles from camera transform
//    CLLocation *loc = [self.arView currentLocation];
//    NSLog(@"[RCTARKit] Current position (%.2f, %.2f, %.2f) at (%.6f, %.6f)", pos.x, pos.y, pos.z, loc.coordinate.longitude, loc.coordinate.latitude);
}

- (void)session:(ARSession *)session cameraDidChangeTrackingState:(ARCamera *)camera {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView session:session cameraDidChangeTrackingState:camera];
#endif

    if (self.onTrackingState) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.onTrackingState(@{
                                   @"state": @(camera.trackingState),
                                   @"reason": @(camera.trackingStateReason)
                                   });
        });
    }
}

- (void)session:(ARSession *)session didFailWithError:(NSError *)error {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView session:session didFailWithError:error];
#endif
}

- (void)sessionWasInterrupted:(ARSession *)session {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView sessionWasInterrupted:session];
#endif
}

- (void)sessionInterruptionEnded:(ARSession *)session {
#ifdef MODE_ARCL
    [(SceneLocationView*)self.arView sessionInterruptionEnded:session];
#endif
}

@end
