const { readFileSync } = require("node:fs");
const { test, before, after } = require("node:test");
const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const { doc, setDoc, getDoc, updateDoc } = require("firebase/firestore");
let env;
before(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-yuk-kasir",
    firestore: { rules: readFileSync("../firestore.rules", "utf8") },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "stores/shop"), {
      name: "Laundry",
      ownerId: "owner",
      memberIds: ["owner", "staff"],
    });
    await setDoc(doc(db, "users/staff"), {
      name: "Staff",
      phone: "08",
      role: "Karyawan",
      premium: false,
      storeIds: ["shop"],
    });
  });
});
after(async () => env?.cleanup());
test("outsider cannot read store", async () =>
  assertFails(
    getDoc(
      doc(env.authenticatedContext("outsider").firestore(), "stores/shop"),
    ),
  ));
test("employee can read linked store", async () =>
  assertSucceeds(
    getDoc(doc(env.authenticatedContext("staff").firestore(), "stores/shop")),
  ));
test("employee cannot escalate role or premium", async () => {
  const db = env.authenticatedContext("staff").firestore();
  await assertFails(updateDoc(doc(db, "users/staff"), { premium: true }));
  await assertFails(updateDoc(doc(db, "users/staff"), { role: "Owner" }));
  await assertFails(updateDoc(doc(db, "users/staff"), { storeIds: ["other"] }));
});
test("employee cannot edit services; owner can", async () => {
  const values = Array(19).fill(0);
  await assertFails(
    setDoc(
      doc(
        env.authenticatedContext("staff").firestore(),
        "stores/shop/services/one",
      ),
      { values },
    ),
  );
  await assertSucceeds(
    setDoc(
      doc(
        env.authenticatedContext("owner").firestore(),
        "stores/shop/services/one",
      ),
      { values },
    ),
  );
});
test("member may create customer; outsider cannot", async () => {
  const data = { name: "Budi", phone: "081234", address: "" };
  await assertSucceeds(
    setDoc(
      doc(
        env.authenticatedContext("staff").firestore(),
        "stores/shop/customers/one",
      ),
      data,
    ),
  );
  await assertFails(
    setDoc(
      doc(
        env.authenticatedContext("outsider").firestore(),
        "stores/shop/customers/two",
      ),
      data,
    ),
  );
});
test("client cannot forge membership", async () =>
  assertFails(
    updateDoc(
      doc(env.authenticatedContext("staff").firestore(), "stores/shop"),
      { memberIds: ["staff", "outsider"] },
    ),
  ));
