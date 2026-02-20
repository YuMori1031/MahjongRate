import {getApp, initializeApp, type App} from "firebase-admin/app";

/**
 * Firebase Admin SDK を初期化し、既に初期化済みの場合はそのインスタンスを返す。
 * Cloud Functions 側で複数回 initializeApp() が呼ばれてエラーになるのを防ぐ。
 *
 * @return {App} Firebase Admin の App インスタンス
 */
export function ensureApp(): App {
  try {
    return getApp();
  } catch {
    return initializeApp();
  }
}
