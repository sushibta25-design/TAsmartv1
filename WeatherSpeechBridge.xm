#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <notify.h>

static const char *kWSBWeatherNotify = "com.sushibta.vmlspeedbubble.weather";
static NSString * const kWSBPayloadPath = @"/var/mobile/VMLWeatherPayload.plist";
static NSString * const kWSBLogPath = @"/var/mobile/VMLWeatherSpeech.txt";
static NSString * const kWSBPrefsPath = @"/var/mobile/Library/Preferences/com.sushibta.vmlspeedbubble.plist";
static NSString * const kWSBKeyFilePath = @"/var/mobile/VMLFPTKey.txt";
static NSString * const kWSBFPTEndpoint = @"https://api.fpt.ai/hmi/tts/v5";
static int gWSBToken = 0;
static AVSpeechSynthesizer *gWSBSpeech = nil;
static AVAudioPlayer *gWSBPlayer = nil;
static NSUInteger gWSBRequestGeneration = 0;

static BOOL WSBIsSpringBoard(void){return [NSBundle.mainBundle.bundleIdentifier isEqualToString:@"com.apple.springboard"];}

static void WSBLog(NSString *format,...){
    va_list args;va_start(args,format);NSString *msg=[[NSString alloc]initWithFormat:format arguments:args];va_end(args);
    NSString *line=[NSString stringWithFormat:@"%@ | %@\n",[NSDate date],msg?:@""];NSData *data=[line dataUsingEncoding:NSUTF8StringEncoding];
    if(![[NSFileManager defaultManager]fileExistsAtPath:kWSBLogPath]){[data writeToFile:kWSBLogPath atomically:YES];return;}
    NSFileHandle *fh=[NSFileHandle fileHandleForWritingAtPath:kWSBLogPath];if(!fh)return;
    @try{[fh seekToEndOfFile];[fh writeData:data];[fh closeFile];}@catch(__unused NSException *e){}
}

static BOOL WSBIsRain(NSInteger code){return (code>=51&&code<=57)||(code>=61&&code<=67)||(code>=80&&code<=82);}
static NSString *WSBSentence(NSString *name,double temp,NSInteger code){
    NSString *place=name.length?name:@"điểm đến";
    if(code==0)return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại trời nắng, nhiệt độ %.0f độ. Hãy chú ý mang theo dù.",place,temp];
    if(WSBIsRain(code))return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại đang mưa, nhiệt độ %.0f độ. Hãy chú ý mang theo áo mưa.",place,temp];
    if(code>=95)return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại có dông, nhiệt độ %.0f độ. Hãy chú ý mang theo áo mưa và cẩn thận khi di chuyển.",place,temp];
    if(code==45||code==48)return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại có sương mù, nhiệt độ %.0f độ. Hãy chú ý quan sát khi di chuyển.",place,temp];
    if(code>=71&&code<=77)return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại có tuyết, nhiệt độ %.0f độ. Hãy chú ý giữ ấm và cẩn thận khi di chuyển.",place,temp];
    if(code<=3)return [NSString stringWithFormat:@"Điểm đến là %@, hiện tại có mây, nhiệt độ %.0f độ.",place,temp];
    return [NSString stringWithFormat:@"Điểm đến là %@, nhiệt độ hiện tại %.0f độ.",place,temp];
}

static NSString *WSBFPTAPIKey(void){
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:kWSBPrefsPath];
    NSString *key=[prefs[@"FPTAPIKey"] isKindOfClass:NSString.class]?prefs[@"FPTAPIKey"]:nil;
    if(!key.length){
        key=[NSString stringWithContentsOfFile:kWSBKeyFilePath encoding:NSUTF8StringEncoding error:nil];
    }
    key=[key stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    return key.length?key:nil;
}

static void WSBPrepareAudioSession(void){
    NSError *err=nil;AVAudioSession *session=AVAudioSession.sharedInstance;
    BOOL ok=[session setCategory:AVAudioSessionCategoryPlayback mode:AVAudioSessionModeSpokenAudio options:AVAudioSessionCategoryOptionDuckOthers error:&err];
    WSBLog(@"audio category ok=%d error=%@",ok,err.localizedDescription?:@"none");
    err=nil;ok=[session setActive:YES error:&err];WSBLog(@"audio active ok=%d error=%@",ok,err.localizedDescription?:@"none");
}

static AVSpeechSynthesisVoice *WSBSystemVoice(void){AVSpeechSynthesisVoice *v=[AVSpeechSynthesisVoice voiceWithLanguage:@"vi-VN"];if(!v)v=[AVSpeechSynthesisVoice voiceWithLanguage:@"vi"];return v;}

static void WSBSystemFallback(NSString *sentence){
    dispatch_async(dispatch_get_main_queue(),^{
        WSBPrepareAudioSession();
        if(!gWSBSpeech)gWSBSpeech=[AVSpeechSynthesizer new];
        if(gWSBPlayer.isPlaying)[gWSBPlayer stop];
        [gWSBSpeech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        AVSpeechUtterance *u=[AVSpeechUtterance speechUtteranceWithString:sentence];AVSpeechSynthesisVoice *voice=WSBSystemVoice();if(voice)u.voice=voice;
        u.rate=.44;u.pitchMultiplier=1.06;u.volume=1.0;u.preUtteranceDelay=.15;
        WSBLog(@"fallback system voice=%@ sentence=%@",voice.language?:@"nil",sentence);
        [gWSBSpeech speakUtterance:u];
    });
}

static void WSBPlayFPTData(NSData *data,NSString *sentence){
    dispatch_async(dispatch_get_main_queue(),^{
        WSBPrepareAudioSession();
        [gWSBSpeech stopSpeakingAtBoundary:AVSpeechBoundaryImmediate];
        if(gWSBPlayer.isPlaying)[gWSBPlayer stop];
        NSError *err=nil;gWSBPlayer=[[AVAudioPlayer alloc]initWithData:data error:&err];
        if(!gWSBPlayer||err){WSBLog(@"FPT player create failed=%@",err.localizedDescription?:@"unknown");WSBSystemFallback(sentence);return;}
        gWSBPlayer.volume=1.0;[gWSBPlayer prepareToPlay];BOOL ok=[gWSBPlayer play];WSBLog(@"FPT Linh San play ok=%d bytes=%lu",ok,(unsigned long)data.length);
        if(!ok)WSBSystemFallback(sentence);
    });
}

static void WSBPollFPTAudio(NSURL *audioURL,NSString *sentence,NSUInteger generation,NSInteger attempt){
    if(generation!=gWSBRequestGeneration)return;
    if(attempt>30){WSBLog(@"FPT audio timeout url=%@",audioURL.absoluteString);WSBSystemFallback(sentence);return;}
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:audioURL cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:12.0];
    req.HTTPMethod=@"GET";
    [[[NSURLSession sharedSession]dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        if(generation!=gWSBRequestGeneration)return;
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        NSString *mime=response.MIMEType.lowercaseString?:@"";
        BOOL looksAudio=data.length>1000&&(status>=200&&status<300)&&([mime containsString:@"audio"]||[mime containsString:@"mpeg"]||[mime containsString:@"octet-stream"]||[audioURL.pathExtension.lowercaseString isEqualToString:@"mp3"]);
        WSBLog(@"FPT poll attempt=%ld status=%ld bytes=%lu mime=%@ error=%@",(long)attempt,(long)status,(unsigned long)data.length,mime,error.localizedDescription?:@"none");
        if(looksAudio){WSBPlayFPTData(data,sentence);return;}
        NSTimeInterval delay=attempt<4?2.0:3.0;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(delay*NSEC_PER_SEC)),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{WSBPollFPTAudio(audioURL,sentence,generation,attempt+1);});
    }]resume];
}

static void WSBRequestFPT(NSString *sentence){
    NSString *key=WSBFPTAPIKey();
    if(!key.length){WSBLog(@"FPT key missing; use system fallback");WSBSystemFallback(sentence);return;}
    NSUInteger generation=++gWSBRequestGeneration;
    NSMutableURLRequest *req=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:kWSBFPTEndpoint] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20.0];
    req.HTTPMethod=@"POST";
    [req setValue:key forHTTPHeaderField:@"api_key"];
    [req setValue:@"linhsan" forHTTPHeaderField:@"voice"];
    [req setValue:@"-1" forHTTPHeaderField:@"speed"];
    [req setValue:@"mp3" forHTTPHeaderField:@"format"];
    [req setValue:@"no-cache" forHTTPHeaderField:@"Cache-Control"];
    req.HTTPBody=[sentence dataUsingEncoding:NSUTF8StringEncoding];
    WSBLog(@"FPT request voice=linhsan speed=-1 chars=%lu",(unsigned long)sentence.length);
    [[[NSURLSession sharedSession]dataTaskWithRequest:req completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        if(generation!=gWSBRequestGeneration)return;
        NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        if(error||!data.length){WSBLog(@"FPT request failed status=%ld error=%@",(long)status,error.localizedDescription?:@"none");WSBSystemFallback(sentence);return;}
        NSError *jsonError=nil;NSDictionary *json=[NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
        NSInteger apiError=[json[@"error"] respondsToSelector:@selector(integerValue)]?[json[@"error"] integerValue]:-1;
        NSString *async=[json[@"async"] isKindOfClass:NSString.class]?json[@"async"]:nil;
        WSBLog(@"FPT response http=%ld apiError=%ld async=%@ jsonError=%@",(long)status,(long)apiError,async?:@"nil",jsonError.localizedDescription?:@"none");
        NSURL *audioURL=async.length?[NSURL URLWithString:async]:nil;
        if(status<200||status>=300||apiError!=0||!audioURL){WSBSystemFallback(sentence);return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{WSBPollFPTAudio(audioURL,sentence,generation,1);});
    }]resume];
}

static void WSBSpeakPayload(void){
    NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:kWSBPayloadPath];if(![p isKindOfClass:NSDictionary.class]){WSBLog(@"payload missing");return;}
    NSString *name=[p[@"name"] isKindOfClass:NSString.class]?p[@"name"]:[p[@"name"] description];double temp=[p[@"temperature"] doubleValue];NSInteger code=[p[@"weather_code"] integerValue];
    NSString *sentence=WSBSentence(name,temp,code);WSBRequestFPT(sentence);
}

static void WSBStart(void){
    if(!WSBIsSpringBoard()||gWSBToken)return;int token=0;
    uint32_t s=notify_register_dispatch(kWSBWeatherNotify,&token,dispatch_get_main_queue(),^(__unused int incoming){WSBSpeakPayload();});
    if(s==NOTIFY_STATUS_OK){gWSBToken=token;WSBLog(@"receiver ready token=%d",token);}else WSBLog(@"receiver failed status=%u",s);
}

%ctor{@autoreleasepool{if(!WSBIsSpringBoard())return;WSBLog(@"16.17 FPT Linh San speech bridge loaded");WSBStart();}}
