/*
 Copyright (c) 2015, salesforce.com, inc. All rights reserved.
 
 Redistribution and use of this software in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright notice, this list of conditions
 and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright notice, this list of
 conditions and the following disclaimer in the documentation and/or other materials provided
 with the distribution.
 * Neither the name of salesforce.com, inc. nor the names of its contributors may be used to
 endorse or promote products derived from this software without specific prior written
 permission of salesforce.com, inc.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import <XCTest/XCTest.h>
#import "SFSmartSyncSyncManager.h"
#import <SalesforceSDKCore/SFUserAccountManager.h>
#import <SalesforceSDKCore/TestSetupUtils.h>
#import <SalesforceSDKCore/SFJsonUtils.h>
#import <SalesforceRestAPI/SFRestAPI.h>
#import <SalesforceSDKCore/SFAuthenticationManager.h>

#define COUNT_TEST_ACCOUNTS 10

@interface SFSmartSyncSyncManager()
- (NSString*) addFilterForReSync:(NSString*)query maxTimeStamp:(long long)maxTimeStamp;
@end

@interface SyncManagerTests : XCTestCase
{
    SFUserAccount *currentUser;
    SFSmartSyncSyncManager *syncManager;
    NSDictionary* idToNames;
}
@end

static NSException *authException = nil;

@implementation SyncManagerTests

#pragma mark - setUp/tearDown

+ (void)setUp
{
    @try {
        [SFLogger setLogLevel:SFLogLevelDebug];
        [TestSetupUtils populateAuthCredentialsFromConfigFileForClass:[self class]];
        [TestSetupUtils synchronousAuthRefresh];
    } @catch (NSException *exception) {
        [self log:SFLogLevelDebug format:@"Populating auth from config failed: %@", exception];
        authException = exception;
    }
    [super setUp];
}

- (void)setUp
{
    if (authException) {
        XCTFail(@"Setting up authentication failed: %@", authException);
    }
    [SFRestAPI setIsTestRun:YES];
    [[SFRestAPI sharedInstance] setCoordinator:[SFAuthenticationManager sharedManager].coordinator];
    currentUser = [SFUserAccountManager sharedInstance].currentUser;
    syncManager = [SFSmartSyncSyncManager sharedInstance:currentUser];
    [self createAccountsSoup];
    idToNames = [self createTestAccountsOnServer:COUNT_TEST_ACCOUNTS];
    [super setUp];
}

- (void)tearDown
{
    [SFSmartSyncSyncManager removeSharedInstance:currentUser];
    [[SFRestAPI sharedInstance] cleanup];
    [SFRestAPI setIsTestRun:NO];
    
    // Some test runs were failing, saying the run didn't complete. This seems to fix that.
    [NSThread sleepForTimeInterval:0.1];
    [super tearDown];
}

#pragma mark - tests

/**
 * getSyncStatus should return null for invalid sync id
 */
- (void)testGetSyncStatusForInvalidSyncId
{
    SFSyncState* sync = [syncManager getSyncStatus:[NSNumber numberWithInt:-1]];
    XCTAssertTrue(sync == nil, @"Sync status should be nil");
}


/**
 * Sync down the test accounts, check smart store, check status during sync
 */
- (void)testSyncDown
{
    // first sync down
    [self trySyncDown:SFSyncStateMergeModeOverwrite];
    
    // Check that db was correctly populated
    [self checkDb:idToNames];
}

/**
 * Test addFilterForReSync with various queries
 */
- (void) testAddFilterForResync
{
    NSDateFormatter* isoDateFormatter = [NSDateFormatter new];
    isoDateFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss.SSSZ";
    NSDate* date = [NSDate new];
    long long dateLong = (long long)([date timeIntervalSince1970] * 1000.0);
    NSString* dateStr = [isoDateFormatter stringFromDate:date];
    
    // Original queries
    NSString* originalBasicQuery = @"select Id from Account";
    NSString* originalLimitQuery = @"select Id from Account limit 100";
    NSString* originalNameQuery = @"select Id from Account where Name = 'John'";
    NSString* originalNameLimitQuery = @"select Id from Account where Name = 'John' limit 100";
    NSString* originalBasicQueryUpper = @"SELECT Id FROM Account";
    NSString* originalLimitQueryUpper = @"SELECT Id FROM Account LIMIT 100";
    NSString* originalNameQueryUpper = @"SELECT Id FROM Account WHERE Name = 'John'";
    NSString* originalNameLimitQueryUpper = @"SELECT Id FROM Account WHERE Name = 'John' LIMIT 100";
    
    
    // Expected queries
    NSString* basicQuery = [NSString stringWithFormat:@"select Id from Account where LastModifiedDate > %@", dateStr];
    NSString* limitQuery = [NSString stringWithFormat:@"select Id from Account where LastModifiedDate > %@ limit 100", dateStr];
    NSString* nameQuery = [NSString stringWithFormat:@"select Id from Account where LastModifiedDate > %@ and Name = 'John'", dateStr];
    NSString* nameLimitQuery = [NSString stringWithFormat:@"select Id from Account where LastModifiedDate > %@ and Name = 'John' limit 100", dateStr];
    NSString* basicQueryUpper = [NSString stringWithFormat:@"SELECT Id FROM Account where LastModifiedDate > %@", dateStr];
    NSString* limitQueryUpper = [NSString stringWithFormat:@"SELECT Id FROM Account where LastModifiedDate > %@ LIMIT 100", dateStr];
    NSString* nameQueryUpper = [NSString stringWithFormat:@"SELECT Id FROM Account WHERE LastModifiedDate > %@ and Name = 'John'", dateStr];
    NSString* nameLimitQueryUpper = [NSString stringWithFormat:@"SELECT Id FROM Account WHERE LastModifiedDate > %@ and Name = 'John' LIMIT 100", dateStr];

    // Tests
    XCTAssertEqualObjects(basicQuery, [syncManager addFilterForReSync:originalBasicQuery maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(limitQuery, [syncManager addFilterForReSync:originalLimitQuery maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(nameQuery, [syncManager addFilterForReSync:originalNameQuery maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(nameLimitQuery, [syncManager addFilterForReSync:originalNameLimitQuery maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(basicQueryUpper, [syncManager addFilterForReSync:originalBasicQueryUpper maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(limitQueryUpper, [syncManager addFilterForReSync:originalLimitQueryUpper maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(nameQueryUpper, [syncManager addFilterForReSync:originalNameQueryUpper maxTimeStamp:dateLong]);
    XCTAssertEqualObjects(nameLimitQueryUpper, [syncManager addFilterForReSync:originalNameLimitQueryUpper maxTimeStamp:dateLong]);
}


#pragma mark - helper methods

- (void)trySyncDown:(SFSyncStateMergeMode)mergeMode
{
    // TBD
}

- (void)checkDb:(NSDictionary*)idToNames
{
    // TBD
}

- (void)createAccountsSoup
{
    // TBD
}

- (NSDictionary*)createTestAccountsOnServer:(NSUInteger)count
{
    return nil;
}

@end
