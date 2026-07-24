import { router } from '@kit.ArkUI';
import { VPBleSDK, WeatherUnit, WeatherInfo, WeatherForecast, WeatherHourlyItem, WeatherDailyItem } from '@veepoo/vpble-sdk';

interface LogLine {
  time: string;
  msg: string;
}

@Entry
@Component
struct WeatherPage {
  @State busy: boolean = false;
  @State weatherEnabled: boolean = false;
  @State unit: number = WeatherUnit.CELSIUS;
  @State logLines: LogLine[] = [];

  aboutToAppear(): void {
    this.readInfo();
  }

  private addLog(msg: string): void {
    const time = new Date().toLocaleTimeString();
    this.logLines.push({ time, msg });
    if (this.logLines.length > 30) {
      this.logLines.shift();
    }
  }

  private async readInfo(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const r = await VPBleSDK.getInstance().weatherService.getInfo();
    if (r.success && r.data) {
      this.weatherEnabled = r.data.enabled;
      this.unit = r.data.unit;
      this.addLog(`读取：${r.data.enabled ? '开' : '关'}，单位=${r.data.unit === WeatherUnit.CELSIUS ? '℃' : '℉'}`);
    } else {
      this.addLog(`读取失败：${r.errorMessage ?? '未知'}`);
    }
    this.busy = false;
  }

  private async toggleEnabled(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const target: WeatherInfo = {
      enabled: !this.weatherEnabled,
      unit: this.unit,
    };
    const r = await VPBleSDK.getInstance().weatherService.setInfo(target);
    if (r.success) {
      this.weatherEnabled = target.enabled;
      this.addLog(`已${target.enabled ? '开启' : '关闭'}天气推送`);
    } else {
      this.addLog(`设置失败：${r.errorMessage ?? '未知'}`);
    }
    this.busy = false;
  }

  private async pushForecast(): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    const now = new Date();
    const today = `${now.getFullYear()}-${(now.getMonth() + 1).toString().padStart(2, '0')}-${now.getDate().toString().padStart(2, '0')}`;
    const nowHHmm = `${today}-${now.getHours().toString().padStart(2, '0')}-${now.getMinutes().toString().padStart(2, '0')}`;

    const hourly: WeatherHourlyItem[] = [];
    for (let h = 0; h < 24; h++) {
      hourly.push({
        dateTime: `${today}-${h.toString().padStart(2, '0')}-00`,
        weatherStatus: h < 6 ? 1 : (h < 18 ? 0 : 2),
        fahrenheit: 60 + Math.floor(Math.random() * 20),
      });
    }

    const daily: WeatherDailyItem[] = [];
    for (let d = 0; d < 3; d++) {
      const dt = new Date(now.getTime() + d * 24 * 3600 * 1000);
      const dateStr = `${dt.getFullYear()}-${(dt.getMonth() + 1).toString().padStart(2, '0')}-${dt.getDate().toString().padStart(2, '0')}`;
      daily.push({
        dateTime: dateStr,
        weatherByDay: 0,
        weatherByNight: 2,
        maxFahrenheit: 80,
        minFahrenheit: 55,
        ultravioletLight: 5,
      });
    }

    const forecast: WeatherForecast = {
      cityName: 'Shenzhen',
      dateTime: nowHHmm,
      todayData: hourly,
      everyDayData: daily,
    };
    const r = await VPBleSDK.getInstance().weatherService.setForecast(forecast);
    this.addLog(`推送预报：${r.success ? 'OK' : (r.errorMessage ?? 'FAIL')}（${hourly.length}h × ${daily.length}d）`);
    this.busy = false;
  }

  build() {
    Column() {
      Row() {
        Text('<').fontSize(20).fontColor('#333333')
          .onClick(() => router.back()).padding({ right: 12 })
        Text('天气').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333')
      }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

      Row() {
        Text('推送开关').fontSize(14).fontColor('#333333').layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.weatherEnabled })
          .selectedColor('#007DFF')
          .enabled(!this.busy).opacity(this.busy ? 0.4 : 1)
          .onChange(() => this.toggleEnabled())
      }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 16 })
      .backgroundColor(Color.White)

      Row({ space: 12 }) {
        Button('读取配置').width('45%').height(40)
          .backgroundColor('#8E8E93').fontColor(Color.White).borderRadius(8)
          .enabled(!this.busy).opacity(this.busy ? 0.4 : 1)
          .onClick(() => this.readInfo())
        Button('推送今日预报').width('45%').height(40)
          .backgroundColor('#007DFF').fontColor(Color.White).borderRadius(8)
          .enabled(!this.busy).opacity(this.busy ? 0.4 : 1)
          .onClick(() => this.pushForecast())
      }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 16 })

      Scroll() {
        Column() {
          ForEach(this.logLines, (line: LogLine, index: number) => {
            Text(`[${line.time}] ${line.msg}`)
              .fontSize(11).fontColor('#666666').fontFamily('monospace')
              .width('100%').padding({ top: 2, bottom: 2 })
          }, (line: LogLine, index: number) => `${index}_${line.time}`)
        }.width('100%')
      }.width('100%').layoutWeight(1).padding(8).margin({ left: 12, right: 12, top: 12, bottom: 12 })
      .backgroundColor(Color.White).borderRadius(8)
    }.width('100%').height('100%').backgroundColor('#F5F5F5')
  }
}
