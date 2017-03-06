//
//  UTAVideoURLService.h
//  UTALib
//
//  Created by David on 16/5/31.
//  Copyright © 2016年 UTA. All rights reserved.
//
#import "UTAVideoURLService.h"

#define UTAVideoURlServiceTimeout 60.0f

static NSString * USER_AGENT_PHONE = @"Mozilla/5.0 (iPhone; CPU iPhone OS 8_0 like Mac OS X) AppleWebKit/601.1.46 (KHTML, like Gecko) Mobile/13E238";
// 记录原始地址对应的解析器，一对多的关系： @{@"link":@[UTAVideoURLService]}
static NSMutableDictionary * _dictServices;
// 缓存已经解析过的视频地址：@{@"link":@"url"}
static NSMutableDictionary * _dictUrlResolved;

@interface UTAVideoURLService () <UIWebViewDelegate>
{
    UIWebView *_webView;
    NSTimer *_timerResolveVideo;
    NSTimeInterval _timeTicket;
    
    NSString *_originLink;
    NSString *_userAgentDefault;
}

@property (nonatomic, assign) NSTimeInterval timeout;
@property (nonatomic, copy) UTAVideoURLServiceCompletion completion;

@end

@implementation UTAVideoURLService

+ (void)resolveVideoURLWithOriginLink:(nonnull NSString *)link completion:(nonnull UTAVideoURLServiceCompletion)completion {
    [UTAVideoURLService resolveVideoURLWithOriginLink:link timeout:UTAVideoURlServiceTimeout completion:completion];
}

+ (void)resolveVideoURLWithOriginLink:(nonnull NSString *)link timeout:(NSTimeInterval)timeout completion:(nonnull UTAVideoURLServiceCompletion)completion {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _dictServices = @{}.mutableCopy;
        _dictUrlResolved = @{}.mutableCopy;
    });
    
    if (!link) {
        if (completion) {
            NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                                 code:NSURLErrorTimedOut
                                             userInfo:@{NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"视频地址解析超时: %@", nil],
                                                        NSLocalizedRecoverySuggestionErrorKey:@"世上无难事，只要肯放弃; >_<"}];
            completion(nil, error);
        }
        return;
    }
    
    NSURL *url = _dictUrlResolved[link];
    if (url) { completion(url, nil); return;}
    
    UTAVideoURLService *service = [[UTAVideoURLService alloc] init];
    service.completion = completion;
    service.timeout = timeout;
    NSMutableArray *arrServices = _dictServices[link];
    if (!arrServices) {
        arrServices = @[].mutableCopy;
        _dictServices[link] = arrServices;
    }
    if (arrServices.count==0) {
        // 该原始地址已存在解析列表中，则不再解析，只存一个空解析器，否则才解析
        [service startWithLink:link];
    }
    [arrServices addObject:service];
}

+ (void)cancelResolveWithOriginLink:(nonnull NSString *)link {
    NSArray<UTAVideoURLService *> *services = _dictServices[link];
    [services enumerateObjectsUsingBlock:^(UTAVideoURLService * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        [obj cancel];
    }];
}

- (void)cancel {
    [self stopService];
    
    // 解析超时，删除当前任务
    if (_completion) {
        NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                             code:NSURLErrorTimedOut
                                         userInfo:@{NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"已经取消视频解析: %@", _originLink],
                                                    NSLocalizedRecoverySuggestionErrorKey:@"世上无难事，只要肯放弃; >_<"}];
        _completion(nil, error);
    }
    
    [_dictServices removeObjectForKey:_originLink];
    _originLink = nil;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _timeTicket = 0;
    }
    return self;
}

- (void)dealloc {
    [self stopService];
    NSLog(@"%s", __FUNCTION__);
}

- (NSString *)getYouKuVidWithLink:(NSString *)link {
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"(?<=(id_|player.youku.com/embed/|player.youku.com/player.php/sid/))([a-zA-Z0-9]+)" options:kNilOptions error:nil];
    NSTextCheckingResult *tcr = [reg firstMatchInString:link options:kNilOptions range:NSMakeRange(0, link.length)];
    return [link substringWithRange:tcr.range];
}

- (NSString *)getYouTuBeVidWithLink:(NSString *)link {
    // https://www.youtube.com/watch?v=I_44Zl4Pdos&spfreload=10&app=desktop
    NSRegularExpression *reg = [NSRegularExpression regularExpressionWithPattern:@"(?<=(youtube.com/embed/|youtu.be/|v=))([a-zA-Z0-9_]+)" options:kNilOptions error:nil];
    NSTextCheckingResult *tcr = [reg firstMatchInString:link options:kNilOptions range:NSMakeRange(0, link.length)];
    return [link substringWithRange:tcr.range];
}

#pragma mark - public methods
- (void)startWithLink:(NSString *)link {
    [self stopService];
    
    // 记录当前UA，完成后需要还原；
    _userAgentDefault = [[UIWebView new] stringByEvaluatingJavaScriptFromString:@"navigator.userAgent"];
    
    _originLink = link;
    _webView = [[UIWebView alloc] init];
    _webView.delegate = self;
    
    // ***** 关键代码
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent":USER_AGENT_PHONE}];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    NSURL *url = [NSURL URLWithString:link];
    if ([url.host rangeOfString:@"youtube.com" options:NSCaseInsensitiveSearch].location!=NSNotFound) {
        // eg.https://www.youtube.com/embed/JopNqvzMIqE
        link = [@"https://www.youtube.com/embed/" stringByAppendingString:[self getYouTuBeVidWithLink:link]];
        NSMutableURLRequest *muq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:link]];
        [_webView loadRequest:muq];
    }
    else if ([url.host rangeOfString:@"youku.com" options:NSCaseInsensitiveSearch].location!=NSNotFound) {
        NSString *vid = [self getYouKuVidWithLink:link];
        if (vid.length==0) {
            [self stopService];
            if (_completion) {
                NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                                     code:NSURLErrorTimedOut
                                                 userInfo:@{NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"视频地址解析失败: %@", _originLink],
                                                            NSLocalizedRecoverySuggestionErrorKey:@"世上无难事，只要肯放弃; >_<"}];
                _completion(nil, error);
            }
            return;
        }
        // 2016.12.24 紧急更新 优酷视频解析问题
        /**
         NSString *html = [NSString stringWithFormat:@"<div id=\"youkuplayer\" style=\"width:100%%;height:100%%\"></div> <script type=\"text/javascript\" src=\"http://player.youku.com/jsapi\"> player = new YKU.Player('youkuplayer',{ styleid: '0', client_id: '067e1d65d35f5b07', vid: '%@',autoplay: true}); </script>", vid];
         [_webView loadHTMLString:html baseURL:nil];
         */
        [_webView loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:[@"http://player.youku.com/embed/" stringByAppendingString:vid]]]];
    }
    else {
        NSMutableURLRequest *muq = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:link]];
        [_webView loadRequest:muq];
    }
    
    // 超时计时器
    _timerResolveVideo = [NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(timeTicket) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_timerResolveVideo forMode:NSRunLoopCommonModes];
}

- (void)stopService {
    [_timerResolveVideo invalidate];
    _timerResolveVideo = nil;
    
    _webView.delegate = nil;
    [_webView stopLoading];
    [_webView loadHTMLString:@"" baseURL:nil];
    _webView = nil;
    
    if (_userAgentDefault) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent":_userAgentDefault}];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)timeTicket {
    _timeTicket+=_timerResolveVideo.timeInterval;
    if (_timeTicket>=_timeout) {
        // 解析超时，删除当前任务
        [self stopService];
        [_dictServices removeObjectForKey:_originLink];
        
        if (_completion) {
            NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                                 code:NSURLErrorTimedOut
                                             userInfo:@{NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"视频地址解析超时: %@", _originLink],
                                                        NSLocalizedRecoverySuggestionErrorKey:@"世上无难事，只要肯放弃; >_<"}];
            _completion(nil, error);
        }
    }
}

#pragma mark - UIWebViewDelegate
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    if ([request.URL.scheme isEqualToString:@"youkuhd"]
        || [request.URL.scheme isEqualToString:@"youku"]) {
        return NO;
    }
    return YES;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    if (!_timerResolveVideo) {
        return;
    }
    
    if (_timerResolveVideo.timeInterval==1) {
        [_timerResolveVideo invalidate];
        _timerResolveVideo = nil;
        
        _timerResolveVideo = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(resovleVideo) userInfo:nil repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:_timerResolveVideo forMode:NSRunLoopCommonModes];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    if (NSURLErrorNotConnectedToInternet==error.code && _completion) {
        [self stopService];
        _completion(nil, error);
        [_dictServices removeObjectForKey:_originLink];
    }
}

- (void)resovleVideo {
    _timeTicket+=_timerResolveVideo.timeInterval;
    
    NSString *videoLink = [_webView stringByEvaluatingJavaScriptFromString:@"var l=document.getElementsByTagName('video')[0].src;if(''==l){l=document.getElementsByTagName('video')[0].childNodes[0].src;if(''!=l){l;}}else{l;}"];
    if (videoLink.length==0 && [[_webView stringByEvaluatingJavaScriptFromString:@"document.location.href"] rangeOfString:@"youtube.com" options:NSCaseInsensitiveSearch].location!=NSNotFound) {
        // youtube.com
        [_webView stringByEvaluatingJavaScriptFromString:@"document.getElementsByClassName('ytp-thumbnail-overlay ytp-cued-thumbnail-overlay')[0].click()"];
    }

    if (videoLink.length>0) {
        [self stopService];
        
        NSURL *url = [NSURL URLWithString:videoLink];
        NSMutableArray *arrServices = _dictServices[_originLink];
        for (UTAVideoURLService *service in arrServices) {
            if (service.completion) {
                service.completion(url, nil);
            }
        }
        
        if ([[NSURL URLWithString:_originLink].host rangeOfString:@"iqiyi.com" options:NSCaseInsensitiveSearch].location==NSNotFound) {
            // 不缓存奇艺视频地址，更新太频繁了；
            _dictUrlResolved[_originLink] = url;
        }
        [_dictServices removeObjectForKey:_originLink];
    }
    else if (_timeTicket>=_timeout) {
        [self stopService];
        [_dictServices removeObjectForKey:_originLink];
        
        // 解析超时，删除当前任务
        if (_completion) {
            NSError *error = [NSError errorWithDomain:NSStringFromClass([self class])
                                                 code:NSURLErrorTimedOut
                                             userInfo:@{NSLocalizedFailureReasonErrorKey:[NSString stringWithFormat:@"视频地址解析超时: %@", _originLink],
                                                        NSLocalizedRecoverySuggestionErrorKey:@"世上无难事，只要肯放弃; >_<"}];
            _completion(nil, error);
        }
        
    }
}

@end
