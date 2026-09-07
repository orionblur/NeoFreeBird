# Engagement Score (XES)

このフォークが追加する機能です。各ポストのアクション行の末尾に、
X の公開ランキング実装の重みで計算した推定エンゲージメントスコアを表示します。

- 出典: <https://github.com/xai-org/x-algorithm>（Apache-2.0）
- 参照コミット: `902a06fd616ed815f660e5546d16d492fa1ca825`（2026-09-04）
- 重みの定義: `home-mixer/params/param.rs`
- 合成の算術: `home-mixer/scorers/ranking_scorer.rs`

---

## 1. 定義

本家の式は一行です。

```
Final Score = Σ ( weight_i × P(action_i) )
```

`P(action_i)` は **Phoenix（Transformer）が閲覧者ごとに推論する行動確率**で、
端末側からは取得できません。そこで次のように近似します。

```
P(action_i) ≈ action_count_i / view_count
```

`view_count` はそのポストが表示された回数なので、`count / views` は
「無作為な閲覧者がその行動を取る確率」の経験的推定になります。
つまりこのスコアは **「平均的な閲覧者に対する期待価値」の近似**であって、
あなた個人へのパーソナライズ結果ではありません。

`offset_score`、著者多様性減衰、Out-of-Network 割引も本家の式のまま実装しています。

### やってはいけない読み方

`param.rs` L285-313 に X 自身のコメントがあります。

> the weights apply to the predicted probabilities rather than raw counts …
> it'd be incorrect to see that a report has 468 times higher weight than a like and
> conclude that "1 report cancels out 468 likes"

重みを生のカウントに掛けるのは誤りです。設定の「生カウント式を使う」は
この誤った式を比較用に出すもので、既定では使いません。

---

## 2. 要点 — 実装の構成

| ファイル | 役割 |
| --- | --- |
| `src/Core/NFBScoreMath.h` / `.m` | 重みとスコア計算。**純 C**（Foundation 非依存）なのでホスト上で単体テストできる |
| `src/EngagementScore/NFBEngagementScore.h` / `.m` | 内部モデルから件数を取り出す。セレクタ名は実行時に探索する |
| `src/EngagementScore/NFBScoreBadgeView.h` / `.m` | バッジ本体。タップで内訳をアラート表示 |
| `src/Hooks/EngagementScore.x` | `TTAStatusInlineActionsView` / `T1StatusInlineActionsView` の `layoutSubviews` に相乗り |

`NFBScoreMath.m` が `.c` ではなく `.m` なのは、Makefile の
`find src \( -name '*.x' -o -name '*.m' \)` に拾わせるためです。中身は純 C です。

### 件数の取り出し方（ここが一番の設計判断）

Twitter/X 内部クラスの count 系プロパティ名はバージョンごとに変わります。
名前をハードコードすると、そのビルドでだけ静かに 0 が出ます。そこで:

1. 指標ごとの候補セレクタを順に試す（`favoriteCount` / `likeCount` / …）
2. 全滅したら `class_copyPropertyList` を走査し、名前から推測する
3. 戻り値の型は `NSMethodSignature` で判定（`long long` / `NSInteger` / `NSNumber*` など）
4. 解決結果はクラス単位でキャッシュ
5. **どうしても取れない指標は 0 ではなく「不明」として項ごと除外する**

5 が重要です。0 と不明を混ぜると、取得に失敗した指標のぶんだけ
スコアが静かに過小評価されます。内訳では `—` と表示されます。

うまく取れないときは、設定 → デバッグ → 「スコア取得元をログに出す」を有効にすると、
どのプロパティから読んだか・`*count` で終わるプロパティ一覧が Console に出ます。

### バッジの置き方

アクション行（返信・リポスト・いいね・ブックマークの並び）の**末尾の余白**にだけ置きます。
既存のサブビューのフレームには一切触れず、余白が足りない画面では
レイアウトを壊すより出さないほうがよいので黙って隠します。

---

## 3. 設定

設定 → ツイート

| 項目 | 既定 | 内容 |
| --- | --- | --- |
| エンゲージメントスコアを表示 | OFF | 機能全体のスイッチ |
| 生カウント式を使う | OFF | `Σ w × count`。ソースが誤りと注意している式 |
| 相互フォローとみなす | OFF | 返信の重み 5.0 → 20.0（`reply_weight_for`） |
| 著者多様性減衰を適用 | OFF | `(1−0.25)·0.5^k + 0.25` |
| Out-of-Network 割引を適用 | OFF | ×0.75 |

設定 → デバッグ

| 項目 | 既定 | 内容 |
| --- | --- | --- |
| スコア取得元をログに出す | OFF | 解決されたプロパティ名を Console に出力 |

---

## 4. 制約（正直に）

- **パーソナライズは再現できません。** 本家の `P` は閲覧者の直近行動列を入力に推論されます。
- **26 項のうち観測できるのは 5 項だけです。** クリック・滞在時間・共有・
  ネガティブフィードバックは端末のモデルに載りません。特に
  `share_via_copy_link`（+20.0、正の最大）と `report`（−234.0、負の最大）が欠けます。
- **ブックマークは本家の重み付き和に項がありません。** Phoenix は `ClientTweetBookmark` を
  予測しますが、`RankingScorer` に `BookmarkWeight` は存在しないため既定の重みは 0 です。
- **表示数が読めないポストでは確率近似を計算しません。** バッジは「表示数なし」と出ます。
- **グレード（S/A/B/C/D/E）の閾値は経験的です。** 信頼できるのは
  同一セッション内での相対順位（内訳の「上位 N%」）の方です。
- **セレクタ探索は万能ではありません。** モデルが件数を持たない画面では素直に「不明」になります。
- 表示数（`viewCount`）が端末モデルに存在しないビルドでは、確率近似が常に計算不能になります。
  その場合は生カウント式モードを使ってください。

---

## 5. 検証

演算部は純 C なので、iOS デバイスなしで検証できます。

```bash
clang -std=c11 -Isrc/Core -x c tests/nfb_score_test.c src/Core/NFBScoreMath.m -lm \
    -o /tmp/nfb_score_test && /tmp/nfb_score_test
```

35 件のアサーションが、`ranking_scorer.rs` の算術（`positive_sum` 43.34 /
`negative_sum` 367.22 / `total_sum` 410.56、`offset_score`、`diversity_multiplier`）と、
同じ重みで書いた Web 拡張版の JavaScript 実装の双方に一致することを確認しています。

Logos 構文の検証:

```bash
perl "$THEOS/bin/logos.pl" src/Hooks/EngagementScore.x > /dev/null
```

なお、フック部と UI 部のビルドには Theos と iOS SDK が必要です
（リポジトリ既定の手順そのままです）。

---

## 6. ライセンス

転記した重みの出典 `xai-org/x-algorithm` は Apache-2.0 です。
