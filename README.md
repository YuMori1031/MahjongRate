## プロジェクト名
### 雀レート（MahjongRate）

---

## 概要
麻雀の対局記録と成績を、メンバーで共有しながら管理できるiOSアプリです。

招待コードやQRコードで参加し、管理者の承認後にメンバーとして記録の閲覧・編集ができます。  
対局結果は月ごとに整理され、局ごとのスコア入力まで対応しています。

Firebaseをバックエンドとして使用し、複数ユーザーでリアルタイムにデータ共有が可能です。

[![appstore-logo](https://github.com/user-attachments/assets/9d4462eb-8b41-4b8d-a1b0-7ee947911ebf)](https://apps.apple.com/jp/app/%E9%9B%80%E3%83%AC%E3%83%BC%E3%83%88/id6757226979?itscg=30200&itsct=apps_box_link&mttnsubad=6757226979)

---

## 環境構築

### 1. リポジトリをclone
```bash
git clone https://github.com/YuMori1031/MahjongRate.git
cd MahjongRate
```

---

### 2. Firebase設定ファイルを用意
```text
MahjongRate/GoogleService-Info-Test.plist   （検証用）
MahjongRate/GoogleService-Info-Prod.plist   （本番用）
```

---

### 3. AdMobのアプリID / バナーIDを設定
```text
MahjongRate/Config/Debug.xcconfig   （検証用）
MahjongRate/Config/Release.xcconfig （本番用）
```

---

### 4. Firebase Functions をデプロイ
※ Functions のソースは `FirebaseFunctions/` 配下

```bash
cd FirebaseFunctions
firebase deploy --only functions
```

---

### 5. Xcodeでビルド
```bash
open MahjongRate.xcodeproj
```

---

## 開発情報

| 項目 | バージョン |
| ---- | ---- |
| Xcode | 16.2 |
| Swift | 6.0.3 |
| iOS | 17.0以上 |

---

## 使用ライブラリ

- **FirebaseAuth**  
  メール / パスワード認証

- **FirebaseFirestore**  
  対局記録・プレイヤー・結果データ保存

- **FirebaseStorage**  
  プロフィール画像保存

- **FirebaseFunctions**  
  アカウント削除・未認証ユーザー削除

- **GoogleMobileAds (AdMob)**  
  バナー広告表示

- **UserMessagingPlatform**  
  広告同意管理

- **AVFoundation**  
  QRコードスキャナー

- **PhotosUI / UniformTypeIdentifiers**  
  プロフィール画像選択

---

## Firebase構成

### Authentication
- Email / Password 認証のみ

---

### Firestore構造
```text
members/
  └ ユーザー基本情報

gameRecords/
  ├ players/
  ├ gameResults/
  │    └ gameRounds/
  │         └ scores/
  └ pendingMembers/
```

---

### Firebase Functions

リージョン：`asia-northeast2`

#### ✔ deleteMyAccount
ユーザー自身のアカウント削除  
削除対象：
- Firebase Auth
- Firestore関連データ
- Storage画像

#### ✔ deleteUnverifiedUsers
未認証ユーザー自動削除  

仕様：
- メール登録後1時間以内に認証されないユーザーを削除

---

## デザインパターン
- MVVM（View + ViewModel）
- SwiftUI + UIKit Bridge

---

## バージョン管理
GitHub

---

## デモ画面
<img width="300" src="https://github.com/user-attachments/assets/69df0dd1-77bd-416b-a7f8-bb0147407eae" />
<img width="300" src="https://github.com/user-attachments/assets/2857967e-1b2d-4f4f-951c-8adacb4995cd" />
<img width="300" src="https://github.com/user-attachments/assets/676e0590-5da8-4d20-9167-2ce3ae69f69c" />