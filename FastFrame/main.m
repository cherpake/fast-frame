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
NSString* _path;
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

NSArray* findFramedScreenshots() {
    NSArray* images = [Shell run:@"/usr/bin/find" arguments:@[_path, @"-type", @"f", @"-name", @"*.jpg"]];
    
    return [images filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString* file, NSDictionary* bindings) {
        NSString* localeIdentifier = file.stringByDeletingLastPathComponent.lastPathComponent;
        // NOTE: for some unclear reason we need to do this... thank you Apple for making things so strange
        return ( [[NSLocale ISOLanguageCodes] containsObject:localeIdentifier] ||
                [[NSLocale availableLocaleIdentifiers] containsObject:[localeIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"]])
        && [file rangeOfString:@"_frame"].length != 0;
    }]];
}

NSArray* findScreenshots() {
    NSArray* images = [Shell run:@"/usr/bin/find" arguments:@[_path, @"-type", @"f", @"-name", @"*.png"]];
    
    return [images filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSString* file, NSDictionary* bindings) {
        NSString* localeIdentifier = file.stringByDeletingLastPathComponent.lastPathComponent;
        // NOTE: for some unclear reason we need to do this... thank you Apple for making things so strange
        return ( [[NSLocale ISOLanguageCodes] containsObject:localeIdentifier] ||
                 [[NSLocale availableLocaleIdentifiers] containsObject:[localeIdentifier stringByReplacingOccurrencesOfString:@"-" withString:@"_"]])
                && [file rangeOfString:@"_frame"].length == 0;
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

NSString* findStrings(NSString* screenshot, NSString* stringsKey) {
    NSDictionary* devices = _config[devicesKey];
    return devices[findDeviceName(screenshot)][stringsKey];
}

NSString* findText(NSString* screenshot, NSString* file) {
    // lets check if we have file in the screenshot folder,
    // if not - lets look in the config folder
    NSString* folder = screenshot.stringByDeletingLastPathComponent;
    NSString* textFile = [folder stringByAppendingPathComponent:file];
    if ( ![[NSFileManager defaultManager] fileExistsAtPath:textFile] ) {
        textFile = [_configPath stringByAppendingPathComponent:file];
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

NSRect invertRect(NSRect bounds, CGRect rect) {
    return NSMakeRect(rect.origin.x, bounds.size.height - (rect.origin.y + rect.size.height), rect.size.width, rect.size.height);
}

CGImageRef frameScreenshot(NSString* screenshot, CGImageRef image) {
    NSString* deviceFrame = findFrame(screenshot);
    if ( !deviceFrame ) return NULL;

    CGImageRef frameImage = nil;
    NSString* framePath = [[_configPath stringByAppendingPathComponent:configDevices] stringByAppendingPathComponent:deviceFrame];
    NSData* frameData = [NSData dataWithContentsOfFile:framePath];
    frameImage = [[NSBitmapImageRep alloc] initWithData:frameData].CGImage;
    if ( !frameImage ) {
        NSLog(@"Can't load frame from \"%@\"", framePath);
        abort();
    }
    
    CGSize imageSize = {CGImageGetWidth(image), CGImageGetHeight(image)};
    CGSize frameSize = {CGImageGetWidth(frameImage), CGImageGetHeight(frameImage)};
        
    // OK, let do our thing, draw screenshot inside the frame, and replace the image
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
    CGRect frameRect = {0, 0, frameSize.width, frameSize.height};
    CGRect imageRect = CGRectInset(frameRect, (frameSize.width - imageSize.width) / 2.0, (frameSize.height - imageSize.height) / 2.0);

    // draw image and then frame on top of it
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
    [NSGraphicsContext setCurrentContext:g];
    CGContextRef ctx = [g graphicsPort];
    CGContextDrawImage(ctx, imageRect, image);
    CGContextDrawImage(ctx, frameRect, frameImage);
    image = CGBitmapContextCreateImage(ctx);
    [NSGraphicsContext restoreGraphicsState];
    
    return image;
}

void drawBackground(CGContextRef ctx, CGSize imageSize) {
    NSColor* background = [NSColor whiteColor];
    NSColor* endBackground = [NSColor whiteColor];

    NSString* bgColor = _config[backgroundKey][colorKey];
    NSString* endBgColor = _config[backgroundKey][endColorKey];

    if ( bgColor ) background = colorFromHexString(bgColor);
    if ( endBgColor ) endBackground = colorFromHexString(endBgColor);
    
    CGRect imageRect = CGRectMake(0, 0, imageSize.width, imageSize.height);
    CGContextAddRect(ctx, imageRect);
    CGContextClip(ctx);

    NSArray *colors = @[(__bridge id)background.CGColor,
                        (__bridge id)endBackground.CGColor];
    CGFloat locations[2] = {0.0, 1.0};
    CGGradientRef grad = CGGradientCreateWithColors(CGColorSpaceCreateDeviceRGB(), (CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(ctx, grad, CGPointMake(CGRectGetMidX(imageRect), imageSize.height), CGPointMake(CGRectGetMidX(imageRect), 0.0),  0);
}

void drawDevice(CGContextRef ctx, CGRect rect, CGSize imageSize, CGImageRef image) {
    CGSize theImageSize = {CGImageGetWidth(image), CGImageGetHeight(image)};
    CGRect aspectRect = AVMakeRectWithAspectRatioInsideRect(theImageSize, rect);
    CGContextDrawImage(ctx, invertRect(rect, aspectRect), image);
}

CGFloat drawText(CGContextRef ctx, CGRect _rect, NSString* textFileKey, NSString* screenshot, CGFloat minSize, CGFloat maxSize, NSInteger maxLines) {
    NSString* fontName = _config[textFileKey][fontKey][nameKey];
    NSString* configTextColor = _config[textFileKey][fontKey][colorKey];
    NSString* configFontSize =  _config[textFileKey][fontKey][sizeKey];
    
    CGRect rect = _rect;
    
    // make our rect smaller by appliying padding
    NSString* padding = _config[textFileKey][paddingKey];
    if ( padding ) {
        NSInteger paddingValue = [padding integerValue];
        if ( [padding hasSuffix:@"%"] ) {
            rect = CGRectInset(rect, CGRectGetMaxX(rect) * (paddingValue / 100.0), CGRectGetMaxY(rect) * (paddingValue / 100.0));
        } else {
            rect = CGRectInset(rect, paddingValue, paddingValue);
        }
    }
    
    // OK, this is complicated, cause strings file can include strings that are specific for iPad
    // so calculating font size should occure for all strings that apply to specific device model
    // and filter out strings that are not, thus we allow to specify specific strings file for device type
    NSString* textFile = findStrings(screenshot, textFileKey) ?: textFileKey;
    NSString* textFilePath = [screenshot.stringByDeletingLastPathComponent stringByAppendingPathComponent:textFile];
    NSDictionary* textDict = [NSDictionary dictionaryWithContentsOfFile:textFilePath];
    NSArray* allText = [textDict.allValues sortedArrayUsingComparator:^NSComparisonResult(NSString* obj1, NSString* obj2) {
        return obj2.length > obj1.length;
    }];

    BOOL autoFontSize = NO;
    CGFloat fontSize = [configFontSize floatValue];
    // calculate font size based on
    // all other strings in the file
    if ( fontSize == 0.0 ) {
        fontSize = maxSize;
        autoFontSize = YES;
    }

    // text attr
    NSShadow* shadow = [NSShadow new];
    shadow.shadowBlurRadius = 5.0;
    shadow.shadowColor = [NSColor blackColor];
    NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [style setLineBreakMode:NSLineBreakByWordWrapping];
    [style setAlignment:NSTextAlignmentCenter];
    NSColor* textColor = configTextColor != nil ? colorFromHexString(configTextColor) : [NSColor whiteColor];
    
    // make our text attr and if needed adjust font size based on min, max size and # of lines
    NSDictionary* attr;
    CGFloat numberOfLines = 0;
    CGSize biggestTextSize;
    do {
        NSFont* font = [NSFont fontWithName:fontName size:fontSize];
        NSDictionary* oneLineAttr = @{NSFontAttributeName : font,
                               NSShadowAttributeName : shadow,
                               NSForegroundColorAttributeName : textColor,
                               NSKernAttributeName: @-0.3};
        
        // oneline size
        CGSize oneLineSize = [allText.firstObject boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX)
                                                               options:NSStringDrawingUsesLineFragmentOrigin
                                                            attributes:oneLineAttr].size;
        
        NSMutableDictionary* multilineAttr = [oneLineAttr mutableCopy];
        [multilineAttr addEntriesFromDictionary:@{NSParagraphStyleAttributeName: style}];
        
        // multiline size - have to go over all strings to measure the longest
        // and base on it calc y offset to padding our frame with if needed - this way our screenshot
        // will be on the same level in all screenshots for each device
        biggestTextSize = CGSizeZero;
        for ( NSString* string in allText ) {
            CGSize stringSize = [string boundingRectWithSize:rect.size
                                                     options:NSStringDrawingUsesLineFragmentOrigin
                                                  attributes:multilineAttr].size;
            if ( stringSize.height > biggestTextSize.height ) {
                biggestTextSize = stringSize;
            }
        }

        // calc number of lines
        numberOfLines = biggestTextSize.height / oneLineSize.height;
        // assign attr we used - in case we found our font size
        attr = multilineAttr;
        // reduce font size for next loop
        fontSize -= 1.0;

        // basically what we want is to have:
        // biggest text in one line or max # lines
        if ( numberOfLines <= 1.0 ) break;
        if ( numberOfLines > maxLines*1.0 ) {
            // here we should continue with the loop
            // cause we have more than max # of lines
            continue;
        }
        if ( fontSize > minSize ) {
            // here we can continue cause our font is still
            // bigger than min allowed font size
            continue;
        } else {
            // if we got here we reached our min font size
            // and we have smallest font size allowed...
            break;
        }
    } while (autoFontSize);
    NSLog(@"Selected font size of %f", fontSize);
    
    // find our current text
    NSString* text = findText(screenshot, textFile);
    CGSize textSize = [text boundingRectWithSize:rect.size
                                         options:NSStringDrawingUsesLineFragmentOrigin
                                      attributes:attr].size;
    
    // calc y offset to pad our frame with it if needed - this way our screenshot
    // will be on the same level in all screenshots for each device
    CGFloat yOffset = ceil((biggestTextSize.height - textSize.height) / 2.0);
    
    CGRect textRect = rect;
    textRect.size = textSize;
    textRect.origin.x = floor((CGRectGetMaxX(_rect) - textSize.width) / 2.0);
    textRect.origin.y += yOffset;
    NSRect drawRect = invertRect(NSRectFromCGRect(_rect), textRect);
    [text drawInRect:drawRect withAttributes:attr];

    // we take our original rect, and calculate padding +
    // text size add add our y offset to level device in screenshots
    return (CGRectGetMinY(rect) - CGRectGetMinY(_rect)) + textSize.height + yOffset * 2.0;
}

void processScreenshot(NSString* screenshot) {
    NSData* imageData = [NSData dataWithContentsOfFile:screenshot];
    if ( !imageData ) {
        NSLog(@"Can't load screenshot from \"%@\"", screenshot);
        return;
    }
    
    CGImageRef image = [[NSBitmapImageRep alloc] initWithData:imageData].CGImage;
    if ( !image ) {
        NSLog(@"Can't load screenshot from \"%@\"", screenshot);
        return;
    }
    
    NSLog(@"Framing %@", screenshot);
    CGSize imageSize = {CGImageGetWidth(image), CGImageGetHeight(image)};
    
    // add frame to image
    CGImageRef framedImage = frameScreenshot(screenshot, image);
    
    // our new image
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
    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *g = [NSGraphicsContext graphicsContextWithBitmapImageRep:offscreenRep];
    [NSGraphicsContext setCurrentContext:g];
    CGContextRef ctx = [g graphicsPort];
    
    // draw background
    drawBackground(ctx, imageSize);
    
    // our content rect
    CGRect rect = CGRectMake(0, 0, imageSize.width, imageSize.height);
//    rect = CGRectInset(rect, ceil(imageSize.width * 0.05), ceil(imageSize.height * 0.05));
    
    // draw text (this func will make rect smaller by the space taken by the text)
    CGFloat textOffset = drawText(ctx, rect, keywordFile, screenshot, 92.0, 192.0, 3);
    rect = CGRectOffset(rect, 0, textOffset);
    
    // draw device (+frame)
    
    // add padding?
    NSDictionary* devices = _config[devicesKey];
    NSNumber* padding = devices[findDeviceName(screenshot)][paddingKey];
    rect = CGRectOffset(rect, 0.0, padding.floatValue);
    
    drawDevice(ctx, rect, imageSize, framedImage ?: image);
    if ( framedImage ) CGImageRelease(framedImage);
    
    // save
    NSString* uuid = [[NSUUID UUID].UUIDString lowercaseString];
    NSString* framedName = [[screenshot stringByDeletingPathExtension] stringByAppendingFormat:@"_%@_framed.jpg", uuid];
    NSData* framed = [offscreenRep representationUsingType:NSBitmapImageFileTypeJPEG
                                                properties:@{NSImageCompressionFactor : @0.8}];
    [framed writeToFile:framedName atomically:YES];

    [NSGraphicsContext restoreGraphicsState];
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
//        NSLog(@"%@", [[[NSFontManager sharedFontManager] availableFonts] componentsJoinedByString:@"\n"]);
        
        _path = [[NSFileManager defaultManager] currentDirectoryPath];
        if (!loadConfig()) return -1;
        if (!validateConfig()) return -1;

        // find screenshots that needs to be framed
        NSArray* screenshots = findScreenshots();
        if (!screenshots) return -1;

        // removed old framed screenshots
        NSArray* framed = findFramedScreenshots();
        for (NSString* f in framed) {
            [[NSFileManager defaultManager] trashItemAtURL:[NSURL fileURLWithPath:f] resultingItemURL:nil error:nil];
        }
        
        // frame screenshots
        for (NSString* s in screenshots) {
            @autoreleasepool {
                processScreenshot(s);
            }
        }
    }
    return 0;
}
