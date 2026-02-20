import {Firestore} from "firebase-admin/firestore";

/**
 * Firestore のコレクション配下を、バッチで再帰的に削除するヘルパー。
 * - Admin SDK には「コレクション丸ごと削除」APIが無いので、クエリ→バッチ削除を繰り返す。
 *
 * @param {Firestore} db Firestore (Admin SDK) のインスタンス
 * @param {string} collectionPath 削除対象コレクションのパス（例: "members/uid/xxx"）
 * @param {number} [batchSize=200] 1回の削除件数（多すぎるとタイムアウトしやすい）
 * @return {Promise<void>} 完了したら resolve
 */
export async function deleteCollectionByPath(
  db: Firestore,
  collectionPath: string,
  batchSize = 200,
): Promise<void> {
  let snap = await db.collection(collectionPath).limit(batchSize).get();

  while (!snap.empty) {
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();

    snap = await db.collection(collectionPath).limit(batchSize).get();
  }
}
