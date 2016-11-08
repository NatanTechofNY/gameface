//
//  CVFFaceDetect.m
//  CVFunhouse
//
//  Created by John Brewer on 7/22/12.
//  Copyright (c) 2012 Jera Design LLC. All rights reserved.
//

// Based on the OpenCV example: <opencv>/samples/c/facedetect.cpp

#import "CVFFaceDetect.h"

#include "opencv2/objdetect/objdetect.hpp"
#include "opencv2/imgproc/imgproc.hpp"

//Start - from dlib
#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

#import <UIKit/UIKit.h>

#include <dlib/image_processing.h>
#include <dlib/image_io.h>
//End - from dlib

//Start - from attentiontracker
#include <opencv2/calib3d/calib3d.hpp>
#include <opencv2/highgui/highgui.hpp>
#include "head_pose_estimation.hpp"
//End - from attentiontracker

#include "CVFImageProcessorDelegate.h"

using namespace std;
using namespace cv;

CascadeClassifier cascade;
std::string modelFileNameCString;
double scale = 1;
dlib::shape_predictor sp;
dlib::full_object_detection shape;

@interface CVFFaceDetect() {
    bool _inited;
}

@end

@implementation CVFFaceDetect

-(void)processMat:(cv::Mat)mat
{
    if (!_inited) {
        NSString* haarDataPath =
        [[NSBundle mainBundle] pathForResource:@"haarcascade_frontalface_alt.xml" ofType:nil];
        
        cascade.load([haarDataPath UTF8String]);
        
        NSString *modelFileName = [[NSBundle mainBundle] pathForResource:@"shape_predictor_68_face_landmarks" ofType:@"dat"];
        modelFileNameCString = [modelFileName UTF8String];
        dlib::deserialize(modelFileNameCString) >> sp;
        
//        for (int i = 0; i < [self.delegate getDelaunayEdges].count; i++) {
//            NSMutableArray *m = [self.delegate getDelaunayEdges][i];
//            for (int j = 0; j < m.count; j++) {
//                NSLog( @"%@", m[j]);
//            }
//        }
        
        _inited = true;
    }

    cvtColor(mat, mat, CV_BGR2RGB);

    int i = 0;
    vector<cv::Rect> faces;
    Mat gray, smallImg( cvRound (mat.rows/scale), cvRound(mat.cols/scale), CV_8UC1 );
    
    cvtColor( mat, gray, CV_RGB2GRAY );
    resize( gray, smallImg, smallImg.size(), 0, 0, INTER_LINEAR );
    equalizeHist( smallImg, smallImg );
    
    cascade.detectMultiScale( smallImg, faces,
                             1.2, 2, 0
                             |CV_HAAR_SCALE_IMAGE
                             ,
                             cv::Size(75, 75) );
    
    for( vector<cv::Rect>::const_iterator r = faces.begin(); r != faces.end(); r++, i++ ) {
        dlib::cv_image<dlib::bgr_pixel> dlibMat(mat);
        
//        for converting either direction use this http://stackoverflow.com/a/34873134/1079379
//        static cv::Rect dlibRectangleToOpenCV(dlib::rectangle r){return cv::Rect(cv::Point2i(r.left(), r.top()), cv::Point2i(r.right() + 1, r.bottom() + 1));}
//        static dlib::rectangle openCVRectToDlib(cv::Rect r){return dlib::rectangle((long)r.tl().x, (long)r.tl().y, (long)r.br().x - 1, (long)r.br().y - 1);}
        
        dlib::rectangle dlibRect((long)r->tl().x, (long)r->tl().y, (long)r->br().x - 1, (long)r->br().y - 1);
//        if ([self.delegate showFaceDetect]) {
//            dlib::draw_rectangle(dlibMat, dlibRect, dlib::rgb_pixel(0, 255, 255));
//        }
        
        shape = sp(dlibMat, dlibRect);
        NSMutableArray *m = [NSMutableArray new];
        
        /////
        // Draws the contours of the face and face features onto the image
        
        // Define colors for drawing.
        Scalar delaunay_color(255,255,255), points_color(0, 0, 255);
        
        // Rectangle to be used with Subdiv2D
        cv::Size size = mat.size();
        cv::Rect rect(0, 0, size.width, size.height);
        
        // Create an instance of Subdiv2D
        Subdiv2D subdiv(rect);
        /////
        
        for (unsigned long k = 0; k < shape.num_parts(); k++) {
            if ([self.delegate showFaceDetect]) {
                draw_solid_circle(dlibMat, shape.part(k), 3, dlib::rgb_pixel(0, 255, 0));
            }
            
            CGPoint landmark = CGPointMake( [self pixelToPoints:shape.part(k).x()], [self pixelToPoints:shape.part(k).y()]);
            
            //inside lips outline
            if (k >= 60) { [m addObject: [NSValue valueWithCGPoint: landmark ]]; }
            
            //nose bridge
            if (k == 28) { [self.delegate noseBridgePosition: landmark ]; }
            
            //nose tip
            if (k == 31) { [self.delegate noseTipPosition: landmark ]; }
            
            if (k == 52) {
                CGPoint landmark34 = CGPointMake( [self pixelToPoints:shape.part(34).x()], [self pixelToPoints:shape.part(34).y()]);
                CGPoint midpoint = CGPointMake( (landmark.x + landmark34.x) / 2.0 , (landmark.y + landmark34.y) / 2.0 );
                [self.delegate mustachePosition:midpoint];
            }
            
            if (rect.contains([self toCv:shape.part(k)])) {
                subdiv.insert([self toCv:shape.part(k)]);
            }
        }
        
//        if ([self.delegate showFaceDetect]) {
            [self draw_delaunay:mat subdiv:subdiv delaunay:delaunay_color];
//        }
        
        [self.delegate mouthVerticePositions:m];
        [self pose:0 image:mat];
    }

    [self matReady:mat];

//    cv::Mat edges;
//    cvtColor(mat, edges, CV_BGR2GRAY);
//    GaussianBlur(edges, edges, cv::Size(7, 7), 1.5, 1.5);
//    Canny(edges, edges, 0, 30, 3);
//    Canny(edges, edges, 10, 100, 3);
//    [self matReady:edges];

}

- (CGFloat)pixelToPoints:(CGFloat)px {
    CGFloat pointsPerInch = 72.0; // see: http://en.wikipedia.org/wiki/Point%5Fsize#Current%5FDTP%5Fpoint%5Fsystem
    
    float pixelPerInch = 163; // aka dpi
    
    pointsPerInch += [self.delegate adjustPPI];
    CGFloat result = px * pointsPerInch / pixelPerInch;
    return result;
}

-(Point2f) toCv: (dlib::point&) p {
    return cv::Point2f(p.x(), p.y());
}

// Draw delaunay triangles
-(void) draw_delaunay: (Mat&) img subdiv: (Subdiv2D&) subdiv delaunay: (Scalar) delaunay_color {
    
    std::vector<Vec6f> triangleList;
    subdiv.getTriangleList(triangleList);
    std::vector<cv::Point> pt(3);
    cv::Size size = img.size();
    cv::Rect rect(0,0, size.width, size.height);
    
    for( size_t i = 0; i < triangleList.size(); i++ )
    {
        Vec6f t = triangleList[i];
        pt[0] = cv::Point(cvRound(t[0]), cvRound(t[1]));
        pt[1] = cv::Point(cvRound(t[2]), cvRound(t[3]));
        pt[2] = cv::Point(cvRound(t[4]), cvRound(t[5]));
        
        // Draw rectangles completely inside the image.
        if ( rect.contains(pt[0]) && rect.contains(pt[1]) && rect.contains(pt[2]))
        {
            cv::line(img, pt[0], pt[1], delaunay_color, 1, CV_AA, 0);
            cv::line(img, pt[1], pt[2], delaunay_color, 1, CV_AA, 0);
            cv::line(img, pt[2], pt[0], delaunay_color, 1, CV_AA, 0);
        }
    }
}

-(void) warpTriangle: (Mat &) img1 img2: (Mat &) img2 tri1: (vector<Point2f>) tri1 tri2: (vector<Point2f>) tri2 {
    // Find bounding rectangle for each triangle
    cv::Rect r1 = boundingRect(tri1);
    cv::Rect r2 = boundingRect(tri2);
    
    // Offset points by left top corner of the respective rectangles
    vector<Point2f> tri1Cropped, tri2Cropped;
    vector<cv::Point> tri2CroppedInt;
    for(int i = 0; i < 3; i++) {
        tri1Cropped.push_back( Point2f( tri1[i].x - r1.x, tri1[i].y -  r1.y) );
        tri2Cropped.push_back( Point2f( tri2[i].x - r2.x, tri2[i].y - r2.y) );
        
        // fillConvexPoly needs a vector of Point and not Point2f
        tri2CroppedInt.push_back( cv::Point((int)(tri2[i].x - r2.x), (int)(tri2[i].y - r2.y)) );
        
    }
    
    // Apply warpImage to small rectangular patches
    Mat img1Cropped;
    img1(r1).copyTo(img1Cropped);
    
    // Given a pair of triangles, find the affine transform.
    Mat warpMat = getAffineTransform( tri1Cropped, tri2Cropped );
    
    // Apply the Affine Transform just found to the src image
    Mat img2Cropped = Mat::zeros(r2.height, r2.width, img1Cropped.type());
    warpAffine( img1Cropped, img2Cropped, warpMat, img2Cropped.size(), INTER_LINEAR, BORDER_REFLECT_101);
    
    // Get mask by filling triangle
    Mat mask = Mat::zeros(r2.height, r2.width, CV_32FC3);
    fillConvexPoly(mask, tri2CroppedInt, Scalar(1.0, 1.0, 1.0), 16, 0);
    
    // Copy triangular region of the rectangular patch to the output image
    multiply(img2Cropped,mask, img2Cropped);
    multiply(img2(r2), Scalar(1.0,1.0,1.0) - mask, img2(r2));
    img2(r2) = img2(r2) + img2Cropped;
    
}

-(head_pose) pose: (size_t) face_idx image: (Mat) image {
    
    cv::Mat projectionMat = cv::Mat::zeros(3,3,CV_32F);
    cv::Matx33f projection = projectionMat;
    projection(0,0) = 500;//focalLength;
    projection(1,1) = 500;//focalLength;
    projection(0,2) = [UIScreen mainScreen].bounds.size.width / 2.0;//opticalCenterX;
    projection(1,2) = [UIScreen mainScreen].bounds.size.height / 2.0;//opticalCenterY;
    projection(2,2) = 1;
    
    std::vector<Point3f> head_points;
    
    head_points.push_back(P3D_SELLION);
    head_points.push_back(P3D_RIGHT_EYE);
    head_points.push_back(P3D_LEFT_EYE);
    head_points.push_back(P3D_RIGHT_EAR);
    head_points.push_back(P3D_LEFT_EAR);
    head_points.push_back(P3D_MENTON);
    head_points.push_back(P3D_NOSE);
    head_points.push_back(P3D_STOMMION);
    
    std::vector<Point2f> detected_points;
    
    detected_points.push_back([self coordsOf:face_idx feature:SELLION]);
    detected_points.push_back([self coordsOf:face_idx feature:RIGHT_EYE]);
    detected_points.push_back([self coordsOf:face_idx feature:LEFT_EYE]);
    detected_points.push_back([self coordsOf:face_idx feature:RIGHT_SIDE]);
    detected_points.push_back([self coordsOf:face_idx feature:LEFT_SIDE]);
    detected_points.push_back([self coordsOf:face_idx feature:MENTON]);
    detected_points.push_back([self coordsOf:face_idx feature:NOSE]);
    
    auto stomion = ([self coordsOf:face_idx feature:MOUTH_CENTER_TOP] + [self coordsOf:face_idx feature:MOUTH_CENTER_BOTTOM]) * 0.5;
    detected_points.push_back(stomion);
    
    cv::Mat rvec, tvec;
    
    // Find the 3D pose of our head
    solvePnP(head_points, detected_points,
             projection, noArray(),
             rvec, tvec, false,
             CV_ITERATIVE);
    Matx33d rotation;
    Rodrigues(rvec, rotation);
    
    cv::Matx44d pose = {
        rotation(0,0),    rotation(0,1),    rotation(0,2),    tvec.at<double>(0)/1000,
        rotation(1,0),    rotation(1,1),    rotation(1,2),    tvec.at<double>(1)/1000,
        rotation(2,0),    rotation(2,1),    rotation(2,2),    tvec.at<double>(2)/1000,
        0,                0,                0,                     1
    };
    
    std::vector<Point2f> reprojected_points;
    
    projectPoints(head_points, rvec, tvec, projection, noArray(), reprojected_points);
    
    for (auto point : reprojected_points) {
        circle(image, point,2, Scalar(0,255,255),2);
    }
    
    std::vector<Point3f> axes;
    axes.push_back(Point3f(0,0,0));
    axes.push_back(Point3f(50,0,0));
    axes.push_back(Point3f(0,50,0));
    axes.push_back(Point3f(0,0,50));
    std::vector<Point2f> projected_axes;
    
    projectPoints(axes, rvec, tvec, projection, noArray(), projected_axes);
    
    line(image, projected_axes[0], projected_axes[3], Scalar(255,0,0),2,CV_AA);
    line(image, projected_axes[0], projected_axes[2], Scalar(0,255,0),2,CV_AA);
    line(image, projected_axes[0], projected_axes[1], Scalar(0,0,255),2,CV_AA);
    
    // putText(image, "(" + to_string(int(pose(0,3) * 100)) + "cm, " + to_string(int(pose(1,3) * 100)) + "cm, " + to_string(int(pose(2,3) * 100)) + "cm)", coordsOf(face_idx, SELLION), FONT_HERSHEY_SIMPLEX, 0.5, Scalar(0,0,255),2);
    
    head_pose pose_head	=	{pose,	// transformation matrix
        tvec,	// vector with translations
        rvec};	// vector with rotations
    
    return pose_head;
}

-(Point2f) coordsOf: (size_t) face_idx feature: (FACIAL_FEATURE) feature {
    return [self toCv:shape.part(feature)];
}

@end
