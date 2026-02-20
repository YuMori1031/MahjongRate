import {getStorage} from "firebase-admin/storage";

/**
 * gs:// 形式のURLを Storage のパスに変換して削除するヘルパー
 *
 * @param {string} gsUrl gs://bucket/path/to/file の形式
 * @return {Promise<void>} 完了したら resolve
 */
export async function deleteByGsUrl(gsUrl: string): Promise<void> {
  // 例: gs://mahjongrate.appspot.com/icons/xxx.png
  if (!gsUrl.startsWith("gs://")) return;

  const noScheme = gsUrl.replace("gs://", "");
  const firstSlash = noScheme.indexOf("/");
  if (firstSlash <= 0) return;

  const bucketName = noScheme.substring(0, firstSlash);
  const objectPath = noScheme.substring(firstSlash + 1);

  if (!bucketName || !objectPath) return;

  const bucket = getStorage().bucket(bucketName);

  // 既に無い場合もあるので force delete のイメージで
  await bucket.file(objectPath).delete({ignoreNotFound: true});
}
