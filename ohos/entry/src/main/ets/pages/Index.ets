import common from '@ohos.app.ability.common';
import { FlutterPage } from '@ohos/flutter_ohos'
import { MovingPhotoSave } from '../plugins/MovingPhotoSave';

let storage = LocalStorage.getShared()
const EVENT_BACK_PRESS = 'EVENT_BACK_PRESS'

@Entry(storage)
@Component
struct Index {
  private context = getContext(this) as common.UIAbilityContext
  @LocalStorageLink('viewId') viewId: string = "";
  @StorageLink('movingPhotoSaveVisible') movingPhotoSaveVisible: boolean = false;
  @StorageLink('movingPhotoSaving') movingPhotoSaving: boolean = false;
  @StorageLink('movingPhotoPreview') movingPhotoPreview: string = '';

  // 保存动态照片的确认层：SaveButton 是系统的安全控件，点击后才有写入图库的临时授权
  @Builder
  movingPhotoDialog() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('#80000000')
      Column({ space: 16 }) {
        Text('保存动态照片').fontSize(20).fontWeight(FontWeight.Medium)
        Image(this.movingPhotoPreview)
          .height(180)
          .width('100%')
          .objectFit(ImageFit.Contain)
        if (this.movingPhotoSaving) {
          LoadingProgress().width(40).height(40)
          Text('正在保存到图库…').fontSize(14)
        } else {
          SaveButton({
            icon: SaveIconStyle.FULL_FILLED,
            text: SaveDescription.SAVE_TO_GALLERY,
            buttonType: ButtonType.Capsule
          })
            .onClick((_event: ClickEvent, result: SaveButtonOnClickResult) => {
              if (result === SaveButtonOnClickResult.SUCCESS) {
                MovingPhotoSave.save(this.context);
              } else {
                MovingPhotoSave.denied();
              }
            })
          Button('取消')
            .buttonStyle(ButtonStyleMode.TEXTUAL)
            .onClick(() => MovingPhotoSave.cancel())
        }
      }
      .width('90%')
      .constraintSize({ maxWidth: 420 })
      .padding(24)
      .borderRadius(20)
      .backgroundColor($r('sys.color.ohos_id_color_dialog_bg'))
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Default)
  }

  build() {
    Stack() {
      FlutterPage({ viewId: this.viewId })
      if (this.movingPhotoSaveVisible) {
        this.movingPhotoDialog()
      }
    }
  }

  onBackPress(): boolean {
    if (this.movingPhotoSaveVisible) {
      MovingPhotoSave.cancel();
      return true;
    }
    this.context.eventHub.emit(EVENT_BACK_PRESS)
    return true
  }
}
