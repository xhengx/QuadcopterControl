//
//  ViewController.m
//  四轴遥控
//
//  Created by honey on 16/2/22.
//  Copyright © 2016年 honey. All rights reserved.
//
#import <math.h>

#import "ViewController.h"
#import "AsyncSocket.h"
#import "AsyncUdpSocket.h"

#import "JSAnalogueStick.h"
#import "JSButton.h"

//区间映射函数
double mapx(double x, double in_min, double in_max, double out_min, double out_max)
{
    return (x - in_min) * (out_max - out_min) / (in_max - in_min) + out_min;
}

//油门曲线设置
//(x - 90)^3 / 10^4 + 100
//#define v(x) ceil(pow((x - 90), 3) / pow(10, 4)) + 73
//#define v(x) ceil(pow((x - 265), 3) / pow(10, 5) + 100)
#define v(x) ceil(pow((x - 100), 3) / pow(10, 4) + 100)

#define mapRegion(value) mapx(value, -1, 1, 144, 44)


#define kServerIp  @"192.168.4.1"
#define kPort      1002

//0 1 2 3 4 5 6 7 8 9 0 a b c d e f

typedef enum : NSUInteger {
    AIL    = 0xa1,
    ELE    = 0xb2,
    RUD    = 0xc3,
    THR    = 0xd4,
    
    Unlock = 0xf0,
    Lock   = 0xff

} Direction;

typedef struct  {
    UInt8 command;
    UInt8 value;
}CMD;


@interface ViewController () <AsyncUdpSocketDelegate, JSAnalogueStickDelegate, JSButtonDelegate>
{
    AsyncUdpSocket      *udp;
    
    BOOL                disconnectByUser; //是否人为断开,不是重新连接
    UInt8               lastTHRValue;   //上一次的油门数据
    UInt8               lastAIL;        //上一次的前后数据
    UInt8               lastELE;        //上一次的左右数据
    UInt8               lastRUD;        //上一次的转圈数据
}

@property (weak, nonatomic) IBOutlet UILabel *messageLabel;
@property (weak, nonatomic) IBOutlet UILabel *rudLabel;
@property (weak, nonatomic) IBOutlet UILabel *ailAndEleLabel;

@property (weak, nonatomic) IBOutlet JSAnalogueStick *aleAndele;

@property (weak, nonatomic) IBOutlet JSAnalogueStick *rud;
@property (weak, nonatomic) IBOutlet JSButton *start;

@property (weak, nonatomic) IBOutlet JSButton *unlock;
@property (weak, nonatomic) IBOutlet JSButton *lock;
@property (weak, nonatomic) IBOutlet UISlider *thrSlider;

@property (weak, nonatomic) IBOutlet UIView *led;
@property (strong, nonatomic) NSTimer *ledTimer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
   
    [self setupUI];
}



- (void)setupUI
{
    [[self.unlock titleLabel] setText:@"解锁"];
    [self.unlock setBackgroundImage:[UIImage imageNamed:@"button"]];
    [self.unlock setBackgroundImagePressed:[UIImage imageNamed:@"button-pressed"]];
    
    [[self.lock titleLabel] setText:@"锁定"];
    [self.lock setBackgroundImage:[UIImage imageNamed:@"button"]];
    [self.lock setBackgroundImagePressed:[UIImage imageNamed:@"button-pressed"]];
    
    [[self.start titleLabel] setText:@"启动"];
    [self.start setBackgroundImage:[UIImage imageNamed:@"button"]];
    [self.start setBackgroundImagePressed:[UIImage imageNamed:@"button-pressed"]];

}

- (void)connectUDP
{
    udp = [[AsyncUdpSocket alloc] init];
    
    udp.delegate = self;
    
    [[self.start titleLabel] setText:@"关闭"];
}


#pragma mark - 油门
-(IBAction)sliderValueChanged:(UISlider *)sender
{
    CGFloat value = sender.value;
    
    
    UInt8 currentValue = (UInt8)value; //47 ~ 150
    
    if (currentValue != lastTHRValue)
    {
        
        
        UInt8 y = v(value); //油门曲线的转换
        
        [self sendCMD:THR value:y];
        
        NSString *thrString = [[NSString alloc] initWithFormat:@"油门:%d", y];
        

        self.messageLabel.text = thrString;
        
        lastTHRValue = currentValue;
    }
}

#pragma mark - 摇杆
- (void)buttonPressed:(JSButton *)button
{
    if (button == self.start) //启动
    {
        if (udp == nil)
        {
            [self connectUDP];
        }
        else
        {
            [[self.start titleLabel] setText:@"启动"];
            [udp close];
            udp = nil;
        }
        
    }
    else if (button == self.unlock)//解锁
    {
        [self sendCMD:Unlock value:0];

        self.led.backgroundColor = [UIColor greenColor];
        
        self.thrSlider.enabled = YES;
        
    }
    else if (button == self.lock)  //锁定
    {
        [self sendCMD:Lock value:0];
        self.led.backgroundColor = [UIColor redColor];
        self.thrSlider.enabled = NO;
    }
    
    self.thrSlider.value = self.thrSlider.minimumValue;

}

- (void)buttonReleased:(JSButton *)button
{
    
}

- (void)analogueStickDidChangeValue:(JSAnalogueStick *)analogueStick
{
    
    if (analogueStick == self.aleAndele)
    {
        //左右为方向,上下为前进后退
        UInt8 eleValue = mapRegion(analogueStick.xValue);
        UInt8 ailValue = mapRegion(analogueStick.yValue);

        
        if (eleValue != lastELE)
        {
            [self sendCMD:ELE value:eleValue];
            lastELE = eleValue;
        }
        
        if (ailValue != lastAIL)
        {
            [self sendCMD:AIL value:ailValue];
            lastAIL = ailValue;
        }
        NSMutableString *s = [[NSMutableString alloc] initWithFormat:@"前后:%d,左右:%d", lastAIL, eleValue];
        self.ailAndEleLabel.text = s;

    }
    else if (analogueStick == self.rud)
    {
        //转圈圈
        UInt8 rudValue = mapRegion(self.rud.xValue);

        if (lastRUD != rudValue)
        {
            [self sendCMD:RUD value:rudValue];
            lastRUD = rudValue;
        }
        NSMutableString *s = [[NSMutableString alloc] initWithFormat:@"旋转:%d", rudValue];
        self.rudLabel.text = s;
    }
 //   [NSThread sleepForTimeInterval:1 / 100.0];
}


#pragma mark - 数据发送
- (void)sendCMD:(UInt8)command value:(UInt8)value {
    
    CMD c;
    c.command = command;
    c.value = value;
    
    NSLog(@"%d", c.command);
    
    NSData *data = [NSData dataWithBytes:&c length:sizeof(CMD)];
    
    [udp sendData:data toHost:kServerIp port:kPort withTimeout:-1 tag:command];

}

- (void)onUdpSocket:(AsyncUdpSocket *)sock didSendDataWithTag:(long)tag
{
    
}





@end
