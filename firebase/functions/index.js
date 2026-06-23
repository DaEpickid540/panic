/**
 * Panic: Arena — Cloud Functions
 *
 * - assignRoles (HTTPS POST): elects exactly one hunter per game, deterministically,
 *   and returns the caller's role. Safe under concurrent calls via a transaction.
 * - validateStateTransition (RTDB trigger): rejects illegal phase changes.
 * - onPlayerLeave (RTDB trigger): converts a disconnecting player to ghost and
 *   checks the end condition.
 *
 * Deploy: firebase deploy --only functions
 * Node 18+, firebase-functions v4, firebase-admin v12.
 */

const functions = require("firebase-functions");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.database();

// Mirror of GameManager.Phase (keep in sync with GDScript).
const Phase = { LOBBY: 0, COUNTDOWN: 1, HUNTING: 2, END: 3 };
const LEGAL_TRANSITIONS = {
  [Phase.LOBBY]: [Phase.COUNTDOWN],
  [Phase.COUNTDOWN]: [Phase.HUNTING, Phase.LOBBY],
  [Phase.HUNTING]: [Phase.END],
  [Phase.END]: [Phase.LOBBY],
};

/**
 * POST /assignRoles
 * Body: { playerId: string, totalPlayers: number, gameId: string }
 * Returns: { playerId, role: "hunter" | "hunted" | "ghost" }
 *
 * Election is deterministic: the first caller fixes a random hunterIndex in
 * [0, totalPlayers); players are slotted in arrival order; the player whose
 * slot == hunterIndex is the (single) hunter. A transaction makes concurrent
 * calls safe — exactly one hunter regardless of call ordering.
 */
exports.assignRoles = functions.https.onRequest(async (req, res) => {
  // CORS (the HTML5 client calls this cross-origin).
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(204).send("");
  if (req.method !== "POST") return res.status(405).json({ error: "POST only" });

  const { playerId, totalPlayers, gameId } = req.body || {};
  if (!playerId || !gameId || !totalPlayers || totalPlayers < 1) {
    return res.status(400).json({ error: "playerId, gameId, totalPlayers required" });
  }

  const electionRef = db.ref(`/games/${gameId}/election`);
  const result = await electionRef.transaction((cur) => {
    if (cur === null) {
      cur = { hunterIndex: Math.floor(Math.random() * totalPlayers), order: {} };
    }
    if (!(playerId in (cur.order || {}))) {
      cur.order = cur.order || {};
      cur.order[playerId] = Object.keys(cur.order).length;
    }
    return cur;
  });

  const election = result.snapshot.val();
  const slot = election.order[playerId];
  const role = slot === election.hunterIndex ? "hunter" : "hunted";

  // Mirror to the authoritative roles node (ints: hunter=0, hunted=1, ghost=2).
  await db.ref(`/games/${gameId}/playerRoles/${playerId}`).set(role === "hunter" ? 0 : 1);

  return res.status(200).json({ playerId, role });
});

/** Reject illegal phase transitions by reverting. */
exports.validateStateTransition = functions.database
  .ref("/games/{gameId}/phase")
  .onUpdate(async (change) => {
    const before = change.before.val();
    const after = change.after.val();
    const allowed = LEGAL_TRANSITIONS[before] || [];
    if (!allowed.includes(after)) {
      console.warn(`Illegal transition ${before} -> ${after}; reverting.`);
      return change.before.ref.set(before);
    }
    return null;
  });

/** Disconnect handling: player -> ghost, then re-check end condition. */
exports.onPlayerLeave = functions.database
  .ref("/games/{gameId}/players/{playerId}")
  .onDelete(async (snap, context) => {
    const { gameId, playerId } = context.params;
    await db.ref(`/games/${gameId}/playerRoles/${playerId}`).set(2); // ghost

    const rolesSnap = await db.ref(`/games/${gameId}/playerRoles`).get();
    const roles = rolesSnap.val() || {};
    const huntedLeft = Object.values(roles).filter((r) => r === 1).length;
    if (huntedLeft === 0) {
      return db.ref(`/games/${gameId}/phase`).set(Phase.END);
    }
    return null;
  });
