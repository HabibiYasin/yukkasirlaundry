const assert = require("node:assert/strict");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
initializeApp({ projectId: "demo-yuk-kasir" });
async function account(email) {
  const r = await fetch(
    "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=demo",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email,
        password: "testing123",
        returnSecureToken: true,
      }),
    },
  );
  const a = await r.json();
  assert.ok(a.idToken, JSON.stringify(a));
  return a;
}
async function call(name, token, data) {
  const r = await fetch(
    `http://127.0.0.1:5001/demo-yuk-kasir/us-central1/${name}`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({ data }),
    },
  );
  const j = await r.json();
  if (j.error) throw Error(JSON.stringify(j.error));
  return j.result;
}
(async () => {
  const owner = await account("owner@example.com"),
    staff = await account("staff@example.com");
  await call("completeProfile", owner.idToken, {
    name: "Owner",
    phone: "081",
    role: "Owner",
  });
  await call("completeProfile", staff.idToken, {
    name: "Staff",
    phone: "082",
    role: "Karyawan",
  });
  const shop = await call("createStore", owner.idToken, {
    name: "Yuk Laundry",
    phone: "081",
    city: "Depok",
    address: "Jalan 1",
  });
  assert.ok(shop.id);
  assert.equal(
    (await call("createStore", owner.idToken, { name: "  YUK   Laundry  " }))
      .duplicate,
    true,
  );
  await assert.rejects(() =>
    call("createStore", staff.idToken, { name: "Unauthorized" }),
  );
  await call("inviteEmployee", owner.idToken, {
    storeId: shop.id,
    email: "staff@example.com",
    name: "Staff",
  });
  assert.equal((await call("syncMemberships", staff.idToken, {})).linked, 0);
  await getAuth().updateUser(staff.localId, { emailVerified: true });
  const signIn = await fetch(
    "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=demo",
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        email: "staff@example.com",
        password: "testing123",
        returnSecureToken: true,
      }),
    },
  );
  const verified = await signIn.json();
  assert.equal((await call("syncMemberships", verified.idToken, {})).linked, 1);
  const s = (await getFirestore().doc(`stores/${shop.id}`).get()).data();
  assert.ok(s.memberIds.includes(staff.localId));
  assert.equal((await call("syncMemberships", verified.idToken, {})).linked, 0);
  console.log(
    "PASS: registration, duplicate confirmation, owner authorization, verified invitations, membership synchronization, idempotency.",
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
