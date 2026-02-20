import {onCall, HttpsError} from "firebase-functions/v2/https";
import {ensureApp} from "../admin";
import {deleteUserDataAndAuth} from "../cleanup/deleteUserData";

/**
 * アプリ側から呼ぶ「退会」用 callable
 * - クライアントで再ログイン（requiresRecentLogin対策）してから呼ぶ想定
 * - ここでは「ログイン中ユーザー本人のみ」許可する
 */
export const deleteMyAccount = onCall(
  {
    region: "asia-northeast2",
  },
  async (req) => {
    ensureApp();

    const uid = req.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "ログインが必要です。");
    }

    const confirm = (req.data?.confirm ?? "") as string;
    if (confirm !== "DELETE") {
      throw new HttpsError("invalid-argument", "confirm が不正です。");
    }

    await deleteUserDataAndAuth(uid);

    return {ok: true};
  },
);
