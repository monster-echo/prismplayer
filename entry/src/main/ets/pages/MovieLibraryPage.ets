import { CatalogPage } from '../components/CatalogPage';

@Entry
@ComponentV2
struct MovieLibraryPage {
  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  build() {
    Column() {
      CatalogPage({ kind: 'movie' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
