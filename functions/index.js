const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { createHash } = require("node:crypto");
initializeApp();
const db = getFirestore();
const hash = (s) => createHash("sha256").update(s).digest("hex");
const clean = (v) => String(v || "").trim();
function auth(r) {
  if (!r.auth) throw new HttpsError("unauthenticated", "Silakan login.");
  return r.auth.uid;
}
async function owner(uid, id) {
  const s = await db.doc(`stores/${id}`).get();
  if (!s.exists || s.data().ownerId !== uid)
    throw new HttpsError("permission-denied", "Hanya owner toko.");
  return s;
}
exports.completeProfile = onCall(async (r) => {
  const uid = auth(r),
    ref = db.doc(`users/${uid}`);
  const role = r.data.role;
  if (!["Owner", "Karyawan"].includes(role))
    throw new HttpsError("invalid-argument", "Pilih peran.");
  await db.runTransaction(async (t) => {
    if ((await t.get(ref)).exists) return;
    t.set(ref, {
      id: uid,
      name: clean(r.data.name),
      phone: clean(r.data.phone),
      email: r.auth.token.email || "",
      role,
      premium: false,
      storeIds: [],
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { ok: true };
});
exports.createStore = onCall(async (r) => {
  const uid = auth(r);
  const u = await db.doc(`users/${uid}`).get();
  if (u.data()?.role !== "Owner")
    throw new HttpsError(
      "permission-denied",
      "Hanya owner dapat membuat toko.",
    );
  const name = clean(r.data.name);
  if (!name || name.length > 100)
    throw new HttpsError(
      "invalid-argument",
      "Nama toko wajib diisi, maksimal 100 karakter.",
    );
  const key = hash(name.toLowerCase().replace(/\s+/g, " "));
  const lock = db.doc(`storeNames/${key}`),
    ref = db.collection("stores").doc();
  return db.runTransaction(async (t) => {
    const previous = await t.get(lock);
    if (previous.exists && !r.data.confirmDuplicate) return { duplicate: true };
    t.set(ref, {
      name,
      phone: clean(r.data.phone),
      city: clean(r.data.city),
      address: clean(r.data.address),
      ownerId: uid,
      memberIds: [uid],
      createdAt: FieldValue.serverTimestamp(),
    });
    t.set(ref.collection("members").doc(uid), {
      uid,
      name: u.data().name,
      email: u.data().email,
      role: "Owner",
    });
    t.set(lock, { exists: true });
    t.update(u.ref, { storeIds: FieldValue.arrayUnion(ref.id) });
    return { id: ref.id };
  });
});
exports.inviteEmployee = onCall(async (r) => {
  const uid = auth(r),
    storeId = clean(r.data.storeId);
  await owner(uid, storeId);
  const email = clean(r.data.email).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email))
    throw new HttpsError("invalid-argument", "Email tidak valid.");
  await db.doc(`invitations/${hash(storeId + ":" + email)}`).set({
    storeId,
    email,
    name: clean(r.data.name),
    createdBy: uid,
    status: "pending",
    createdAt: FieldValue.serverTimestamp(),
  });
  return { ok: true };
});
exports.syncMemberships = onCall(async (r) => {
  const uid = auth(r);
  if (!r.auth.token.email_verified) return { linked: 0 };
  const email = (r.auth.token.email || "").toLowerCase();
  const invites = await db
    .collection("invitations")
    .where("email", "==", email)
    .get();
  let linked = 0;
  for (const invite of invites.docs) {
    if (invite.data().status !== "pending") continue;
    await db.runTransaction(async (t) => {
      const fresh = await t.get(invite.ref);
      const s = db.doc(`stores/${invite.data().storeId}`),
        store = await t.get(s),
        user = await t.get(db.doc(`users/${uid}`));
      if (!store.exists || !user.exists || fresh.data().status !== "pending")
        return;
      t.update(s, { memberIds: FieldValue.arrayUnion(uid) });
      t.set(s.collection("members").doc(uid), {
        uid,
        email,
        name: user.data().name,
        role: store.data().ownerId === uid ? "Owner" : "Karyawan",
      });
      t.update(user.ref, { storeIds: FieldValue.arrayUnion(s.id) });
      t.update(invite.ref, { status: "accepted", uid });
      linked++;
    });
  }
  return { linked };
});

Object.assign(exports, require("./orders"));
