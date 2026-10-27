/**
 * Thin compat wrapper so existing namespaced Admin SDK calls keep working
 * on firebase-admin@14 (modular entry points). No secrets here.
 */
const {
  initializeApp,
  getApp,
  getApps,
  cert,
  applicationDefault,
} = require("firebase-admin/app");
const {
  getFirestore,
  FieldValue,
  FieldPath,
  Timestamp,
} = require("firebase-admin/firestore");
const { getAuth } = require("firebase-admin/auth");
const { getStorage } = require("firebase-admin/storage");

function firestore(...args) {
  return getFirestore(...args);
}
firestore.FieldValue = FieldValue;
firestore.FieldPath = FieldPath;
firestore.Timestamp = Timestamp;

module.exports = {
  initializeApp: (...args) => {
    if (getApps().length > 0) {
      return getApp();
    }
    return initializeApp(...args);
  },
  getApp,
  getApps,
  firestore,
  auth: (...args) => getAuth(...args),
  storage: (...args) => getStorage(...args),
  credential: { cert, applicationDefault },
};
