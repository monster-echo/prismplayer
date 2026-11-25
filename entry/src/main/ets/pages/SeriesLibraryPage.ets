import { CatalogPage } from '../components/CatalogPage';

@Entry
@ComponentV2
struct SeriesLibraryPage {
  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  build() {
    Column() {
      CatalogPage({ kind: 'tv' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
