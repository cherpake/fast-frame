//
//  Shell.m
//  Remote for Mac Server
//
//  Created by Evgeny Cherpak on 19/05/2017.
//
//

#import "Shell.h"

@implementation Shell

+ (NSArray<NSString*>*)run:(NSString *)command arguments:(NSArray<NSString*>*)args {
    NSTask* task = [NSTask new];
    task.launchPath = command;
    task.arguments = args;
    
    NSPipe* output = [NSPipe new];
    NSPipe* errorOutput = [NSPipe new];
    task.standardOutput = output;
    task.standardError = errorOutput;
    
    [task launch];
    
    NSData* outputData = output.fileHandleForReading.readDataToEndOfFile;
    NSString* outputString = nil;
    if ( outputData ) {
        outputString = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
        outputString = [outputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ( outputString.length == 0 ) outputString = nil;
    }
    
    NSData* errorData = errorOutput.fileHandleForReading.readDataToEndOfFile;
    NSString* errorString = nil;
    if ( errorData ) {
        errorString = [[NSString alloc] initWithData:errorData encoding:NSUTF8StringEncoding];
        errorString = [errorString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if ( errorString.length == 0 ) errorString = nil;
    }
    
    [task waitUntilExit];
    
    if ( errorString ) {
        return nil;
    } else {
        return [outputString componentsSeparatedByString:@"\n"];
    }
}

@end
