import {setGlobalOptions} from "firebase-functions/v2/options";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {getAuth} from "firebase-admin/auth";
import {ensureApp} from "../admin";

// コスト・負荷抑制用（共通）
setGlobalOptions({
  maxInstances: 1,
  region: "asia-northeast2",
});

/**
 * 未認証ユーザーを定期的に削除するスケジュールバッチ。
 * - 60分ごとに実行
 * - 作成から1時間以上経過した「メール未認証 & 有効なユーザー」を削除
 */
export const deleteUnverifiedUsers = onSchedule(
  {
    schedule: "every 60 minutes",
    timeZone: "Asia/Tokyo",
  },
  async () => {
    ensureApp();
    const auth = getAuth();

    const now = Date.now();
    const thresholdMs = 60 * 60 * 1000; // 1時間
    const cutoff = now - thresholdMs;

    let nextPageToken: string | undefined;

    do {
      const result = await auth.listUsers(1000, nextPageToken);

      const targets = result.users.filter((u) => {
        const createdAtMs = Date.parse(u.metadata.creationTime || "");
        const disabled = u.disabled;
        const emailVerified = u.emailVerified;

        if (Number.isNaN(createdAtMs)) return false;
        return !emailVerified && !disabled && createdAtMs < cutoff;
      });

      if (targets.length > 0) {
        const uids = targets.map((u) => u.uid);

        logger.info("Deleting unverified users", {
          count: uids.length,
          cutoff: new Date(cutoff).toISOString(),
          uids,
        });

        await auth.deleteUsers(uids);
      }

      nextPageToken = result.pageToken;
    } while (nextPageToken);
  },
);
