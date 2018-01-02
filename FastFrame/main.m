//
//  main.m
//  FastFrame
//
//  Created by Evgeny Cherpak on 25/05/2017.
//  Copyright © 2017 Evgeny Cherpak. All rights reserved.
//

#import <Foundation/Foundation.h>
@import AppKit;
@import AVFoundation;

#import "Shell.h"

NSMutableArray<NSString*>* _arguments;
NSString* _configPath;
NSDictionary* _config;

static NSString* configFile                         = @"Fastframe.json";
static NSString* configDevices                      = @"DeviceFrames";


static NSString* devicesKey                         = @"devices";
static NSString* frameKey                           = @"frame";
static NSString* backgroundKey                      = @"background";
static NSString* colorKey                           = @"color";
static NSString* endColorKey                        = @"endcolor";
static NSString* keywordKey                         = @"keyword";
static NSString* titleKey                           = @"title";
static NSString* paddingKey                         = @"padding";
static NSString* fontKey                            = @"font";
static NSString* nameKey                            = @"name";
static NSString* sizeKey                            = @"size";

static NSString* keywordFile                        = @"keyword.strings";
static NSString* titleFile                          = @"title.strings";

NSColor* colorFromHexString(NSString* hexString) {
    unsigned rgbValue = 0;
    NSScanner *scanner = [NSScanner scannerWithString:hexString];
    [scanner setScanLocation:1]; // bypass '#' character
    [scanner scanHexInt:&rgbValue];
    return [NSColor colorWithRed:((rgbValue & 0xFF0000) >> 16)/255.0 green:((rgbValue & 0xFF00) >> 8)/255.0 blue:(rgbValue & 0xFF)/255.0 alpha:1.0];
}

BOOL loadConfig() {
    NSString* path = [[NSFileManager defaultManager] currentDirectoryPath];//[_arguments firstObject].stringByDeletingLastPathComponent;
    while (![path.lastPathComponent isEqualToString:path]) {
        NSString* file = [path stringByAppendingPathComponent:configFile];
        if ( [[NSFileManager defaultManager] fileExistsAtPath:file] ) {
            NSData* data = [NSData dataWithContentsOfFile:file];
            NSError* error;
            _config = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&error];
            if ( error ) {
                NSLog(@"Can't load %@ due to: %@", configFile, error);
            } else {
                _configPath = path;
                NSLog(@"Found %@ at: %@", configFile, file);
            }
            break;
        } else {
            path = path.stringByDeletingLastPathComponent;
        }
    }
    if (!_config) {
        NSLog(@"Can't find %@ file", configFile);
        return false;
    }
    return true;
}

BOOL validateConfig() {
    // lets make sure that if we use device frames, we have the files for them
    NSDictionary* devices = _config[devicesKey];
    if ( devices.allValues > 0 ) {
        BOOL dir = NO;
        NSString* devicesDir = [_configPath stringByAppendingPathComponent:configDevices];
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:devicesDir isDirectory:&dir] || !dir ) {
            NSLog(@"Can't find \"%@\" directory", configDevices);
            return false;
        }
        BOOL missingFrames = NO;
        for ( NSDictionary* d in devices.allValues ) {
            NSString* frame = d[frameKey];
            NSString* file = [devicesDir stringByAppendingPathComponent:frame];
            if ( ![[NSFileManager defaultManager] fileExistsAtPath:file] ) {
                NSLog(@"Can't find \"%@\" device frame", frame);
                missingFrames = YES;
            }
        }
        if ( missingFrames ) return false;
    }
    
    return true;
}

NSArray* findScreenshots() {
    NSArray* images = [Shell run:@"/usr/bin/find" arguments:@[_configPath, @"-type", @"f", @"-name", @"*.png"]];
    
    return [images filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString* file, NSDictionary* bindings) {
        NSString* localeIdentifier = file.stringByDeletingLastPathComponent.lastPathComponent;
        // NOTE: for some unclear reason we need to do this... thank you Apple for making things so strange
        return [[NSLocale availableLocaleIdentifiers] containsObject:[localeIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"]] && [file rangeOfString:@"_frame"].length == 0;
    }]];
}

NSString* findDeviceName(NSString* screenshot) {
    NSDictionary* devices = _config[devicesKey];
    NSArray* deviceNames = devices.allKeys;
    NSString* deviceName = nil;
    for ( NSString* n in deviceNames ) {
        if ( [screenshot rangeOfString:n].length > 0 ) {
            deviceName = n;
            break;
        }
    }
    return deviceName;
}

NSString* findFrame(NSString* screenshot) {
    NSDictionary* devices = _config[devicesKey];
    return devices[findDeviceName(screenshot)][frameKey];
}

NSString* findText(NSString* screenshot, NSString* type) {
    // lets check if we have file in the screenshot folder,
    // if not - lets look in the config folder
    NSString* folder = screenshot.stringByDeletingLastPathComponent;
    NSString* textFile = [folder stringByAppendingPathComponent:type];
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:textFile] ) {
        textFile = [_configPath stringByAppendingPathComponent:type];
        if ( ![[NSFileManager defaultManager] fileExistsAtPath:textFile] ) {
            textFile = nil;
        }
    }
    if ( !textFile ) return nil;
    NSDictionary* strings = [NSDictionary dictionaryWithContentsOfFile:textFile];
    for ( NSString* k in strings.allKeys ) {
        if ( [screenshot rangeOfString:k].length > 0 ) {
            return strings[k];
        }
    }
    return nil;
}

NSString* findKeyword(NSString* screenshot) {
    return findText(screenshot, keywordFile);
}

NSString* findTitle(NSString* screenshot) {
    return findText(screenshot, titleFile);
}

NSRect invertRect(NSRect bounds, CGRect rect) {
    return NSMakeRect(rect.origin.x, bounds.size.height - (rect.origin.y + rect.size.height), rect.size.width, rect.size.height);
}

void frameScreenshot(NSString* screenshot) {
    NSData* imageData = [NSData dataWithContentsOfFile:screenshot];
    CGImageRef image = [[NSBitmapImageRep alloc] initWithData:imageData].CGImage;
    if ( !image ) {
        NSLog(@"Can't load screenshot from \"%@\"", screenshot);
        return;
    }
    
    CGSize imageSize = {CGImageGetWidth(image), CGImageGetHeight(image)};

    NSString* deviceFrame = findFrame(screenshot);
    CGImageRef frameImage = nil;
    if ( deviceFrame ) {
        NSLog(@"Using \"%@\" for %@", deviceFrame, screenshot.lastPathComponent);
        NSString* framePath = [[_configPath stringByAppendingPathComponent:configDevices] stringByAppendingPathComponent:deviceFrame];
        NSData* frameData = [NSData dataWithContentsOfFile:framePath];
        frameImage = [[NSBitmapImageRep alloc] initWithData:frameData].CGImage;
        if ( !frameImage ) {
            NSLog(@"Can't load frame from \"%@\"", framePath);
            return;
        }
        
        CGSize frameSize = {CGImageGetWidth(frameImage), CGImageGetHeight(frameImage)};
        
        // OK, let do our thing, draw screenshot inside the frame,
        // and replace the image
        NSBitmapImageRep *offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                                 pixelsWide:frameSize.width
                                                                                 pixelsHigh:frameSize.height
                                                                              bitsPerSample:8
                                                                            samplesPerPixel:4
                                                                                   hasAlpha:true
                                                                                   isPlanar:false
                                                                             colorSpaceName:NSCalibratedRGBColorSpace
                                                                               bitmapFormat:0
                                                                                bytesPerRow:0
                                                                               bitsPerPixel:0];
        
        // set offscreen context
        NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:g];
        
        CGRect frameRect = {0, 0, frameSize.width, frameSize.height};
        CGContextRef ctx = [g graphicsPort];
//        CGContextDrawImage(ctx, frameRect, frameImage);
        CGRect imageRect = CGRectInset(frameRect, (frameSize.width - imageSize.width) / 2.0, (frameSize.height - imageSize.height) / 2.0);
        CGContextDrawImage(ctx, imageRect, image);
        CGContextDrawImage(ctx, frameRect, frameImage);
        
        image = CGBitmapContextCreateImage(ctx);
        
        [NSGraphicsContext restoreGraphicsState];
    }

    NSString* keyword = findKeyword(screenshot);
    NSString* title = findTitle(screenshot);
    
    if ( keyword ) NSLog(@" > Keyword: %@", keyword);
    if ( title ) NSLog(@" > Title: %@", title);
    
    NSString* bgColor = _config[backgroundKey][colorKey];
    NSColor* background;
    if ( bgColor ) {
        background = colorFromHexString(bgColor);
    } else {
        background = [NSColor whiteColor];
    }

    NSString* endBgColor = _config[backgroundKey][endColorKey];
    NSColor* endBackground;
    if ( endBgColor ) {
        endBackground = colorFromHexString(endBgColor);
    } else {
        endBackground = [NSColor whiteColor];
    }

    NSRect imageRect = {0, 0, imageSize.width, imageSize.height};
    
    NSBitmapImageRep *offscreenRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nil
                                                                             pixelsWide:imageSize.width
                                                                             pixelsHigh:imageSize.height
                                                                          bitsPerSample:8
                                                                        samplesPerPixel:4
                                                                               hasAlpha:true
                                                                               isPlanar:false
                                                                         colorSpaceName:NSCalibratedRGBColorSpace
                                                                           bitmapFormat:0
                                                                            bytesPerRow:0
                                                                           bitsPerPixel:0];
    
    // set offscreen context
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:g];
    
    CGContextRef ctx = [g graphicsPort];
    CGContextAddRect(ctx, imageRect);
    CGContextClip(ctx);
    
    NSArray *colors = @[(__bridge id)background.CGColor, (__bridge id)endBackground.CGColor];
    CGFloat locations[2] = {0.0, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(), (CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(CGRectGetMidX(imageRect), imageSize.height), CGPointMake(CGRectGetMidX(imageRect), 0.0),  0);
    
    __block CGFloat yOffset = 0.0;
    __block CGFloat xOffset = 0.0;
    
    void (^drawText)(NSString*, NSString*, NSString*) = ^(NSString* text, NSString* textKey, NSString* file){
        if ( text.length > 0 ) {
            NSString* padding = _config[textKey][paddingKey];
            if ( [padding hasSuffix:@"%"] ) {
                xOffset = (imageSize.height / 100) * [padding integerValue];
                yOffset += xOffset;
            } else {
                xOffset = 1.0 * [padding integerValue];
                yOffset += xOffset;
            }
            
            NSString* fontName = _config[textKey][fontKey][nameKey];
            NSString* fontSize =  _config[textKey][fontKey][sizeKey];
            NSString* fontColor = _config[textKey][fontKey][colorKey];
            
            CGFloat textLines = 1.0;
            CGFloat maxWidth = imageSize.width - xOffset * 2.0 - 40.0;
            
            NSFont* font;
            if ( fontSize.floatValue == 0.0 ) {
                // need to calculate font size
                CGFloat fontSize = 192.0; // initial size
                font = [NSFont fontWithName:fontName size:fontSize];

                // need all strings
                NSString* textFile = [screenshot.stringByDeletingLastPathComponent stringByAppendingPathComponent:file];
                NSDictionary* textDict = [NSDictionary dictionaryWithContentsOfFile:textFile];
                NSArray* allText = [textDict.allValues sortedArrayUsingComparator:^NSComparisonResult(NSString* obj1, NSString* obj2) {
                    return obj2.length > obj1.length;
                }];
                NSLog(@"Calculating size for: %@", allText);
                
                CGFloat minFontSize = 80.0;
                
                NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
                [style setLineBreakMode:NSLineBreakByWordWrapping];
                [style setAlignment:NSTextAlignmentCenter];
                
                for ( NSString* t in allText ) {
                    while ( fontSize > minFontSize ) {
                        font = [NSFont fontWithName:fontName size:fontSize];
                        NSDictionary* attr = @{NSFontAttributeName : font,
                                               NSParagraphStyleAttributeName: style,
                                               NSKernAttributeName: @-0.3};
                        CGSize oneLineSize = [t sizeWithAttributes:attr];
                        CGSize size = [t boundingRectWithSize:NSMakeSize(maxWidth, CGFLOAT_MAX)
                                                      options:NSStringDrawingUsesLineFragmentOrigin
                                                   attributes:attr].size;
                        
                        if ( size.height > oneLineSize.height && fontSize > minFontSize ) {
                            fontSize -= 1.0;
                        } else {
                            break;
                        }
                    }
                }
                
                for ( NSString* t in allText ) {
                    NSDictionary* attr = @{NSFontAttributeName : font,
                                           NSParagraphStyleAttributeName: style,
                                           NSKernAttributeName: @-0.3};
                    CGSize oneLineSize = [t sizeWithAttributes:attr];
                    CGSize size = [t boundingRectWithSize:NSMakeSize(maxWidth, CGFLOAT_MAX)
                                                                    options:NSStringDrawingUsesLineFragmentOrigin
                                                                 attributes:attr].size;
                    CGFloat textLinesInT = ceil(size.height / oneLineSize.height);
                    if ( textLinesInT > textLines ) {
                        textLines = textLinesInT;
                    }
                }
                
                NSLog(@"Selected font size of %@", @(fontSize));
            } else {
                font = [NSFont fontWithName:fontName size:fontSize.floatValue];
            }
            
            NSColor* textColor;
            if ( fontColor ) {
                textColor = colorFromHexString(fontColor);
            } else {
                textColor = [NSColor blackColor];
            }
            
            if ( textLines > 1.0 ) {
                NSLog(@"More than 1 line");
            }
            
            NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
            [style setLineBreakMode:NSLineBreakByWordWrapping];
            [style setAlignment:NSTextAlignmentCenter];
            NSDictionary* attr = @{NSFontAttributeName : font,
                                   NSForegroundColorAttributeName : textColor,
                                    NSParagraphStyleAttributeName: style,
                                   NSKernAttributeName: @-0.3};
            CGSize size = [text boundingRectWithSize:NSMakeSize(maxWidth, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin attributes:attr].size;
            CGSize oneLineSize = [text sizeWithAttributes:attr];
            CGFloat emptySpaceY = ((oneLineSize.height * textLines) - size.height) / 2.0;
            CGFloat emptySpaceX = 20.0;
            CGRect rect = {xOffset + emptySpaceX, yOffset + emptySpaceY, maxWidth, size.height};
            rect = invertRect(imageRect, rect);
            [text drawInRect:rect withAttributes:attr];
            
            yOffset += oneLineSize.height * textLines;
        }
    };
    
    CGFloat devicePadding = 0.0;

    NSString* padding = _config[devicesKey][findDeviceName(screenshot)][paddingKey];
    if ( [padding hasSuffix:@"%"] ) {
        devicePadding = (imageSize.height / 100) * [padding integerValue];
    } else {
        devicePadding = 1.0 * [padding integerValue];
    }
    
    drawText(keyword, keywordKey, keywordFile);
    drawText(title, titleKey, titleFile);

    CGRect fullRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
    CGRect rect = CGRectMake(0, yOffset, imageSize.width, imageSize.height - yOffset);
    rect = CGRectInset(rect, devicePadding, devicePadding);
    // we need real ratio of the image in case we replaced it with framed image, and it has diff. ratio
    CGSize ratio = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
    CGRect drawRect = AVMakeRectWithAspectRatioInsideRect(ratio, rect);
    CGContextDrawImage(ctx, invertRect(fullRect, drawRect), image);
    
    // Save to file
    NSString* framedName = [[screenshot stringByDeletingPathExtension] stringByAppendingString:@"_framed.png"];
    NSData* framed = [offscreenRep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    [framed writeToFile:framedName atomically:YES];
    
    //
    [NSGraphicsContext restoreGraphicsState];
}

void frameScreenshots(NSArray<NSString*>* screenshots) {
    for ( NSString* s in screenshots ) {
        @autoreleasepool {
            frameScreenshot(s);
        }
    }
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        _arguments = [NSMutableArray arrayWithCapacity:argc];
        for ( int i = 0; i < argc; i++ ) {
            [_arguments addObject:[NSString stringWithUTF8String:argv[i]]];
        }
        
//        if ( [_arguments containsObject:@"--list-fonts"] ) {
            NSLog(@"%@", [[[NSFontManager sharedFontManager] availableFonts] componentsJoinedByString:@"\n"]);
//            return 0;
//        }
        
        if (!loadConfig()) return -1;
        if (!validateConfig()) return -1;
        
        NSArray* screenshots = findScreenshots();
        if (!screenshots) return -1;
        
        frameScreenshots(screenshots);
    }
    return 0;
}
