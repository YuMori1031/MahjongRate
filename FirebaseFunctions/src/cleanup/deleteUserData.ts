import {getAuth} from "firebase-admin/auth";
import {
  FieldValue,
  getFirestore,
  type DocumentData,
  type UpdateData,
} from "firebase-admin/firestore";
import * as logger from "firebase-functions/logger";
import {deleteByGsUrl} from "../utils/storageDelete";
import {deleteCollectionByPath} from "../utils/firestoreDelete";

/**
 * 退会（アカウント削除）時に「関連データも削除」する本体。
 *
 * 方針:
 * - 参加者が他にいる record は残す
 *   - 自分が作成者なら createdBy を引き継ぐ
 *   - 自分が作成者でなくても memberIDs から自分を抜く
 * - 参加者が自分だけの record は「全部削除」
 * - members/{uid} は削除
 * - プロフィール画像は members.iconPath / iconURL を見て Storage を削除
 * - 最後に Auth ユーザー自体を削除
 *
 * @param {string} uid Firebase Authentication の UID
 * @return {Promise<void>} 完了したら resolve
 */
export async function deleteUserDataAndAuth(uid: string): Promise<void> {
  const db = getFirestore();
  const auth = getAuth();

  // 1) members/{uid} を読み、プロフィール画像を消せるなら消す
  try {
    const mref = db.collection("members").doc(uid);
    const msnap = await mref.get();

    if (msnap.exists) {
      const data = msnap.data() as {
        iconPath?: string;
        iconURL?: string;
      };

      // 優先: iconPath（削除用）
      // 例: "gs://<bucket>/profileImages/xxx.jpg" または "profileImages/xxx.jpg"
      // ※ iconPath を「profileImages/xxx.jpg」の形式で保存する運用でもOK
      if (data.iconPath) {
        await deleteProfileImageByPathOrGsUrl(data.iconPath);
      } else if (data.iconURL) {
        // 互換: 以前の iconURL が gs:// の場合だけ削除できる
        if (data.iconURL.startsWith("gs://")) {
          await deleteByGsUrl(data.iconURL);
        } else {
          // downloadURL(https://...) からの削除はパースが必要で事故りやすいので
          // ここでは削除しない（iconPath 運用へ寄せる）
          logger.info("iconURL is not gs:// (skip delete)", {
            uid,
          });
        }
      }
    }
  } catch (e) {
    // 画像削除に失敗しても退会自体は続行したい
    logger.warn("Failed to delete profile image (continue)", {
      uid,
      error: String(e),
    });
  }

  // 2) gameRecords のうち「memberIDs に uid を含む」ものを探して処理
  const recordsSnap = await db
    .collection("gameRecords")
    .where("memberIDs", "array-contains", uid)
    .get();

  for (const doc of recordsSnap.docs) {
    const recordID = doc.id;
    const data = doc.data() as {
      createdBy?: string;
      memberIDs?: string[];
    };

    const memberIDs = data.memberIDs ?? [];
    const remaining = memberIDs.filter((x) => x !== uid);

    // 2-A) 他参加者がいない → record ツリーを丸ごと削除
    if (remaining.length === 0) {
      logger.info("Deleting entire record tree", {recordID, uid});

      // players サブコレクション削除
      await deleteCollectionByPath(db, `gameRecords/${recordID}/players`);

      // gameResults 以下を全部削除（rounds / scores も）
      const resultsSnap = await db
        .collection(`gameRecords/${recordID}/gameResults`)
        .get();

      for (const resDoc of resultsSnap.docs) {
        const resultID = resDoc.id;

        // rounds を取得
        const roundsSnap = await db
          .collection(
            `gameRecords/${recordID}/gameResults/${resultID}/gameRounds`,
          )
          .get();

        // rounds ごとに scores を消す → round を消す
        for (const rdoc of roundsSnap.docs) {
          const roundID = rdoc.id;

          await deleteCollectionByPath(
            db,
            `gameRecords/${recordID}/gameResults/${resultID}` +
              `/gameRounds/${roundID}/scores`,
          );

          await rdoc.ref.delete();
        }

        // gameResults 自体を削除
        await resDoc.ref.delete();
      }

      // 親 gameRecords/{recordID} を削除
      await doc.ref.delete();
      continue;
    }

    // 2-B) 他参加者がいる → memberIDs から uid を抜いて record は残す
    //      自分が作成者なら createdBy を引き継ぐ
    logger.info(
      "Updating record (remove member / transfer owner if needed)",
      {recordID, uid},
    );

    await db.runTransaction(async (tx) => {
      const ref = doc.ref;
      const latest = await tx.get(ref);
      if (!latest.exists) return;

      const latestData = latest.data() as {
        createdBy?: string;
        memberIDs?: string[];
      };

      const latestMembers = latestData.memberIDs ?? [];
      const latestRemaining = latestMembers.filter((x) => x !== uid);

      // 念のため：他参加者がいないなら transaction 内でも削除
      if (latestRemaining.length === 0) {
        tx.delete(ref);
        return;
      }

      // 注意:
      // FieldValue.arrayRemove([uid]) は「配列を要素として削除」になり、
      // Firestore 側で「ネスト配列は不可」エラーになるので uid を直接渡す
      const update: UpdateData<DocumentData> = {
        memberIDs: FieldValue.arrayRemove(uid),
        updatedAt: FieldValue.serverTimestamp(),
      };

      if (latestData.createdBy === uid) {
        update.createdBy = latestRemaining[0];
      }

      tx.update(ref, update);
    });
  }

  // 3) members/{uid} を削除（失敗しても続行）
  try {
    await db.collection("members").doc(uid).delete();
  } catch (e) {
    logger.warn("Failed to delete members doc (continue)", {
      uid,
      error: String(e),
    });
  }

  // 4) Auth ユーザー削除（ここで失敗したら「退会失敗」扱い）
  await auth.deleteUser(uid);

  logger.info("Account deleted completely", {uid});
}

/**
 * iconPath が
 * - "gs://bucket/path/to/file"
 * - "path/to/file"
 * のどちらでも来ても削除できるようにする。
 *
 * @param {string} iconPathOrGsUrl iconPath もしくは gs:// URL
 * @return {Promise<void>} 完了したら resolve
 */
async function deleteProfileImageByPathOrGsUrl(
  iconPathOrGsUrl: string,
): Promise<void> {
  // gs:// のときは既存ヘルパーで削除
  if (iconPathOrGsUrl.startsWith("gs://")) {
    await deleteByGsUrl(iconPathOrGsUrl);
    return;
  }

  // それ以外は「デフォルトバケットのオブジェクトパス」として扱う
  // （例: "profileImages/xxx.jpg"）
  const {getStorage} = await import("firebase-admin/storage");
  const bucket = getStorage().bucket();
  await bucket.file(iconPathOrGsUrl).delete({ignoreNotFound: true});
}
