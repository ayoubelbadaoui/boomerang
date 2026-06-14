import { db, admin } from '../firebase';
import * as functions from 'firebase-functions/v1';
import { FUNCTIONS_REGION } from '../../config/constants';

const Timestamp = admin.firestore.Timestamp;

/** Smallest epoch-millis value we treat as "already in milliseconds". Values
 * below this are assumed to be epoch seconds and scaled up. (1e12 ms ≈ 2001.) */
const MILLIS_THRESHOLD = 1_000_000_000_000;

/**
 * Coerce a legacy `createdAt` value into a Firestore Timestamp.
 * Returns null when the value is already a Timestamp (no write needed) or
 * cannot be interpreted at all.
 */
function normalizeCreatedAt(
  value: unknown,
): FirebaseFirestore.Timestamp | null {
  if (value instanceof Timestamp) return null; // already correct
  if (value == null) return null; // nothing to derive from; leave as-is

  if (value instanceof Date) return Timestamp.fromDate(value);

  if (typeof value === 'number' && Number.isFinite(value)) {
    const ms = value < MILLIS_THRESHOLD ? value * 1000 : value;
    return Timestamp.fromMillis(Math.round(ms));
  }

  if (typeof value === 'string') {
    const asInt = Number(value);
    if (Number.isFinite(asInt) && value.trim() !== '') {
      const ms = asInt < MILLIS_THRESHOLD ? asInt * 1000 : asInt;
      return Timestamp.fromMillis(Math.round(ms));
    }
    const parsed = Date.parse(value);
    if (!Number.isNaN(parsed)) return Timestamp.fromMillis(parsed);
  }

  // Firestore-style { _seconds, _nanoseconds } that lost its type.
  if (typeof value === 'object') {
    const obj = value as Record<string, unknown>;
    const seconds = obj._seconds ?? obj.seconds;
    if (typeof seconds === 'number') {
      const nanos =
        typeof (obj._nanoseconds ?? obj.nanoseconds) === 'number'
          ? (obj._nanoseconds ?? obj.nanoseconds) as number
          : 0;
      return new Timestamp(seconds, nanos);
    }
  }

  return null;
}

/**
 * Coerce a legacy counter (`likes` / `commentsCount`) into a non-negative
 * integer. Returns null when the value is already a valid integer.
 * When the field is a `likes` count we prefer the authoritative
 * `likedBy.length` if it disagrees.
 */
function normalizeCount(value: unknown, authoritative?: number): number | null {
  let current: number | null = null;
  if (typeof value === 'number' && Number.isInteger(value) && value >= 0) {
    current = value;
  }

  if (authoritative != null) {
    // Trust likedBy length over a stored counter.
    if (current !== authoritative) return authoritative;
    return null;
  }

  if (current != null) return null; // already valid, no authoritative override

  if (typeof value === 'number' && Number.isFinite(value)) {
    return Math.max(0, Math.trunc(value));
  }
  if (typeof value === 'string') {
    const parsed = parseInt(value, 10);
    if (Number.isFinite(parsed)) return Math.max(0, parsed);
  }
  return 0; // unparseable / missing → default
}

/**
 * One-off HTTP backfill that normalizes legacy boomerang documents whose
 * `createdAt`, `likes`, or `commentsCount` were written in a non-current
 * shape (epoch ints, ISO strings, stringified counters, …). These shapes
 * used to crash the home feed's in-memory sort/mapping.
 *
 * Safe to run repeatedly: documents already in the correct shape are skipped.
 * Walks the collection by document id so memory stays bounded for large
 * datasets, and commits writes in batches of 500.
 *
 * Invoke once after deploy:
 *   firebase functions:shell → normalizeBoomerangFields()
 * or hit the deployed HTTPS URL.
 */
export const normalizeBoomerangFields = functions
  .region(FUNCTIONS_REGION)
  .runWith({ timeoutSeconds: 540, memory: '1GB' })
  .https.onRequest(async (_req, res) => {
    functions.logger.info('normalizeBoomerangFields: starting');

    let scanned = 0;
    let updated = 0;
    const PAGE = 300;
    let lastDoc: FirebaseFirestore.QueryDocumentSnapshot | undefined;

    while (true) {
      let query = db
        .collection('boomerangs')
        .orderBy(admin.firestore.FieldPath.documentId())
        .limit(PAGE);
      if (lastDoc) query = query.startAfter(lastDoc);

      const page = await query.get();
      if (page.empty) break;

      let batch = db.batch();
      let pending = 0;
      const commits: Promise<FirebaseFirestore.WriteResult[]>[] = [];

      for (const doc of page.docs) {
        scanned++;
        const data = doc.data();
        const fix: Record<string, unknown> = {};

        const nextCreatedAt = normalizeCreatedAt(data.createdAt);
        if (nextCreatedAt) fix.createdAt = nextCreatedAt;

        const likedByLength = Array.isArray(data.likedBy)
          ? data.likedBy.filter((u: unknown) => typeof u === 'string' && u).length
          : undefined;
        const nextLikes = normalizeCount(data.likes, likedByLength);
        if (nextLikes != null) fix.likes = nextLikes;

        const nextComments = normalizeCount(data.commentsCount);
        if (nextComments != null) fix.commentsCount = nextComments;

        if (Object.keys(fix).length === 0) continue;

        batch.update(doc.ref, fix);
        pending++;
        updated++;
        if (pending >= 500) {
          commits.push(batch.commit());
          batch = db.batch();
          pending = 0;
        }
      }
      if (pending > 0) commits.push(batch.commit());
      await Promise.all(commits);

      lastDoc = page.docs[page.docs.length - 1];
    }

    const msg = `normalizeBoomerangFields complete: ${updated} of ${scanned} boomerangs updated.`;
    functions.logger.info(msg);
    res.status(200).send(msg);
  });
