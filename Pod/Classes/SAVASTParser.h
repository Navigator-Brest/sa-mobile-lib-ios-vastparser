//
//  SAVAST2Parser.h
//  Pods
//
//  Created by Gabriel Coman on 17/12/2015.
//
//

#import <Foundation/Foundation.h>

////////////////////////////////////////////////////////////////////////////////
// The VASTParser main protocol
////////////////////////////////////////////////////////////////////////////////

// The SAVASTParserProtocol implements two functions
@protocol SAVASTParserProtocol <NSObject>

// Called as a callback when there are valid ads to be displayed
- (void) didParseVASTAndHasAdsResponse:(NSArray*)ads;

// Called as a callback when there are no valid ads to be displayed
- (void) didNotFindAnyValidAds;

// This should be called when the VAST response is entirely corrupted
- (void) didFindInvalidVASTResponse;

@end

////////////////////////////////////////////////////////////////////////////////
// The VASTParser main class
////////////////////////////////////////////////////////////////////////////////

@interface SAVASTParser : NSObject

// weak object delegate to SAVAStParserProtocol
@property (nonatomic, weak) id<SAVASTParserProtocol> delegate;

// parse the VAST URL
- (void) parseVASTURL:(NSString*)url;

@end