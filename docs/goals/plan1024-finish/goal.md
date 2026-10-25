# 2026-10-24 計画の残りを最後まで

## Objective

research/plan-2026-10-24.md の残りのパッケージ（C rubric v5 #97、N 規則 9a、E2 planted の記録、G 見捨てたスライスの印、K 記録の固め）をすべて PR にしてマージし、Issue の整理を済ませる。まとめ役が確かめて進め、ユーザーには承認の要る変更のときだけ聞く。

## Original Request

計画の残りを最後まで自動で終わらせる。ユーザーにいちいち確認を取らず、まとめ役が確かめて進める（マージの設定もまとめ役が行う）。止めて聞くのは、承認されていない永続データの形・rubric の意味・公開の挙動の変更が要るときだけ。

## Intake Summary

- Input shape: `existing_plan`
- Audience: 篠田さん（vetdd の利用者）
- Authority: `approved`（2026-10-24 の 7 つの決定、2026-10-25 の step 8 の受け入れ、マージの設定はまとめ役に任された）
- Proof type: `artifact`（マージ済みの PR、閉じた Issue、入れ直した ~/.claude/skills/vetdd）
- Completion proof: 5 パッケージの PR がマージ済み、各 PR で必須チェック緑・未解決スレッド 0・bash 5 と bash 3.2 の全テスト緑、マージごとに片付けと install.sh、#33・#18・#3・#1 の整理済み
- Likely misfire: PR は出たが未解決スレッドや自動マージの取り消しで止まったまま「完了」と言う。マージ前の古い HEAD のテスト結果で済ませる
- Blind spots considered: 作業担当の自動マージが許可の判定で止められる（まとめ役が設定する）、遅れて届く bot スレッド、main が進むたびの載せ直し
- Existing plan facts: worker-brief.md の手順、同時に 3 本まで、check-evidence.sh を触るものは B → I → N → G → K と E2 の順で直列

## Goal Kind

`existing_plan`

## Current Tranche

残り 5 パッケージのマージと Issue の整理まで。

## Non-Negotiable Constraints

- 承認済みの形（E2 の planted、G の abandoned、K の (a)(b)(c)）以外の永続データの形を変えない
- rubric の意味を変える変更は #97 の範囲（受け入れ済み）だけ
- 力ずくの push・リポジトリ設定の変更・main への直接 push をしない

## Stop Rule

最終 audit が「full original outcome 完了」を証明したときのみ停止。

## Canonical Board

`docs/goals/plan1024-finish/state.yaml`

## Run Command

```text
/goaladv run plan1024-finish
```
