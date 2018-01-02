//
//  Shell.h
//  Remote for Mac Server
//
//  Created by Evgeny Cherpak on 19/05/2017.
//
//

#import <Foundation/Foundation.h>

@interface Shell : NSObject

+ (NSArray<NSString*>*)run:(NSString *)command arguments:(NSArray<NSString*>*)args;

@end
