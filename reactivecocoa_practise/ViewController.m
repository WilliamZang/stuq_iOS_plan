//
//  ViewController.m
//  reactivecocoa_practise
//
//  Created by ZangChengwei on 16/6/19.
//  Copyright © 2016年 ZangChengwei. All rights reserved.
//

#import "ViewController.h"
#import <ReactiveCocoa.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIView *grid;
@property (weak, nonatomic) IBOutlet UIButton *autoRunBtn;
@property (weak, nonatomic) IBOutlet UIButton *oneStepBtn;

@end

static int GridXBlocks = 13;
static int GridYBlocks = 7;

typedef NS_ENUM(NSUInteger, SpriteState) {
    SpriteStateAppear,
    SpriteStateRunning,
    SpriteStateDisappear,
};

typedef NS_ENUM(NSUInteger, ControlState) {
    ControlStateStop,
    ControlStateAuto,
    ControlStateOneStep,
};
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    UIImage *img1 = [UIImage imageNamed:@"pet1"];
    UIImage *img2 = [UIImage imageNamed:@"pet2"];
    UIImage *img3 = [UIImage imageNamed:@"pet3"];
    
    NSArray *steps = @[RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0), RACTuplePack(@0, @1),
                       RACTuplePack(@0, @1), RACTuplePack(@0, @1),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@0, @-1), RACTuplePack(@0, @-1),
                       RACTuplePack(@1, @0), RACTuplePack(@1, @0),
                       RACTuplePack(@1, @0)
                       ];
    
    RACTuple *startBlock = RACTuplePack(@1, @2);
    
    RACSequence *stepsSequence = steps.rac_sequence;
    
    NSInteger spriteCount = steps.count + 1; // 步数 + 1个起始位置
    
    void (^updateXYConstraints)(UIView *view, RACTuple *location) = ^(UIView *view, RACTuple *location) {
        CGFloat width = self.grid.frame.size.width / GridXBlocks;
        CGFloat height = self.grid.frame.size.height / GridYBlocks;
        CGFloat x = [location.first floatValue] * width;
        CGFloat y = [location.second floatValue] * height;
        view.frame = CGRectMake(x, y, width, height);
    };
    
    for (int i = 0; i < spriteCount; ++i) {
        UIImageView *spriteView = [[UIImageView alloc] init];
        
        spriteView.tag = i;
        spriteView.animationImages = @[img1, img2, img3];
        spriteView.animationDuration = 1.0;
        spriteView.alpha = 0.0f;
        [self.grid addSubview:spriteView];
        
        updateXYConstraints(spriteView, startBlock);
    }
    
    RACSequence *locationSeq = [stepsSequence scanWithStart:startBlock reduce:^id(RACTuple *running, RACTuple *next) {
        RACTupleUnpack(NSNumber *x1, NSNumber *y1) = running;
        RACTupleUnpack(NSNumber *x2, NSNumber *y2) = next;
        
        NSNumber *x = @(x1.integerValue + x2.integerValue);
        NSNumber *y = @(y1.integerValue + y2.integerValue);
        return RACTuplePack(x, y);
    }];
    
    RACSignal *locationSignal = locationSeq.signal;
    
    RACSignal *stepsSignal = [[locationSignal map:^id(id value) {
        return [[RACSignal return:value] delay:1];
    }] concat];

    RACSignal *moveSignal = [stepsSignal map:^id(RACTuple *location) {
        return RACTuplePack(location, @(SpriteStateRunning));
    }];
    
    RACSignal *startSignal = [RACSignal return:RACTuplePack(startBlock, @(SpriteStateAppear))];
    RACSignal *endSignal = [RACSignal return:RACTuplePack(nil, @(SpriteStateDisappear))];
    
    RACSignal *spriteSignal = [[startSignal concat:moveSignal] concat:endSignal];
    
    RACSignal *(^SpriteMaker)(NSNumber *tag) = ^RACSignal *(NSNumber *tag) {
        return [spriteSignal reduceEach:^id(RACTuple *location, NSNumber *state) {
            return RACTuplePack(tag, state, location);
        }];
    };
    
 
    RACSignal *autoBtnClickSignal = [self.autoRunBtn rac_signalForControlEvents:UIControlEventTouchUpInside];
    RACSignal *oneStepBtnClickSignal = [self.oneStepBtn rac_signalForControlEvents:UIControlEventTouchUpInside];
    RACSignal *autoSignal = [autoBtnClickSignal mapReplace:@(ControlStateAuto)];
    RACSignal *oneStepSignal = [oneStepBtnClickSignal mapReplace:@(ControlStateOneStep)];
    
    RACSignal *controlSignal = [RACSignal merge:@[autoSignal, oneStepSignal]];
    
    RACSignal *caseSignal = [controlSignal scanWithStart:@(ControlStateStop) reduce:^id(NSNumber *running, NSNumber *next) {
        // s a -> a;
        // a a -> s;
        // m a -> a;
        // s m -> m;
        // m m -> m;
        // a m -> m;
        // 特点:除了a a-> s,剩下都是 x y -> y
        if (next.integerValue == ControlStateAuto && running.integerValue == next.integerValue) {
            return @(ControlStateStop);
        }
        return next;
    }];
    
    RACSignal *timerSignal = [[RACSignal interval:1.5 onScheduler:[RACScheduler mainThreadScheduler]] startWith:nil];
    RACSignal *returnSignal = [RACSignal return:nil];
    RACSignal *emptySignal = [RACSignal empty];
    
    RACSignal *appearSignal = [RACSignal switch:caseSignal cases:@{
                                                                  @(ControlStateAuto) : timerSignal,
                                                                  @(ControlStateOneStep) : returnSignal
                                                                  }default:emptySignal];
    
    RACSignal *spriteIDSignal = [appearSignal scanWithStart:@-1 reduce:^id(NSNumber *running, id _) {
        NSInteger id = running.integerValue;
        ++id;
        if (id == spriteCount) {
            id = 0;
        }
        return @(id);
    }];
    
    RACSignal *spriteControlSignal = [[spriteIDSignal flattenMap:SpriteMaker] deliverOnMainThread];
    
    RACSignal *hotSpriteControlSignal = [spriteControlSignal replay];
    @weakify(self)
    [[[hotSpriteControlSignal filter:^BOOL(RACTuple *value) {
        NSNumber *state = value.second;
        return state.integerValue == SpriteStateAppear;
    }] reduceEach:^id(NSNumber *tag, NSNumber *state, RACTuple *location){
        return RACTuplePack(tag, location);
    }] subscribeNext:^(RACTuple *info) {
        RACTupleUnpack(NSNumber *tag, RACTuple *location) = info;
        @strongify(self)
        UIImageView *sprite = [self.grid viewWithTag:tag.integerValue];
        updateXYConstraints(sprite, location);
        [sprite startAnimating];
        [UIView animateWithDuration:1 animations:^{
            sprite.alpha = 1.0f;
        }];
    }];
    
    [[[hotSpriteControlSignal filter:^BOOL(RACTuple *value) {
        NSNumber *state = value.second;
        return state.integerValue == SpriteStateRunning;
    }] reduceEach:^id(NSNumber *tag, NSNumber *state, RACTuple *location){
        return RACTuplePack(tag, location);
    }] subscribeNext:^(RACTuple *info) {
        RACTupleUnpack(NSNumber *tag, RACTuple *location) = info;
        @strongify(self)
        UIImageView *sprite = [self.grid viewWithTag:tag.integerValue];
        [UIView animateWithDuration:1 animations:^{
            updateXYConstraints(sprite, location);
        }];
    }];
    
    [[[hotSpriteControlSignal filter:^BOOL(RACTuple *value) {
        NSNumber *state = value.second;
        return state.integerValue == SpriteStateDisappear;
    }] reduceEach:^id(NSNumber *tag, NSNumber *state, RACTuple *location){
        return RACTuplePack(tag, nil);
    }] subscribeNext:^(RACTuple *info) {
        NSNumber *tag = info.first;
        @strongify(self)
        UIImageView *sprite = [self.grid viewWithTag:tag.integerValue];
        [sprite stopAnimating];
        [UIView animateWithDuration:1 animations:^{
            sprite.alpha = 0.0f;
        }];
    }];
    
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
