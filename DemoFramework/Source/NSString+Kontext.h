//
//  NSString+Kontext.h
//
//  Created by James on 16/3/2017.
//
//

#import <Foundation/Foundation.h>

#ifndef NSString_Kontext_h
#define NSString_Kontext_h
@interface NSString (Kontext)

- (NSString*)one_getVersionForRange:(NSRange)range;
- (NSString*)one_substringAfter:(NSString *)needle;
- (NSString*)one_getSemanticVersion;

@end
#endif
