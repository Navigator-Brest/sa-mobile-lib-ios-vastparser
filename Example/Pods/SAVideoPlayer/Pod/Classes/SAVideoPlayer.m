//
//  SAVideoPlayer.m
//  Pods
//
//  Created by Gabriel Coman on 05/03/2016.
//
//

#import "SAVideoPlayer.h"
#import "SABlackMask.h"
#import "SACronograph.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

#define AV_END AVPlayerItemDidPlayToEndTimeNotification
#define AV_NOEND AVPlayerItemFailedToPlayToEndTimeNotification
#define AV_STALLED AVPlayerItemPlaybackStalledNotification
#define AV_CHANGED AVAudioSessionRouteChangeNotification
#define ENTER_BG UIApplicationDidEnterBackgroundNotification
#define ENTER_FG UIApplicationWillEnterForegroundNotification
#define AV_STATUS @"status"
#define AV_RATE @"rate"
#define AV_FULL @"playbackBufferFull"
#define AV_EMPTY @"playbackBufferEmpty"
#define AV_KEEPUP @"playbackLikelyToKeepUp"
#define AV_TIME @"loadedTimeRanges"

#define MIN_BUFFER_TO_PLAY 3.5
#define MAX_NR_RECONNECTS 5

@interface SAVideoPlayer ()

// the URL
@property (nonatomic, strong) NSURL *mediaURL;

// subviews
@property (nonatomic, strong) UIView *videoView;
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) AVPlayerItem *playerItem;


@property (nonatomic, strong) UIView *chrome;
@property (nonatomic, strong) SABlackMask *mask;
@property (nonatomic, strong) SACronograph *chrono;
@property (nonatomic, strong) SAURLClicker *clicker;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;

// states
@property (nonatomic, assign) BOOL isReadyHandled;
@property (nonatomic, assign) BOOL isStartHandled;
@property (nonatomic, assign) BOOL isFirstQuartileHandled;
@property (nonatomic, assign) BOOL isMidpointHandled;
@property (nonatomic, assign) BOOL isThirdQuartileHandled;
@property (nonatomic, assign) BOOL isEndHandled;

// notification center reference
@property (nonatomic, strong) NSNotificationCenter *notif;
@property (nonatomic, strong) NSObject *observer;

// buffer variables in case network is shaky and buffer goes empty too soon
@property (nonatomic, assign) BOOL isPlaybackBufferEmpty;
@property (nonatomic, assign) BOOL shouldShowSpinner;

// network reconnect variables
@property (nonatomic, assign) NSInteger currentReconnectTries;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) BOOL isNetworkHavingProblems;

@end

@implementation SAVideoPlayer

#pragma mark <Init>

- (id) init {
    if (self = [super init]) {
        _notif = [NSNotificationCenter defaultCenter];
        _shouldShowSpinner = false;
        _shouldShowSmallClickButton = false;
    }
    return self;
}

- (id) initWithCoder:(NSCoder *)aDecoder {
    if (self = [super initWithCoder:aDecoder]) {
        _notif = [NSNotificationCenter defaultCenter];
        _shouldShowSpinner = false;
        _shouldShowSmallClickButton = false;
    }
    return self;
}

- (id) initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        _notif = [NSNotificationCenter defaultCenter];
        _shouldShowSpinner = false;
        _shouldShowSmallClickButton = false;
    }
    return self;
}

#pragma mark <Check handling>

- (void) resetChecks {
    _isStartHandled =
    _isFirstQuartileHandled =
    _isMidpointHandled =
    _isThirdQuartileHandled =
    _isEndHandled = false;

    _isPlaybackBufferEmpty = false;
    _currentReconnectTries = -1;
    _isNetworkHavingProblems = false;
}

#pragma mark <Setup> functions

- (void) setup {
    self.backgroundColor = [UIColor blackColor];
    [self setupPlayer];
    [self setupChome];
    [self resetChecks];
}

- (void) setupPlayer {
    // create the video view
    _videoView = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_videoView];
}

- (void) setupChome {
    _chrome = [[UIView alloc] initWithFrame:self.bounds];
    [self addSubview:_chrome];
    
    _mask = [[SABlackMask alloc] init];
    [_chrome addSubview:_mask];
    
    _chrono = [[SACronograph alloc] init];
    [_chrome addSubview:_chrono];
    
    _clicker = [[SAURLClicker alloc] init];
    _clicker.shouldShowSmallClickButton = _shouldShowSmallClickButton;
    [_clicker addTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    [_chrome addSubview:_clicker];

//    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
//    _spinner.center = _chrome.center;
//    [_chrome addSubview:_spinner];
//    [_spinner startAnimating];
//    _spinner.hidden = !_shouldShowSpinner;
}

#pragma mark <Destroy> functions

- (void) destroy {
    [self destroyPlayer];
    [self destroyChrome];
    
    if (_timer) {
        [_timer invalidate];
        _timer = NULL;
    }
}

- (void) destroyPlayer {
    [_notif removeObserver:self name:AV_END object:nil];
    [_notif removeObserver:self name:AV_NOEND object:nil];
    [_notif removeObserver:self name:AV_STALLED object:nil];
    [_notif removeObserver:self name:AV_CHANGED object:nil];
    [_notif removeObserver:self name:ENTER_BG object:nil];
    [_notif removeObserver:self name:ENTER_FG object:nil];
    [_player removeObserver:self forKeyPath:AV_RATE context:nil];
    [_player removeTimeObserver:_observer];
    _observer = NULL;
    [_playerItem removeObserver:self forKeyPath:AV_STATUS context:nil];
    [_playerItem removeObserver:self forKeyPath:AV_FULL context:nil];
    [_playerItem removeObserver:self forKeyPath:AV_EMPTY context:nil];
    [_playerItem removeObserver:self forKeyPath:AV_KEEPUP context:nil];
    [_playerItem removeObserver:self forKeyPath:AV_TIME context:nil];
    
    
    if (_player){
        [_player pause];
        [_playerLayer removeFromSuperlayer];
        _playerItem = NULL;
        _playerLayer = NULL;
        _player = NULL;
    }
    
    [_videoView removeFromSuperview];
    _videoView = NULL;
}

- (void) destroyChrome {
    [_mask removeFromSuperview];
    [_chrono removeFromSuperview];
    [_clicker removeTarget:self action:@selector(onClick:) forControlEvents:UIControlEventTouchUpInside];
    [_clicker removeFromSuperview];
    [_chrome removeFromSuperview];
//    [_spinner stopAnimating];
//    [_spinner removeFromSuperview];
    _mask = NULL;
    _clicker = NULL;
    _chrono = NULL;
    _chrome = NULL;
//    _spinner = NULL;
}

#pragma mark <Update> functions

- (void) updateToFrame:(CGRect)frame {
    self.frame = frame;
    _videoView.frame = self.bounds;
    _playerLayer.frame = _videoView.bounds;
    _chrome.frame = self.bounds;
    [self destroyChrome];
    [self setupChome];
}

- (void) reset {
    [self destroy];
    [self setup];
}

#pragma mark <Resume & Pause> functions

- (void) resume {
    [_player play];
}

- (void) pause {
    [_player pause];
}

#pragma mark <Play> function

- (void) playWithMediaURL:(NSURL *)url {
    [self setup];
    _mediaURL = url;
    _playerItem = [AVPlayerItem playerItemWithURL:_mediaURL];
    _player = [AVPlayer playerWithPlayerItem:_playerItem];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = _videoView.bounds;
    [_videoView.layer addSublayer:_playerLayer];
    [_player seekToTime:kCMTimeZero];
    [_player play];
    
    [self setObservers];
}

- (void) playWithMediaFile:(NSString *)file {
    [self setup];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:file isDirectory:false];
    AVAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    _playerItem = [AVPlayerItem playerItemWithAsset:asset];
    _player = [AVPlayer playerWithPlayerItem:_playerItem];
    _playerLayer = [AVPlayerLayer playerLayerWithPlayer:_player];
    _playerLayer.frame = _videoView.bounds;
    [_videoView.layer addSublayer:_playerLayer];
    [_player play];
    
    [self setObservers];
}

- (void) setObservers {
    
    NSError *setCategoryErr;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:&setCategoryErr];
    
    [_notif addObserver:self selector:@selector(playerItemDidReachEnd:) name:AV_END object:nil];
    [_notif addObserver:self selector:@selector(playerItemFailedToPlayEndTime:) name:AV_NOEND object:nil];
    [_notif addObserver:self selector:@selector(playerItemPlaybackStall:) name:AV_STALLED object:nil];
    [_notif addObserver:self selector:@selector(audioSessionChanged:) name:AV_CHANGED object:nil];
    [_notif addObserver:self selector:@selector(playerItemEnterBackground:) name:ENTER_BG object:nil];
    [_notif addObserver:self selector:@selector(playerItemEnterForeground:) name:ENTER_FG object:nil];
    [_player addObserver:self forKeyPath:AV_RATE options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:AV_STATUS options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:AV_EMPTY options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:AV_FULL options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:AV_KEEPUP options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
    [_playerItem addObserver:self forKeyPath:AV_TIME options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew context:nil];
}

#pragma mark <Click> function

- (void) onClick:(id)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(didGoToURL)]) {
        [_delegate didGoToURL];
    }
}

#pragma mark <AVPlayer> events

- (void) playerItemDidReachEnd: (NSNotification*)notification {
//    _spinner.hidden = YES;
    
    // delegate
    if (!_isEndHandled && _delegate && [_delegate respondsToSelector:@selector(didReachEnd)]){
        _isEndHandled = true;
        [_delegate didReachEnd];
    }
}

- (void) playerItemFailedToPlayEndTime: (NSNotification*)notification {
    
}

- (void) playerItemPlaybackStall: (NSNotification*)notification {
    [_player play];
}

- (void) playerItemEnterBackground: (NSNotification*)notification {
    
    [_player pause];
}

- (void) playerItemEnterForeground: (NSNotification*)notification {
    [_player play];
}

- (void) audioSessionChanged: (NSNotification*) notification {
    NSInteger routeChangeReason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] integerValue];
    if (routeChangeReason == AVAudioSessionRouteChangeReasonOldDeviceUnavailable) {
        [_player play];
    }
}

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void *)context {
    if (object == _player && [keyPath isEqualToString:AV_RATE]){
        NSLog(@"[KVO] %@ %f", AV_RATE, _player.rate);
    }
    if (object == _playerItem && [keyPath isEqualToString:AV_STATUS]) {
        if (_playerItem.status == AVPlayerItemStatusReadyToPlay) {
            [_player play];
            NSLog(@"[KVO] %@: Ready", AV_STATUS);
            _isNetworkHavingProblems = false;
            
            // delegate
            if (!_isReadyHandled && _delegate && [_delegate respondsToSelector:@selector(didFindPlayerReady)]){
                [_delegate didFindPlayerReady];
            }
            
            // weak self so I don't have a retain cycle in the block
            __weak typeof (self) weakSelf = self;
            
            _observer = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 2) queue:dispatch_get_main_queue() usingBlock:^(CMTime currentTime) {
                
                // update current time
                CGFloat time = CMTimeGetSeconds(currentTime);
                CGFloat duration = CMTimeGetSeconds(weakSelf.playerItem.duration);
                NSInteger remaining = (NSInteger)(duration - time);
                
                // each tick update chrono
                dispatch_async(dispatch_get_main_queue(), ^{
                    [weakSelf.chrono setTime:remaining];
                });
                
                // send events through delegation
                if (time >= 1 && !weakSelf.isStartHandled && weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(didStartPlayer)]) {
                    weakSelf.isStartHandled = true;
                    [weakSelf.delegate didStartPlayer];
                };
                
                if (time >= (duration / 4) && !weakSelf.isFirstQuartileHandled && weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(didReachFirstQuartile)]){
                    weakSelf.isFirstQuartileHandled = true;
                    [weakSelf.delegate didReachFirstQuartile];
                }
                
                if (time >= (duration / 2) && !weakSelf.isMidpointHandled && weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(didReachMidpoint)]){
                    weakSelf.isMidpointHandled = true;
                    [weakSelf.delegate didReachMidpoint];
                }
                
                if (time >= (3 * duration / 4) && !weakSelf.isThirdQuartileHandled && weakSelf.delegate && [weakSelf.delegate respondsToSelector:@selector(didReachThirdQuartile)]) {
                    weakSelf.isThirdQuartileHandled = true;
                    [weakSelf.delegate didReachThirdQuartile];
                }
            }];
        }
        if (_playerItem.status == AVPlayerItemStatusFailed) {
            NSLog(@"[KVO] %@: Failed", AV_STATUS);
            _isNetworkHavingProblems = true;
            if (!_timer) {
                _timer = [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(reconnectFunc) userInfo:nil repeats:YES];
                [_timer fire];
            }
        }
        if (_playerItem.status == AVPlayerItemStatusUnknown) {
            NSLog(@"[KVO] %@: Unknown", AV_STATUS);
        }
    }
    if (object == _playerItem && [keyPath isEqualToString:AV_FULL]) {
        NSLog(@"[KVO] %@ %d", AV_FULL, _playerItem.isPlaybackBufferFull);
    }
    if (object == _playerItem && [keyPath isEqualToString:AV_EMPTY]) {
        NSLog(@"[KVO] %@ %d", AV_EMPTY, _playerItem.isPlaybackBufferEmpty);
        // if this gets called, then there is no more data in the buffer and we should pause the video
        _isPlaybackBufferEmpty = true;
        [_player pause];
        
        // start spinner
        dispatch_async(dispatch_get_main_queue(), ^{
            _shouldShowSpinner = YES;
//            _spinner.hidden = !_shouldShowSpinner;
        });
    }
    if (object == _playerItem && [keyPath isEqualToString:AV_KEEPUP]) {
        NSLog(@"[KVO] %@ %d", AV_KEEPUP, _playerItem.isPlaybackLikelyToKeepUp);
    }
//    if (object == _playerItem && [keyPath isEqualToString:AV_TIME]) {
//        NSValue *timeRangeValue = _playerItem.loadedTimeRanges.firstObject;
//        CMTimeRange timeRange;
//        [timeRangeValue getValue:&timeRange];
//        
//        CGFloat assetTime = CMTimeGetSeconds(_playerItem.currentTime);
//        CGFloat assetDuration = CMTimeGetSeconds(_playerItem.asset.duration);
//        CGFloat bufferStart = CMTimeGetSeconds(timeRange.start);
//        CGFloat bufferDuration = CMTimeGetSeconds(timeRange.duration);
//        NSLog(@"[KVO] Loaded time %.2f to %.2f at %.2f / %.2f", bufferStart, bufferDuration, assetTime, assetDuration);
//    
//        // there is enough data in the buffer to play
//        if (_isPlaybackBufferEmpty && bufferDuration >= MIN_BUFFER_TO_PLAY) {
//            _isPlaybackBufferEmpty = false;
//            [_player play];
//            
//            // and stop spinner
//            dispatch_async(dispatch_get_main_queue(), ^{
//                _shouldShowSpinner = NO;
//                _spinner.hidden = !_shouldShowSpinner;
//            });
//        }
//    }
}

- (void) reconnectFunc {
    if (_isNetworkHavingProblems) {
        if (_currentReconnectTries < MAX_NR_RECONNECTS) {
            _currentReconnectTries++;
            NSLog(@"Trying to reconnect ... %ld / %d", (long)_currentReconnectTries, MAX_NR_RECONNECTS);
            [self destroyPlayer];
            [self setupPlayer];
            [self bringSubviewToFront:_chrome];
            [self playWithMediaURL:_mediaURL];
        } else {
            // destroy
            [self destroy];
            
            // delegate
            if (_delegate && [_delegate respondsToSelector:@selector(didPlayWithError)]){
                [_delegate didPlayWithError];
            }
        }
    } else {
        if (_timer) {
            [_timer invalidate];
            _timer = NULL;
        }
    }
}

- (AVPlayer*) getPlayer {
    return _player;
}

- (AVPlayerLayer*) getPlayerLayer {
    return _playerLayer;
}

#pragma mark <Dealloc> 

- (void) dealloc {
    NSLog(@"SAVideoPlayer dealloc");
}

@end
