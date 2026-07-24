import { router } from '@kit.ArkUI';
import { VPBleSDK, ContactItem } from '@veepoo/vpble-sdk';

@Entry
@Component
struct ContactPage {
  @State contacts: ContactItem[] = [];
  @State isLoading: boolean = false;
  @State isWriting: boolean = false;
  @State newName: string = '';
  @State newPhone: string = '';
  @State newSos: boolean = false;
  @State sosTimes: number = 0;
  @State toastMsg: string = '';
  @State showToast: boolean = false;
  private toastTimer: number = -1;

  aboutToAppear(): void {
    this.refresh();
    this.loadSosTimes();
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
    try {
      const r = await VPBleSDK.getInstance().contactService.list();
      if (r.success && r.data) {
        this.contacts = r.data;
      } else {
        this.showToastMsg(`读取失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`读取异常：${(err as Error).message}`);
    } finally {
      this.isLoading = false;
    }
  }

  private async loadSosTimes(): Promise<void> {
    try {
      const r = await VPBleSDK.getInstance().contactService.getSosTimes();
      if (r.success && r.times !== undefined) {
        this.sosTimes = r.times;
      }
    } catch (_err) {
      // SOS 次数为可选项，读取失败忽略
    }
  }

  // 新增 id = 当前最大 id + 1（id 编码只取低 8 位，故上限 255）
  private nextId(): number {
    let max = 0;
    for (const c of this.contacts) {
      if (c.id > max) {
        max = c.id;
      }
    }
    const next = max + 1;
    return next > 255 ? 255 : next;
  }

  private async addContact(): Promise<void> {
    const name = this.newName.trim();
    const phone = this.newPhone.trim();
    if (!name || !phone) {
      this.showToastMsg('请输入姓名和号码');
      return;
    }
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const id = this.nextId();
      const r = await VPBleSDK.getInstance().contactService.save({ id, name, phone, sos: this.newSos });
      if (r.success) {
        this.newName = '';
        this.newPhone = '';
        this.newSos = false;
        this.showToastMsg(`已添加 ${name}（id=${id}）`);
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

  private async deleteContact(id: number): Promise<void> {
    if (this.isWriting) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().contactService.delete(id);
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
    if (index < 0 || target < 0 || index >= this.contacts.length || target >= this.contacts.length) {
      return;
    }
    const fromId = this.contacts[index].id;
    const toId = this.contacts[target].id;
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().contactService.swap(fromId, toId);
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

  private async changeSosTimes(delta: number): Promise<void> {
    const target = this.sosTimes + delta;
    if (target < 1 || target > 3 || this.isWriting || this.sosTimes <= 0) {
      return;
    }
    this.isWriting = true;
    try {
      const r = await VPBleSDK.getInstance().contactService.setSosTimes(target);
      if (r.success && r.times !== undefined) {
        this.sosTimes = r.times;
        this.showToastMsg(`SOS 呼叫次数设为 ${r.times}`);
      } else {
        this.showToastMsg(`设置失败：${r.errorMessage ?? '未知'}`);
      }
    } catch (err) {
      this.showToastMsg(`设置异常：${(err as Error).message}`);
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
          Text('联系人').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#333333').layoutWeight(1)
          Text(this.isLoading ? '读取中' : '刷新')
            .fontSize(14).fontColor(this.isLoading ? '#999999' : '#007DFF')
            .onClick(() => this.refresh())
        }.width('100%').height(56).padding({ left: 16, right: 16 }).alignItems(VerticalAlign.Center)

        // 添加表单
        this.AddForm()

        // 联系人列表
        List({ space: 0 }) {
          ForEach(this.contacts, (item: ContactItem, index?: number) => {
            ListItem() {
              this.ContactRow(item, index === undefined ? -1 : index)
            }
          }, (item: ContactItem) => `contact_${item.id}`)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor(Color.White)
        .divider({ strokeWidth: 0.5, color: '#E0E0E0', startMargin: 16, endMargin: 16 })

        // SOS 呼叫次数
        this.SosTimesBar()
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
      Row() {
        TextInput({ placeholder: '姓名', text: this.newName })
          .layoutWeight(1).height(40)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.newName = v; })
        Blank().width(8)
        TextInput({ placeholder: '号码', text: this.newPhone })
          .layoutWeight(2).height(40)
          .backgroundColor('#F5F5F5').borderRadius(6)
          .onChange((v: string) => { this.newPhone = v; })
      }.width('100%')

      Row() {
        Row() {
          Text('SOS').fontSize(14).fontColor('#666666').margin({ right: 8 })
          Toggle({ type: ToggleType.Switch, isOn: this.newSos })
            .selectedColor('#FF3B30')
            .onChange((on: boolean) => { this.newSos = on; })
        }.layoutWeight(1)
        Button('添加').fontSize(14).height(36)
          .backgroundColor(this.isWriting ? '#CCCCCC' : '#007DFF').fontColor(Color.White).borderRadius(6)
          .enabled(!this.isWriting)
          .onClick(() => this.addContact())
      }.width('100%').alignItems(VerticalAlign.Center)
    }
    .width('100%').padding(16)
    .backgroundColor(Color.White)
  }

  @Builder
  ContactRow(item: ContactItem, index: number) {
    Row() {
      Column() {
        Row() {
          Text(item.name).fontSize(15).fontColor('#333333')
          if (item.sos) {
            Text('SOS').fontSize(10).fontColor(Color.White)
              .backgroundColor('#FF3B30').borderRadius(3)
              .padding({ left: 4, right: 4, top: 1, bottom: 1 }).margin({ left: 6 })
          }
        }
        Text(item.phone).fontSize(12).fontColor('#999999').margin({ top: 2 })
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)

      Button('↑').fontSize(14).width(36).height(32)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(index > 0 && !this.isWriting)
        .onClick(() => this.move(index, -1))
      Blank().width(6)
      Button('↓').fontSize(14).width(36).height(32)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(index < this.contacts.length - 1 && !this.isWriting)
        .onClick(() => this.move(index, 1))
      Blank().width(6)
      Button('删除').fontSize(12).height(32)
        .backgroundColor('#E84026').fontColor(Color.White).borderRadius(6)
        .enabled(!this.isWriting)
        .onClick(() => this.deleteContact(item.id))
    }
    .width('100%').padding({ left: 16, right: 16, top: 10, bottom: 10 })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  SosTimesBar() {
    Row() {
      Text('SOS 呼叫次数').fontSize(14).fontColor('#333333').layoutWeight(1)
      Button('-').width(36).height(32).fontSize(16)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(this.sosTimes > 1 && !this.isWriting)
        .onClick(() => this.changeSosTimes(-1))
      Text(this.sosTimes > 0 ? `${this.sosTimes}` : '--').fontSize(16).fontColor('#333333')
        .margin({ left: 12, right: 12 })
      Button('+').width(36).height(32).fontSize(16)
        .backgroundColor('#EEEEEE').fontColor('#333333').borderRadius(6)
        .enabled(this.sosTimes > 0 && this.sosTimes < 3 && !this.isWriting)
        .onClick(() => this.changeSosTimes(1))
    }
    .width('100%').padding({ left: 16, right: 16, top: 12, bottom: 12 })
    .backgroundColor(Color.White)
  }
}
