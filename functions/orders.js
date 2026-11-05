const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { getFirestore, Timestamp } = require("firebase-admin/firestore");
function bad(message) {
  throw new HttpsError("invalid-argument", message);
}
function id(v) {
  if (typeof v !== "string" || !/^[A-Za-z0-9_-]{1,128}$/.test(v))
    bad("ID tidak valid.");
  return v;
}
function text(v, max = 1000) {
  return String(v || "")
    .trim()
    .slice(0, max);
}
async function access(t, storeId, uid) {
  const s = await t.get(getFirestore().doc(`stores/${storeId}`));
  if (!s.exists || !s.data().memberIds.includes(uid))
    throw new HttpsError("permission-denied", "Tidak memiliki akses toko.");
  return s.data();
}
function user(r) {
  if (!r.auth) throw new HttpsError("unauthenticated", "Silakan masuk.");
  return r.auth.uid;
}
exports.createOrder = onCall(async (r) => {
  const uid = user(r),
    d = r.data,
    storeId = id(d.storeId),
    orderId = id(d.requestId),
    db = getFirestore();
  const ref = db.doc(`stores/${storeId}/orders/${orderId}`);
  return db.runTransaction(async (t) => {
    const store = await access(t, storeId, uid),
      existing = await t.get(ref);
    if (existing.exists) {
      if (existing.data().createdBy !== uid)
        throw new HttpsError(
          "permission-denied",
          "ID transaksi sudah digunakan.",
        );
      return { id: ref.id };
    }
    const customer = await t.get(
      db.doc(`stores/${storeId}/customers/${id(d.customerId)}`),
    );
    if (!customer.exists) bad("Konsumen tidak tersedia.");
    if (!Array.isArray(d.lines) || !d.lines.length || d.lines.length > 50)
      bad("Pilih 1 sampai 50 layanan.");
    const now = Timestamp.now();
    const lines = [];
    let total = 0,
      maxHours = 0;
    for (const input of d.lines) {
      const service = await t.get(
        db.doc(`stores/${storeId}/services/${id(input.serviceId)}`),
      );
      if (!service.exists) bad("Layanan sudah tidak tersedia.");
      const v = service.data().values;
      const quantity = Number(input.quantity),
        price = Number(v[4]),
        minimum = Number(v[5]);
      if (
        !Number.isFinite(quantity) ||
        quantity <= 0 ||
        quantity > 100000 ||
        Math.abs(quantity * 100 - Math.round(quantity * 100)) > 0.00001
      )
        bad("Kuantitas harus positif, maksimal 2 desimal.");
      if (quantity < minimum) bad(`Minimum ${v[0]} adalah ${minimum} ${v[1]}.`);
      if (!Number.isFinite(price) || price < 0)
        bad("Harga layanan tidak valid.");
      if (Number(input.expectedPrice) !== price)
        throw new HttpsError(
          "failed-precondition",
          "Harga layanan berubah. Buka kembali pilihan layanan sebelum menyimpan.",
        );
      const amount = Math.round(quantity * price);
      total += amount;
      const hours = Number(v[2]) * 24 + Number(v[3]);
      if (!Number.isFinite(hours) || hours < 0)
        bad("Durasi layanan tidak valid.");
      maxHours = Math.max(maxHours, hours);
      lines.push({
        serviceId: service.id,
        name: v[0],
        unit: v[1],
        price,
        quantity,
        amount,
        note: text(input.note),
        durationHours: hours,
      });
    }
    if (!Number.isSafeInteger(total) || total > 1000000000)
      bad("Total transaksi terlalu besar.");
    if (!["paid", "deposit", "pickup"].includes(d.paymentType))
      bad("Pilih tipe pembayaran.");
    let paid =
      d.paymentType === "paid"
        ? total
        : d.paymentType === "pickup"
          ? 0
          : Number(d.paid);
    if (
      !Number.isSafeInteger(paid) ||
      paid < 0 ||
      paid > total ||
      (d.paymentType === "deposit" && (paid <= 0 || paid >= total))
    )
      bad("DP harus lebih dari 0 dan kurang dari total.");
    const method = paid > 0 ? text(d.paymentMethod, 30) : "";
    if (paid > 0 && !["Tunai", "Transfer"].includes(method))
      bad("Pilih metode pembayaran.");
    const order = {
      number: `YK-${new Date(now.toMillis()).toISOString().slice(0, 10).replaceAll("-", "")}-${ref.id.slice(0, 8).toUpperCase()}`,
      store: { name: store.name, address: store.address, phone: store.phone },
      customer: { id: customer.id, ...customer.data() },
      lines,
      total,
      paid,
      balance: total - paid,
      paymentType: d.paymentType,
      paymentMethod: method,
      paymentStatus:
        paid === total ? "Lunas" : paid === 0 ? "Belum lunas" : "DP",
      status: "Baru",
      note: text(d.note),
      createdAt: now,
      dueAt: Timestamp.fromMillis(now.toMillis() + maxHours * 3600000),
      createdBy: uid,
    };
    t.create(ref, order);
    t.create(ref.collection("events").doc(), {
      type: "created",
      uid,
      at: now,
      paid,
      method,
    });
    return { id: ref.id };
  });
});
exports.updateOrder = onCall(async (r) => {
  const uid = user(r),
    d = r.data,
    storeId = id(d.storeId),
    db = getFirestore(),
    ref = db.doc(`stores/${storeId}/orders/${id(d.orderId)}`),
    event = ref.collection("events").doc(id(d.requestId));
  return db.runTransaction(async (t) => {
    await access(t, storeId, uid);
    const snap = await t.get(ref),
      previous = await t.get(event);
    if (previous.exists) return { ok: true };
    if (!snap.exists)
      throw new HttpsError("not-found", "Transaksi tidak ditemukan.");
    const order = snap.data(),
      now = Timestamp.now();
    if (d.action === "pay") {
      const amount = Number(d.amount);
      if (
        !Number.isSafeInteger(amount) ||
        amount <= 0 ||
        amount > order.balance
      )
        bad("Pembayaran harus positif dan tidak melebihi sisa tagihan.");
      if (!["Tunai", "Transfer"].includes(d.method))
        bad("Pilih metode pembayaran.");
      const paid = order.paid + amount;
      t.update(ref, {
        paid,
        balance: order.total - paid,
        paymentStatus: paid === order.total ? "Lunas" : "DP",
      });
      t.create(event, {
        type: "payment",
        uid,
        at: now,
        amount,
        method: d.method,
      });
    } else if (d.action === "status") {
      const next = {
        Baru: "Diproses",
        Diproses: "Siap diambil",
        "Siap diambil": "Diambil",
      }[order.status];
      if (!next || next !== d.nextStatus)
        throw new HttpsError(
          "failed-precondition",
          "Status sudah berubah. Muat ulang transaksi.",
        );
      if (next === "Diambil" && order.balance > 0)
        throw new HttpsError(
          "failed-precondition",
          "Lunasi tagihan sebelum pengambilan.",
        );
      t.update(ref, { status: next, updatedAt: now });
      t.create(event, {
        type: "status",
        uid,
        at: now,
        from: order.status,
        to: next,
      });
    } else bad("Aksi tidak valid.");
    return { ok: true };
  });
});
