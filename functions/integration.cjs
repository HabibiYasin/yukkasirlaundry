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

  const database = getFirestore();
  await database
    .doc(`stores/${shop.id}/customers/customer1`)
    .set({ name: "Pak Obi", phone: "081234", address: "" });
  const values = [
    "Cuci Lipat 2 Jam",
    "KG",
    0,
    2,
    7000,
    3,
    0,
    "",
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  await database.doc(`stores/${shop.id}/services/twohours`).set({ values });
  await database
    .doc(`stores/${shop.id}/services/sixhours`)
    .set({
      values: ["Cuci Lipat 6 Jam", "KG", 0, 6, 6000, ...values.slice(5)],
    });
  const payload = {
    storeId: shop.id,
    requestId: "video-order",
    customerId: "customer1",
    lines: [
      { serviceId: "twohours", quantity: 3, expectedPrice: 7000 },
      { serviceId: "sixhours", quantity: 3, expectedPrice: 6000 },
    ],
    paymentType: "pickup",
    note: "Pisahkan pakaian putih",
  };
  const order = await call("createOrder", verified.idToken, payload);
  assert.equal(
    (await call("createOrder", verified.idToken, payload)).id,
    order.id,
  );
  const ref = database.doc(`stores/${shop.id}/orders/${order.id}`);
  let data = (await ref.get()).data();
  assert.equal(data.total, 39000);
  assert.equal(data.paid, 0);
  assert.equal(data.balance, 39000);
  assert.equal(data.dueAt.toMillis() - data.createdAt.toMillis(), 6 * 3600000);
  await assert.rejects(() =>
    call("createOrder", verified.idToken, {
      ...payload,
      requestId: "bad-min",
      lines: [{ serviceId: "twohours", quantity: 1, expectedPrice: 7000 }],
    }),
  );
  await assert.rejects(() =>
    call("createOrder", verified.idToken, {
      ...payload,
      requestId: "bad-price",
      lines: [{ serviceId: "twohours", quantity: 3, expectedPrice: 1 }],
    }),
  );
  const outsider = await account("outsider@example.com");
  await assert.rejects(() =>
    call("createOrder", outsider.idToken, {
      ...payload,
      requestId: "bad-member",
    }),
  );
  const update = { storeId: shop.id, orderId: order.id };
  await assert.rejects(() =>
    call("updateOrder", verified.idToken, {
      ...update,
      requestId: "skip-status",
      action: "status",
      nextStatus: "Diambil",
    }),
  );
  await call("updateOrder", verified.idToken, {
    ...update,
    requestId: "status1",
    action: "status",
    nextStatus: "Diproses",
  });
  await call("updateOrder", verified.idToken, {
    ...update,
    requestId: "status2",
    action: "status",
    nextStatus: "Siap diambil",
  });
  await assert.rejects(() =>
    call("updateOrder", verified.idToken, {
      ...update,
      requestId: "unpaid-pickup",
      action: "status",
      nextStatus: "Diambil",
    }),
  );
  await assert.rejects(() =>
    call("updateOrder", verified.idToken, {
      ...update,
      requestId: "overpay",
      action: "pay",
      amount: 40000,
      method: "Tunai",
    }),
  );
  const payment = {
    ...update,
    requestId: "payment1",
    action: "pay",
    amount: 10000,
    method: "Tunai",
  };
  await call("updateOrder", verified.idToken, payment);
  await call("updateOrder", verified.idToken, payment);
  data = (await ref.get()).data();
  assert.equal(data.paid, 10000);
  assert.equal(data.balance, 29000);
  await call("updateOrder", verified.idToken, {
    ...update,
    requestId: "payment2",
    action: "pay",
    amount: 29000,
    method: "Transfer",
  });
  await call("updateOrder", verified.idToken, {
    ...update,
    requestId: "status3",
    action: "status",
    nextStatus: "Diambil",
  });
  data = (await ref.get()).data();
  assert.equal(data.status, "Diambil");
  assert.equal(data.paymentStatus, "Lunas");
  const dp = await call("createOrder", verified.idToken, {
    ...payload,
    requestId: "dp-order",
    paymentType: "deposit",
    paid: 15000,
    paymentMethod: "Tunai",
  });
  assert.equal(
    (await database.doc(`stores/${shop.id}/orders/${dp.id}`).get()).data()
      .balance,
    24000,
  );
  const paid = await call("createOrder", verified.idToken, {
    ...payload,
    requestId: "paid-order",
    paymentType: "paid",
    paymentMethod: "Transfer",
  });
  assert.equal(
    (await database.doc(`stores/${shop.id}/orders/${paid.id}`).get()).data()
      .balance,
    0,
  );
  console.log(
    "PASS: video example Rp39.000, authoritative price, minimum order, membership, three payment types, payment idempotency, status transitions, paid pickup.",
  );
  console.log(
    "PASS: registration, duplicate confirmation, owner authorization, verified invitations, membership synchronization, idempotency.",
  );
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
