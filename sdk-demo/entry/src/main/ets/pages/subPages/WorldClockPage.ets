import { router } from '@kit.ArkUI';
import { VPBleSDK, WorldClockItem } from '@veepoo/vpble-sdk';

@Entry
@Component
struct WorldClockPage {
  @State clocks: WorldClockItem[] = [];
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State progressText: string = '';
  @State newCity: string = '';
  @State newTz: number = 8; // UTC 偏移小时，默认 +8
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.refresh();
  }

  aboutToDisappear(): void {
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
  }

  private async refresh(): Promise<void> {
    if (this.isLoading) {
      return;
    }
    this.isLoading = true;
    this.progressText = '';
    try {
      const r = await VPBleSDK.getInstance().worldClockService.list((progress: number) => {
        this.progressText = `${Math.round(progress)}%`;
      });
      if (r.success && r.data) {
        this.clocks = r.data;
      } else {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isLoading = false;
      this.progressText = '';
    }
  }

  // 新增 id = 当前最大 id + 1（id 编码只取低 8 位，上限 255）
  private nextId(): number {
    let max = 0;
    for (const c of this.clocks) {
      if (c.clockId > max) {
        max = c.clockId;
      }
    }
    const next = max + 1;
    return next > 255 ? 255 : next;
  }

  private changeTz(delta: number): void {
    const t = this.newTz + delta;
    if (t < -12 || t > 14) {
      return;
    }
    this.newTz = t;
  }

  private tzLabel(tz: number): string {
    if (tz === 0) {
      return 'UTC±0';
    }
    return tz > 0 ? `UTC+${tz}` : `UTC${tz}`;
  }

  private async addClock(): Promise<void> {
    const city = this.newCity.trim();
    if (!city) {
      this.showToastMsg('请输入城市名称');
      return;
    }
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const id = this.nextId();
      const r = await VPBleSDK.getInstance().worldClockService
        .add({ clockId: id, timeZone: this.newTz, city });
      if (r.success) {
        this.newCity = '';
        this.newTz = 8;
        this.showToastMsg(`已添加 ${city}（id=${id}）`);
        await this.refresh();
      } else {
        this.showToastMsg(`添加失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`添加异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async deleteClock(id: number): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().worldClockService.delete(id);
      if (r.success) {
        this.showToastMsg(`已删除 id=${id}`);
        await this.refresh();
      } else {
        this.showToastMsg(`删除失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`删除异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  // delta = -1 上移，+1 下移；底层 swap 与相邻项两两交换
  private async move(index: number, delta: number): Promise<void> {
    if (this.isWriting) {
      return;
    }
    const target = index + delta;
    if (index < 0 || target < 0 || index >= this.clocks.length || target >= this.clocks.length) {
      return;
    }
    const fromId = this.clocks[index].clockId;
    const toId = this.clocks[target].clockId;
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().worldClockService.swap(fromId, toId);
      if (r.success) {
        await this.refresh();
      } else {
        this.showToastMsg(`移动失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`移动异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private showToastMsg(msg: string): void {
    this.toastMsg = msg;
    this.showToast = true;
    if (this.toastTimer !== -1) {
      clearTimeout(this.toastTimer);
    }
    this.toastTimer = setTimeout(() => { this.showToast = false; }, 2500);
  }

  build() {
    Stack() {
      Column() {
        // 标题栏
        Row() {
          Text('<').fontSize(20).fontColor('#333333')
            .onClick(() => router.back()).padding({ right: 12 })
          Text('世界时钟').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.isLoading ? (this.progressText ? `读取中 ${this.progressText}` : '读取中') : '刷新')
            .fontSize(14).fontColor(this.isLoading ? '#999999' : '#007DFF')
            .onClick(() => this.refresh())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        // 添加表单
        this.AddForm()

        if (this.clocks.length > 0) {
          List({ space: 0 }) {
            ForEach(this.clocks, (item: WorldClockItem, index?: number) => {
              ListItem() {
                this.ClockRow(item, index === undefined ? -1 : index)
              }
            }, (item: WorldClockItem) => `wc_${item.clockId}`)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor(Color.White)
          .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })
        } else {
          Column() {
            Text(this.isLoading ? '正在读取世界时钟...' : '暂无世界时钟，请在上方添加')
              .fontSize(14).fontColor('#999999')
          }
          .width('100%').layoutWeight(1)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
      }
      .width('100%').height('100%')

      if (this.showToast) {
        Text(this.toastMsg)
          .fontSize(14).fontColor(Color.White)
          .padding({ left: 20, right: 20, top: 10, bottom: 10 })
          .backgroundColor('rgba(0,0,0,0.7)').borderRadius(20).zIndex(1000)
      }
    }
    .width('100%').height('100%').backgroundColor('#F5F5F5')
  }

  @Builder
  AddForm() {
    Column({ space: 8 }) {
      TextInput({ placeholder: '城市名称', text: this.newCity })
        .height(40)
        .backgroundColor('#F5F5F5').borderRadius(6)
        .onChange((v: string) => { this.newCity = v; })

      Row() {
        Text('时区').fontSize(14).fontColor('#666666').margin({ right: 12 })
        Button('-').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.newTz > -12)
          .onClick(() => this.changeTz(-1))
        Text(this.tzLabel(this.newTz)).fontSize(15).fontColor('#007DFF')
          .margin({ left: 12, right: 12 })
        Button('+').width(36).height(32).fontSize(16)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(this.newTz < 14)
          .onClick(() => this.changeTz(1))
        Blank().layoutWeight(1)
        Button('添加').fontSize(14).height(36)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.addClock())
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White)
  }

  @Builder
  ClockRow(item: WorldClockItem, index: number) {
    Row() {
      Column() {
        Text(item.city).fontSize(15).fontColor('#333333')
        Text(this.tzLabel(item.timeZone)).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Button('↑').fontSize(14).width(36).height(32)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(index > 0 && !this.isWriting)
        .onClick(() => this.move(index, -1))
      Blank().width(6)
      Button('↓').fontSize(14).width(36).height(32)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(index < this.clocks.length - 1 && !this.isWriting)
        .onClick(() => this.move(index, 1))
      Blank().width(6)
      Button('删除').fontSize(12).height(32)
        .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
        .enabled(!this.isWriting)
        .onClick(() => this.deleteClock(item.clockId))
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }
}
