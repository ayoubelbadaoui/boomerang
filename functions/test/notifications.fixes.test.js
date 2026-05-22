const test = require("node:test");
const assert = require("node:assert/strict");

const { buildChatNotificationBody } = require("../index.js");
const { renderTemplate } = require("../lib/domain/templates.js");
const { normalizePayload } = require("../lib/application/notificationService.js");

test("sharedPost body is human-readable and not a raw id", () => {
  const rawId = "ahjedh7382abcd9012";
  const body = buildChatNotificationBody("sharedPost", rawId, null);

  assert.equal(body, "📫 Shared a post");
  assert.notEqual(body, rawId);
});

test("sharedPost reply formatting remains readable", () => {
  const body = buildChatNotificationBody(
    "sharedPost",
    "post_doc_id_123",
    "This is a long reply preview that should be truncated in push",
  );

  assert.match(body, /^Replied to "/);
  assert.match(body, /📫 Shared a post$/);
});

test("templates never leak actor uid when display name is missing", () => {
  const payload = {
    type: "comment",
    text: "Nice post",
    targetUserId: "target-1",
  };
  const actor = {
    id: "uid_like_random_7382_abcd",
  };

  const rendered = renderTemplate(payload, actor);
  assert.equal(rendered.title, "New comment");
  assert.equal(rendered.body, "Someone commented: Nice post");
  assert.ok(!rendered.body.includes(actor.id));
});

test("normalizePayload maps boomerangId into resourceId", () => {
  const payload = normalizePayload("target-1", {
    type: "like",
    boomerangId: "boom-123",
  });

  assert.equal(payload.type, "like");
  assert.equal(payload.resourceId, "boom-123");
});
