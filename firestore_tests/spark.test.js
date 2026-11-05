const { readFileSync } = require("node:fs");
const { createHash } = require("node:crypto");
const { test, before, after } = require("node:test");
const assert = require("node:assert/strict");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  collection,
  getDocs,
  query,
  where,
  runTransaction,
  writeBatch,
  serverTimestamp,
  arrayUnion,
  Timestamp,
} = require("firebase/firestore");
let env, owner, staff, outsider, unverified;
const hash = (v) =>
  createHash("sha256")
    .update(v)
    .digest("base64")
    .replaceAll("/", "_")
    .replaceAll("+", "-");
const profile = (uid, role) => ({
  id: uid,
  name: uid,
  phone: "08123",
  email: uid + "@example.com",
  role,
  premium: false,
  storeIds: [],
  createdAt: serverTimestamp(),
});
async function createStore(
  db,
  uid,
  sid,
  name = "Yuk Laundry",
  confirmDuplicate = false,
) {
  const key = hash(name.trim().toLowerCase().replace(/\s+/g, " "));
  return runTransaction(db, async (t) => {
    const index = doc(db, "storeNames", key);
    const found = await t.get(index);
    const u = await t.get(doc(db, "users", uid));
    if (found.exists() && !confirmDuplicate) return { duplicate: true };
    t.set(doc(db, "stores", sid), {
      name,
      nameKey: key,
      duplicateConfirmed: confirmDuplicate,
      phone: "081",
      city: "Depok",
      address: "Jalan 1",
      ownerId: uid,
      memberIds: [uid],
      createdAt: serverTimestamp(),
    });
    if (!found.exists()) t.set(index, { storeId: sid });
    t.set(doc(db, `stores/${sid}/members/${uid}`), {
      uid,
      name: u.data().name,
      email: u.data().email,
      role: "Owner",
    });
    t.update(doc(db, "users", uid), {
      storeIds: arrayUnion(sid),
      lastStoreId: sid,
    });
    return { id: sid };
  });
}
async function invite(db, sid, email) {
  await setDoc(doc(db, "invitations", hash(sid + ":" + email)), {
    storeId: sid,
    email,
    name: "Staff",
    createdBy: "owner",
    status: "pending",
    createdAt: serverTimestamp(),
  });
}
async function join(db, uid, sid) {
  return runTransaction(db, async (t) => {
    const i = doc(db, "invitations", hash(sid + ":" + uid + "@example.com"));
    const invitation = await t.get(i);
    if (invitation.data().status !== "pending") return;
    const s = doc(db, "stores", sid);
    await t.get(s);
    const u = doc(db, "users", uid),
      p = await t.get(u);
    t.update(s, { memberIds: arrayUnion(uid) });
    t.set(doc(db, `stores/${sid}/members/${uid}`), {
      uid,
      name: p.data().name,
      email: p.data().email,
      role: "Karyawan",
    });
    t.update(u, { storeIds: arrayUnion(sid), lastStoreId: sid });
    t.update(i, { status: "accepted", uid });
  });
}
const service = (name, price, hours) => [
  name,
  "KG",
  0,
  hours,
  price,
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
function orderData(id, type = "pickup", extra = {}) {
  const now = Timestamp.fromMillis(Date.now());
  const total = 39000,
    paid = type === "paid" ? total : type === "deposit" ? 10000 : 0;
  return {
    number: "YK-" + id,
    store: { name: "Yuk Laundry", address: "Jalan 1", phone: "081" },
    customer: { id: "customer1", name: "Obi", phone: "082", address: "" },
    lines: [
      {
        serviceId: "two",
        name: "Cuci 2 Jam",
        unit: "KG",
        price: 7000,
        quantity: 3,
        amount: 21000,
        note: "",
        durationHours: 2,
      },
      {
        serviceId: "six",
        name: "Cuci 6 Jam",
        unit: "KG",
        price: 6000,
        quantity: 3,
        amount: 18000,
        note: "",
        durationHours: 6,
      },
    ].sort((a, b) => b.durationHours - a.durationHours),
    total,
    paid,
    balance: total - paid,
    paymentType: type,
    paymentMethod: paid ? "Tunai" : "",
    paymentStatus: paid === total ? "Lunas" : paid ? "DP" : "Belum lunas",
    status: "Baru",
    note: "",
    createdAt: now,
    dueAt: Timestamp.fromMillis(now.toMillis() + 21600000),
    createdBy: "staff",
    lastEventId: "created",
    ...extra,
  };
}
async function createOrder(db, id, data) {
  const b = writeBatch(db);
  b.set(doc(db, "stores/shop/orders", id), data);
  b.set(doc(db, `stores/shop/orders/${id}/events/created`), {
    type: "created",
    uid: "staff",
    at: serverTimestamp(),
    paid: data.paid,
    method: data.paymentMethod,
  });
  return b.commit();
}
async function change(db, orderId, eventId, action) {
  return runTransaction(db, async (t) => {
    const ref = doc(db, "stores/shop/orders", orderId),
      event = doc(db, `stores/shop/orders/${orderId}/events/${eventId}`);
    const old = await t.get(ref),
      existing = await t.get(event);
    if (existing.exists()) return;
    const o = old.data();
    if (action.type === "payment") {
      const paid = o.paid + action.amount;
      t.update(ref, {
        paid,
        balance: o.total - paid,
        paymentStatus: paid === o.total ? "Lunas" : "DP",
        lastEventId: eventId,
        updatedAt: serverTimestamp(),
      });
      t.set(event, { ...action, uid: "staff", at: serverTimestamp() });
    } else {
      t.update(ref, {
        status: action.to,
        lastEventId: eventId,
        updatedAt: serverTimestamp(),
      });
      t.set(event, {
        type: "status",
        from: o.status,
        to: action.to,
        uid: "staff",
        at: serverTimestamp(),
      });
    }
  });
}
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-yuk-spark",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
  });
  await env.clearFirestore();
  const ctx = (uid, verified = true) =>
    env
      .authenticatedContext(uid, {
        email: uid + "@example.com",
        email_verified: verified,
      })
      .firestore();
  owner = ctx("owner");
  staff = ctx("staff");
  outsider = ctx("outsider");
  unverified = ctx("staff", false);
  for (const [db, id, role] of [
    [owner, "owner", "Owner"],
    [staff, "staff", "Karyawan"],
    [outsider, "outsider", "Karyawan"],
  ])
    await setDoc(doc(db, "users", id), profile(id, role));
  await createStore(owner, "owner", "shop");
  await invite(owner, "shop", "staff@example.com");
});
after(async () => { await env?.cleanup(); });

test("profile cannot escalate premium, role or create for others", async () => {
  await assertFails(updateDoc(doc(staff, "users/staff"), { premium: true }));
  await assertFails(updateDoc(doc(staff, "users/staff"), { role: "Owner" }));
  await assertFails(
    setDoc(doc(staff, "users/forged"), profile("forged", "Owner")),
  );
  await assertFails(
    setDoc(
      doc(
        env
          .authenticatedContext("premium", { email: "premium@example.com" })
          .firestore(),
        "users/premium",
      ),
      { ...profile("premium", "Owner"), premium: true },
    ),
  );
  await assertSucceeds(
    updateDoc(doc(staff, "users/staff"), { name: "Staff Baru" }),
  );
});
test("duplicate confirmation and owner-only shop creation", async () => {
  assert.equal(
    (await createStore(owner, "owner", "duplicate", "  YUK   Laundry  "))
      .duplicate,
    true,
  );
  await assertSucceeds(
    createStore(owner, "owner", "duplicate", "  YUK   Laundry  ", true),
  );
  await assertFails(createStore(staff, "staff", "forged-shop", "Other shop"));
});
test("unverified or wrong email cannot accept invitation", async () => {
  await assertFails(join(unverified, "staff", "shop"));
  await assertFails(
    getDoc(doc(outsider, "invitations", hash("shop:staff@example.com"))),
  );
  await assertFails(
    updateDoc(doc(outsider, "stores/shop"), {
      memberIds: ["owner", "outsider"],
    }),
  );
});
test("verified invite claim is atomic, queryable and idempotent", async () => {
  const docs = await getDocs(
    query(
      collection(staff, "invitations"),
      where("email", "==", "staff@example.com"),
    ),
  );
  assert.equal(docs.size, 1);
  await assertSucceeds(join(staff, "staff", "shop"));
  await join(staff, "staff", "shop");
  assert.deepEqual((await getDoc(doc(staff, "users/staff"))).data().storeIds, [
    "shop",
  ]);
  assert.equal(
    (
      await getDocs(
        query(
          collection(staff, "stores"),
          where("memberIds", "array-contains", "staff"),
        ),
      )
    ).size,
    1,
  );
  await assertFails(
    updateDoc(doc(staff, "stores/shop"), {
      memberIds: ["owner", "staff", "outsider"],
    }),
  );
  await assertFails(
    updateDoc(doc(staff, "users/staff"), {
      storeIds: ["shop", "duplicate"],
      lastStoreId: "duplicate",
    }),
  );
});
test("service ownership and customer access", async () => {
  await assertSucceeds(
    setDoc(doc(owner, "stores/shop/services/two"), {
      values: service("Cuci 2 Jam", 7000, 2),
    }),
  );
  await setDoc(doc(owner, "stores/shop/services/six"), {
    values: service("Cuci 6 Jam", 6000, 6),
  });
  await assertFails(
    updateDoc(doc(staff, "stores/shop/services/two"), {
      values: service("Fake price", 1, 2),
    }),
  );
  await assertSucceeds(
    setDoc(doc(staff, "stores/shop/customers/customer1"), {
      name: "Obi",
      phone: "082",
      address: "",
    }),
  );
  await assertFails(getDoc(doc(outsider, "stores/shop/customers/customer1")));
});
test("video checkout, DP and paid checkout succeed without admin/functions", async () => {
  for (const type of ["pickup", "deposit", "paid"])
    await assertSucceeds(createOrder(staff, type, orderData(type, type)));
  assert.equal(
    (await getDoc(doc(staff, "stores/shop/orders/pickup"))).data().total,
    39000,
  );
});
test("four distinct services fit rules access limits", async () => {
  const data = orderData("six-lines");
  data.lines = [];
  for (let i = 0; i < 4; i++) {
    await setDoc(doc(owner, `stores/shop/services/s${i}`), {
      values: service("Service " + i, 1000, 6),
    });
    data.lines.push({
      serviceId: "s" + i,
      name: "Service " + i,
      unit: "KG",
      price: 1000,
      quantity: 3,
      amount: 3000,
      note: "",
      durationHours: 6,
    });
  }
  data.total = 12000;
  data.balance = 12000;
  await assertSucceeds(createOrder(staff, "six-lines", data));
});
test("forged prices totals snapshots timestamps and missing audit are denied", async () => {
  for (const [id, patch] of [
    ["total", { total: 1, balance: 1 }],
    ["paid", { paid: 39000, balance: 0, paymentStatus: "Lunas" }],
    ["date", { createdAt: Timestamp.fromMillis(0) }],
    [
      "customer",
      {
        customer: { id: "customer1", name: "Fake", phone: "082", address: "" },
      },
    ],
  ])
    await assertFails(createOrder(staff, id, orderData(id, "pickup", patch)));
  const d = orderData("price");
  d.lines[0].price = 1;
  d.lines[0].amount = 3;
  d.total = 18003;
  d.balance = 18003;
  await assertFails(createOrder(staff, "price", d));
  const minimum = orderData("minimum");
  minimum.lines[0].quantity = 1;
  minimum.lines[0].amount = 7000;
  minimum.total = 25000;
  minimum.balance = 25000;
  await assertFails(createOrder(staff, "minimum", minimum));
  await assertFails(
    setDoc(doc(staff, "stores/shop/orders/noaudit"), orderData("noaudit")),
  );
  await assertFails(createOrder(outsider, "outsider", orderData("outsider")));
});
test("payments are atomic, immutable, bounded and idempotent", async () => {
  await assertFails(
    updateDoc(doc(staff, "stores/shop/orders/pickup"), {
      paid: 39000,
      balance: 0,
      paymentStatus: "Lunas",
    }),
  );
  await assertFails(
    change(staff, "pickup", "overpay", {
      type: "payment",
      amount: 40000,
      method: "Tunai",
    }),
  );
  await change(staff, "pickup", "p1", {
    type: "payment",
    amount: 10000,
    method: "Tunai",
  });
  await change(staff, "pickup", "p1", {
    type: "payment",
    amount: 10000,
    method: "Tunai",
  });
  assert.equal(
    (await getDoc(doc(staff, "stores/shop/orders/pickup"))).data().paid,
    10000,
  );
  await assertFails(
    updateDoc(doc(staff, "stores/shop/orders/pickup/events/p1"), {
      amount: 20000,
    }),
  );
});
test("sequential status and full payment required for pickup", async () => {
  await assertFails(
    change(staff, "pickup", "skip", { type: "status", to: "Diambil" }),
  );
  await change(staff, "pickup", "s1", { type: "status", to: "Diproses" });
  await change(staff, "pickup", "s2", { type: "status", to: "Siap diambil" });
  await assertFails(
    change(staff, "pickup", "unpaid", { type: "status", to: "Diambil" }),
  );
  await change(staff, "pickup", "p2", {
    type: "payment",
    amount: 29000,
    method: "Transfer",
  });
  await change(staff, "pickup", "s3", { type: "status", to: "Diambil" });
  assert.equal(
    (await getDoc(doc(staff, "stores/shop/orders/pickup"))).data().balance,
    0,
  );
});

test("450-service import remains within atomic batch limits", async () => {
  const batch = writeBatch(owner);
  for (let i = 0; i < 450; i++)
    batch.set(doc(owner, `stores/shop/services/import${i}`), {
      values: service("Impor " + i, 7000, 72),
    });
  await assertSucceeds(batch.commit());
});
test("fifth line and forged audit history are denied", async () => {
  const d = orderData("too-many");
  d.lines = Array.from({ length: 5 }, () => ({ ...d.lines[0] }));
  d.total = 90000;
  d.balance = 90000;
  await assertFails(createOrder(staff, "too-many", d));
  await assertFails(
    setDoc(doc(staff, "stores/shop/orders/pickup/events/fake"), {
      type: "payment",
      uid: "staff",
      at: serverTimestamp(),
      amount: 500,
      method: "Tunai",
    }),
  );
  await assertFails(getDoc(doc(outsider, "stores/shop/orders/pickup")));
});
