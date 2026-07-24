import { router, promptAction } from '@kit.ArkUI';
import { VPBleSDK, MsgSwitchConfig, MsgSwitchState, ConfigService, MessageResult } from '@veepoo/vpble-sdk';

/** 随机发信人姓名池 */
const DEMO_NAMES: string[] = ['张三', '李四', '王小明', 'Alice', 'Bob', '老板'];
/** 随机消息内容池 */
const DEMO_MESSAGES: string[] = [
  '在吗？晚点电话你', '今晚一起吃饭吗', '会议改到下午三点', '记得带上合同文件',
  '周末去爬山约不约', '收到请回复', 'Hello, are you free?', '快递到前台了',
];

interface SwitchItemState {
  label: string;
  supported: boolean;
  isOn: boolean;
}

const MSG_FIELDS: string[] = [
  'call', 'sms', 'wechat', 'qq', 'sina', 'facebook', 'x', 'flickr',
  'linkedIn', 'whatsapp', 'line', 'instagram', 'snapchat', 'skype',
  'gmail', 'dingTalk', 'wechatWork', 'other', 'tiktok', 'telegram',
  'connected2', 'kakaoTalk', 'jingYou', 'messenger', 'zalo', 'viber',
];

const LABELS: string[] = [
  '来电', '短信', '微信', 'QQ', '新浪微博', 'FaceBook', 'X(Twitter)', 'Flickr',
  'LinkedIn', 'WhatsApp', 'Line', 'Instagram', 'Snapchat', 'Skype',
  'Gmail', '钉钉', '企业微信', '其它', 'TikTok', 'Telegram',
  'Connected2', 'KakaoTalk', '警右', 'Messenger', 'Zalo', 'Viber',
];

function toItem(label: string, value?: number): SwitchItemState {
  const v = value ?? 0;
  return {
    label: label,
    supported: v !== MsgSwitchState.NOT_SUPPORTED,
    isOn: v === MsgSwitchState.ON,
  };
}

function applyConfigToItems(items: SwitchItemState[], config: MsgSwitchConfig): SwitchItemState[] {
  const newItems: SwitchItemState[] = [];
  for (let i = 0; i < items.length && i < MSG_FIELDS.length; i++) {
    const val = ConfigService.getMsgSwitchValue(config, MSG_FIELDS[i]);
    newItems.push(toItem(items[i].label, val));
  }
  return newItems;
}

@Entry
@Component
struct MsgPage {
  @State switchItems: SwitchItemState[] = [];
  @State isWriting: boolean = false;
  private _writing: boolean = false;

  aboutToAppear(): void {
    const dev = VPBleSDK.getInstance().getConnectedDevice();
    const c = dev?.msgSwitchConfig;
    this.switchItems = LABELS.map((label, i) => {
      const val = c ? ConfigService.getMsgSwitchValue(c, MSG_FIELDS[i]) : undefined;
      return toItem(label, val);
    });

    VPBleSDK.getInstance().configService.onMsgSwitchChange((config: MsgSwitchConfig) => {
      if (this._writing) {
        return;
      }
      this.switchItems = applyConfigToItems(this.switchItems, config);
      if (dev) {
        dev.msgSwitchConfig = config;
      }
    });
  }

  aboutToDisappear(): void {
    VPBleSDK.getInstance().configService.offMsgSwitchChange();
  }

  private async setAll(isOn: boolean): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const previousItems = this.switchItems;
    const newItems: SwitchItemState[] = [];
    for (let i = 0; i < this.switchItems.length; i++) {
      const item = this.switchItems[i];
      newItems.push({
        label: item.label,
        supported: item.supported,
        isOn: item.supported ? isOn : false,
      });
    }
    this.switchItems = newItems;

    this._writing = true;
    this.isWriting = true;
    try {
      const result = await VPBleSDK.getInstance().configService.setAllMsgSwitch(isOn);
      if (!result.success) {
        console.error('[VPBleSDK.MsgPage]', `setAllMsgSwitch failed: ${result.errorMessage}`);
        this.switchItems = previousItems;
      }
    } catch (err) {
      console.error('[VPBleSDK.MsgPage]', `setAllMsgSwitch exception: ${JSON.stringify(err)}`);
      this.switchItems = previousItems;
    } finally {
      this._writing = false;
      this.isWriting = false;
    }
  }

  async updateItem(index: number, isOn: boolean): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const previousItems = this.switchItems;
    const newItems: SwitchItemState[] = [];
    for (let i = 0; i < this.switchItems.length; i++) {
      const item = this.switchItems[i];
      if (i === index) {
        newItems.push({ label: item.label, supported: item.supported, isOn: isOn });
      } else {
        newItems.push(item);
      }
    }
    this.switchItems = newItems;

    this._writing = true;
    this.isWriting = true;
    try {
      const result = await VPBleSDK.getInstance().configService
        .setSingleMsgSwitch(MSG_FIELDS[index], isOn);
      if (!result.success) {
        console.error('[VPBleSDK.MsgPage]', `setSingleMsgSwitch failed: ${result.errorMessage}`);
        this.switchItems = previousItems;
      }
    } catch (err) {
      console.error('[VPBleSDK.MsgPage]', `setSingleMsgSwitch exception: ${JSON.stringify(err)}`);
      this.switchItems = previousItems;
    } finally {
      this._writing = false;
      this.isWriting = false;
    }
  }

  private _pick(arr: string[]): string {
    return arr[Math.floor(Math.random() * arr.length)];
  }

  private _randomPhone(): string {
    let s = '1';
    for (let i = 0; i < 10; i++) {
      s += Math.floor(Math.random() * 10).toString();
    }
    return s;
  }

  private _toast(msg: string): void {
    promptAction.showToast({ message: msg, duration: 2000 });
  }

  /**
   * 点击某行 → 构造随机内容 → 调用对应消息发送接口，形成测试闭环
   *
   * 行 index 即通知协议的来源字节：0=来电、1=短信、≥2=各 App 协议码。
   */
  async sendDemo(index: number, label: string): Promise<void> {
    const item = this.switchItems[index];
    if (!item || !item.supported) {
      this._toast(`「${label}」设备未支持，无法推送`);
      return;
    }

    const svc = VPBleSDK.getInstance().messageService;
    const inContacts = Math.random() < 0.5;
    const name = this._pick(DEMO_NAMES);
    const phone = this._randomPhone();

    try {
      let result: MessageResult;
      let desc: string;
      if (index === 0) {
        // 来电
        result = await svc.sendCallNotify({ inContacts, name, phone });
        desc = `来电 ${inContacts ? name : phone}`;
      } else if (index === 1) {
        // 短信
        const message = this._pick(DEMO_MESSAGES);
        result = await svc.sendSmsNotify({ inContacts, name, phone, message });
        desc = `短信[${inContacts ? name : phone}] ${message}`;
      } else {
        // App 通知
        const message = this._pick(DEMO_MESSAGES);
        result = await svc.sendAppNotify(index, `${label}：${message}`);
        desc = `${label} ${message}`;
      }

      if (result.success) {
        this._toast(`已推送 ${desc}`);
      } else {
        this._toast(`推送失败：${result.errorMessage ?? '未知错误'}`);
      }
    } catch (err) {
      console.error('[VPBleSDK.MsgPage]', `sendDemo exception: ${JSON.stringify(err)}`);
      this._toast('推送异常，请确认设备已连接');
    }
  }

  build() {
    Column() {
      Row() {
        Text('<')
          .fontSize(20)
          .fontColor('#333333')
          .onClick(() => router.back())
          .padding({ right: 12 })
        Text('消息通知')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .layoutWeight(1)
        Text('全开')
          .fontSize(14)
          .fontColor('#007DFF')
          .onClick(() => this.setAll(true))
          .margin({ right: 16 })
        Text('全关')
          .fontSize(14)
          .fontColor('#007DFF')
          .onClick(() => this.setAll(false))
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .alignItems(VerticalAlign.Center)

      Text('点击名称：发送一条随机内容到设备；右侧开关：设置通知推送权限')
        .fontSize(12)
        .fontColor('#999999')
        .width('100%')
        .padding({ left: 16, right: 16, bottom: 8 })

      List({ space: 0 }) {
        ForEach(this.switchItems, (item: SwitchItemState, index?: number) => {
          ListItem() {
            Row() {
              Text(item.label)
                .fontSize(16)
                .fontColor(item.supported ? '#333333' : '#999999')
                .layoutWeight(1)
                .onClick(() => {
                  if (index !== undefined) {
                    this.sendDemo(index, item.label);
                  }
                })
              Toggle({ type: ToggleType.Switch, isOn: item.isOn })
                .selectedColor('#007DFF')
                .enabled(item.supported && !this.isWriting)
                .onChange((isOn: boolean) => {
                  if (index !== undefined) {
                    this.updateItem(index, isOn);
                  }
                })
            }
            .width('100%')
            .height(56)
            .padding({ left: 16, right: 16 })
            .alignItems(VerticalAlign.Center)
            .opacity(item.supported ? 1 : 0.4)
          }
        }, (item: SwitchItemState) => `${item.label}_${item.isOn}`)
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor(Color.White)
      .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#F5F5F5')
  }
}
