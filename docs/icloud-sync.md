# 登録ページのiCloud同期

同じApple AccountでiCloudを利用する端末間で、登録URL・並び順・Open In-App・Xの下部メニュー設定を同期します。各端末にこのバージョンのアプリが必要です。設定画面の「完了」で変更を保存してください。ページ内のログイン状態や閲覧履歴は同期対象ではありません。

端末内の保存を残したまま、NSUbiquitousKeyValueStoreに一覧を保存します。オフラインの変更も端末に保存されます。同期は即時ではなく、iCloudの処理タイミングによって反映が遅れます。

- 初回起動時に既存の登録ページを移行します。空の新規端末から既存のクラウド一覧を消すことはありません。
- 一覧全体を1つの値として保存します。同時編集は保存日時が新しい一覧を採用し、同時刻の場合はリビジョンIDで決定します。端末の時計は自動設定を推奨します。
- 編集していない設定画面は受信内容を反映します。編集中の場合は入力を維持し、その後保存するとその一覧が優先されます。
- 全件削除も同期します。古い保存形式の一覧が復活しないようにしています。
- Apple Account変更の通知を受けた場合、以前の一覧は端末内に保持しますが、新アカウントへ自動転送しません。以後、利用者が編集・保存した一覧は新アカウントへ同期します。

## 開発・検証

アプリのDebug/Releaseの両方に `goaround/goaround.entitlements` を設定しています。署名時のiCloud Key-value storage識別子は `$(TeamIdentifierPrefix)$(CFBundleIdentifier)` です。

単体テストはメモリ上のクラウドストアを使い、端末間の保存・受信、並び替え、表示設定、削除、初回移行、古い更新、破損データ、アカウント変更を検証します。実際のAppleサーバー通信は単体テストの対象外です。

実機での同期確認手順:

1. 同じApple AccountでiCloudを使用している2台にビルドをインストールして起動する。
2. 一方の設定でURL・並び順・表示設定を変更して「完了」を押す。
3. もう一方を前面に戻して、一覧の反映を確認する。iCloudの配信を待つ必要がある。
4. 逆方向の変更、削除、オフラインで保存した後の再接続も確認する。

Appleの仕様: [synchronize()](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/synchronize())、[外部変更通知](https://developer.apple.com/documentation/foundation/nsubiquitouskeyvaluestore/didchangeexternallynotification)。
