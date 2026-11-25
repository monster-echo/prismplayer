import { CatalogPage } from '../components/CatalogPage';

@Entry
@ComponentV2
struct FavoritesPage {
  onBackPress(): boolean {
    this.getUIContext().getRouter().back();
    return true;
  }

  build() {
    Column() {
      CatalogPage({ kind: 'favorite' })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
