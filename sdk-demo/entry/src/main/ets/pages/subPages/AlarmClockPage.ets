import { router } from '@kit.ArkUI';
import { VPBleSDK, AlarmClockItem, AlarmClockControl, AlarmClockRepeat } from '@veepoo/vpble-sdk';

@Entry
@Component
struct AlarmClockPage {
  @State alarms: AlarmClockItem[] = [];
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State progressText: string = '';
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  // 表单状态（repDays: 0=周一 … 6=周日）
  @State formTime: string = '08:00';
  @State formLabel: string = '';
  @State formEnabled: boolean = true;
  @State repDays: boolean[] = [false, false, false, false, false, false, false];
  @State editingId: number = -1; // -1 = 新增模式

  private readonly dayLabels: string[] = ['一', '二', '三', '四', '五', '六', '日'];

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
      const r = await VPBleSDK.getInstance().alarmClockService.readAll((progress: number) => {
        this.progressText = `${Math.round(progress)}%`;
      });
      if (r.success && r.data) {
        this.alarms = r.data;
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
    for (const a of this.alarms) {
      if (a.alarmClockId > max) {
        max = a.alarmClockId;
      }
    }
    const next = max + 1;
    return next > 255 ? 255 : next;
  }

  private buildRepeat(): AlarmClockRepeat {
    return {
      monday: this.repDays[0],
      tuesday: this.repDays[1],
      wednesday: this.repDays[2],
      thursday: this.repDays[3],
      friday: this.repDays[4],
      saturday: this.repDays[5],
      sunday: this.repDays[6],
    };
  }

  private resetForm(): void {
    this.formTime = '08:00';
    this.formLabel = '';
    this.formEnabled = true;
    this.repDays = [false, false, false, false, false, false, false];
    this.editingId = -1;
  }

  private startEdit(item: AlarmClockItem): void {
    this.editingId = item.alarmClockId;
    this.formTime = item.time;
    this.formLabel = item.labels;
    this.formEnabled = item.enabled;
    this.repDays = [
      item.repeat.monday, item.repeat.tuesday, item.repeat.wednesday,
      item.repeat.thursday, item.repeat.friday, item.repeat.saturday, item.repeat.sunday,
    ];
  }

  private toggleDay(i: number): void {
    const next = this.repDays.slice();
    next[i] = !next[i];
    this.repDays = next;
  }

  private pickTime(): void {
    const parts = this.formTime.split(':');
    const h = parts.length > 0 ? (parseInt(parts[0], 10) || 0) : 0;
    const m = parts.length > 1 ? (parseInt(parts[1], 10) || 0) : 0;
    const d = new Date();
    d.setHours(h, m, 0, 0);
    TimePickerDialog.show({
      selected: d,
      onAccept: (value: TimePickerResult) => {
        const hh = value.hour ?? 0;
        const mm = value.minute ?? 0;
        this.formTime = `${hh < 10 ? '0' + hh : hh}:${mm < 10 ? '0' + mm : mm}`;
      },
    });
  }

  private async submit(): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const isEdit = this.editingId >= 0;
      const id = isEdit ? this.editingId : this.nextId();
      const item: AlarmClockItem = {
        alarmClockId: id,
        enabled: this.formEnabled,
        time: this.formTime,
        repeat: this.buildRepeat(),
        labels: this.formLabel.trim(),
      };
      const r = await VPBleSDK.getInstance().alarmClockService.set(
        item, isEdit ? AlarmClockControl.SET : AlarmClockControl.SET);
      if (r.success) {
        this.showToastMsg(isEdit ? `已修改 id=${id}` : `已添加 id=${id}`);
        this.resetForm();
        await this.refresh();
      } else {
        this.showToastMsg(`保存失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`保存异常：${(err as Error).message}`);
    } finally {
      this.isWriting = false;
    }
  }

  private async toggleEnabled(item: AlarmClockItem, on: boolean): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const updated: AlarmClockItem = {
        alarmClockId: item.alarmClockId,
        enabled: on,
        time: item.time,
        repeat: item.repeat,
        labels: item.labels,
      };
      const r = await VPBleSDK.getInstance().alarmClockService.set(updated, AlarmClockControl.SET);
      if (!r.success) {
        this.showToastMsg(`切换失败：${r.errorMessage ?? '未知'}`);
      }
      await this.refresh();
    } catch (err) {
      this.showToastMsg(`切换异常：${(err as Error).message}`);
      await this.refresh();
    } finally {
      this.isWriting = false;
    }
  }

  private async deleteAlarm(id: number): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().alarmClockService.delete(id);
      if (r.success) {
        this.showToastMsg(`已删除 id=${id}`);
        if (this.editingId === id) {
          this.resetForm();
        }
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

  // 重复周期 → 文案（每天/工作日/周末/仅一次/周一周三…）
  private repeatSummary(rep: AlarmClockRepeat): string {
    const days: boolean[] = [
      rep.monday, rep.tuesday, rep.wednesday, rep.thursday, rep.friday, rep.saturday, rep.sunday,
    ];
    const count = days.filter((d: boolean) => d).length;
    if (count === 0) {
      return '仅一次';
    }
    if (count === 7) {
      return '每天';
    }
    const weekday = days[0] && days[1] && days[2] && days[3] && days[4] && !days[5] && !days[6];
    if (weekday) {
      return '工作日';
    }
    const weekend = !days[0] && !days[1] && !days[2] && !days[3] && !days[4] && days[5] && days[6];
    if (weekend) {
      return '周末';
    }
    const parts: string[] = [];
    for (let i = 0; i < 7; i++) {
      if (days[i]) {
        parts.push(`周${this.dayLabels[i]}`);
      }
    }
    return parts.join(' ');
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
          Text('文字闹钟').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.isLoading ? (this.progressText ? `读取中 ${this.progressText}` : '读取中') : '刷新')
            .fontSize(14).fontColor(this.isLoading ? '#999999' : '#007DFF')
            .onClick(() => this.refresh())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        Scroll() {
          Column() {
            this.AlarmForm()
            if (this.alarms.length > 0) {
              this.AlarmList()
            } else {
              this.EmptyState()
            }
          }.width('100%').padding({ bottom: 24 })
        }
        .width('100%').layoutWeight(1).align(Alignment.Top)
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
  AlarmForm() {
    Column({ space: 12 }) {
      Row() {
        Text(this.editingId >= 0 ? '修改闹钟' : '新增闹钟')
          .fontSize(15).fontWeight(FontWeight.Medium).fontColor('#333333').layoutWeight(1)
        if (this.editingId >= 0) {
          Text('取消').fontSize(13).fontColor('#999999').onClick(() => this.resetForm())
        }
      }.width('100%')

      // 时间 + 启用开关
      Row() {
        Text(this.formTime).fontSize(28).fontWeight(FontWeight.Bold).fontColor('#007DFF')
          .onClick(() => this.pickTime())
        Blank().layoutWeight(1)
        Row() {
          Text('启用').fontSize(13).fontColor('#666666').margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: this.formEnabled })
            .selectedColor('#34C759')
            .onChange((on: boolean) => { this.formEnabled = on; })
        }
      }.width('100%').alignItems(VerticalAlign.Center)

      // 标签
      TextInput({ placeholder: '标签（可选，≤21 字节）', text: this.formLabel })
        .height(40).backgroundColor('#F5F5F5').borderRadius(6)
        .maxLength(21)
        .onChange((v: string) => { this.formLabel = v; })

      // 重复周期
      Row() {
        Text('重复').fontSize(13).fontColor('#666666').width(40)
        ForEach(this.dayLabels, (lbl: string, i: number) => {
          Text(lbl)
            .fontSize(13)
            .fontColor(this.repDays[i] ? Color.White : '#666666')
            .backgroundColor(this.repDays[i] ? '#007DFF' : '#F0F0F0')
            .borderRadius(12)
            .width(28).height(28)
            .textAlign(TextAlign.Center)
            .margin({ left: i === 0 ? 0 : 6 })
            .onClick(() => this.toggleDay(i))
        }, (lbl: string, i: number) => `${i}`)
      }.width('100%').alignItems(VerticalAlign.Center)

      Button(this.editingId >= 0 ? '保存修改' : '添加闹钟')
        .width('100%').height(40)
        .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF')
        .fontColor(Color.White).borderRadius(8)
        .enabled(!this.isWriting)
        .onClick(() => this.submit())
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White)
    .margin({ left: 16, right: 16, top: 12 })
    .borderRadius(8)
  }

  @Builder
  AlarmList() {
    Column({ space: 10 }) {
      ForEach(this.alarms, (item: AlarmClockItem) => {
        this.AlarmRow(item)
      }, (item: AlarmClockItem) => `alarm_${item.alarmClockId}`)
    }.width('100%').margin({ top: 12 })
  }

  @Builder
  AlarmRow(item: AlarmClockItem) {
    Column({ space: 8 }) {
      Row() {
        Column() {
          Text(item.time).fontSize(24).fontWeight(FontWeight.Bold)
            .fontColor(item.enabled ? '#333333' : '#BBBBBB')
          if (item.labels) {
            Text(item.labels).fontSize(12).fontColor('#999999').margin({ top: 2 })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: item.enabled })
          .selectedColor('#34C759')
          .enabled(!this.isWriting)
          .onChange((on: boolean) => this.toggleEnabled(item, on))
      }.width('100%').alignItems(VerticalAlign.Center)

      Row() {
        Text(this.repeatSummary(item.repeat)).fontSize(11).fontColor('#666666').layoutWeight(1)
        Button('编辑').fontSize(12).height(28)
          .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.startEdit(item))
        Blank().width(8)
        Button('删除').fontSize(12).height(28)
          .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.deleteAlarm(item.alarmClockId))
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White).borderRadius(8)
    .margin({ left: 16, right: 16 })
  }

  @Builder
  EmptyState() {
    Column() {
      Text(this.isLoading ? '正在读取闹钟...' : '暂无闹钟，请在上方添加')
        .fontSize(14).fontColor('#999999')
    }
    .width('100%').padding({ top: 64, bottom: 64 })
    .alignItems(HorizontalAlign.Center)
  }
}
