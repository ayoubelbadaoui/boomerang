"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.renderTemplate = renderTemplate;
const constants_1 = require("../config/constants");
const fallbackActor = (actor) => actor?.username ?? actor?.id ?? 'Someone';
const templates = {
    follow: (_payload, actor) => ({
        title: 'New follower',
        body: `${fallbackActor(actor)} followed you`,
    }),
    follow_back: (_payload, actor) => ({
        title: 'Follow back',
        body: `${fallbackActor(actor)} followed you back`,
    }),
    follow_request: (_payload, actor) => ({
        title: 'Follow request',
        body: `${fallbackActor(actor)} requested to follow you`,
    }),
    like: (_payload, actor) => ({
        title: 'New like',
        body: `${fallbackActor(actor)} liked your boomerang`,
    }),
    comment: (payload, actor) => ({
        title: 'New comment',
        body: `${fallbackActor(actor)} commented: ${truncateText(payload.text)}`,
    }),
    reply: (payload, actor) => ({
        title: 'New reply',
        body: `${fallbackActor(actor)} replied: ${truncateText(payload.text)}`,
    }),
};
const truncateText = (text, max = 80) => {
    if (!text)
        return '';
    return text.length > max ? `${text.slice(0, max - 1)}…` : text;
};
function renderTemplate(payload, actor) {
    const template = templates[payload.type];
    if (template)
        return template(payload, actor);
    return {
        title: constants_1.APP_NAME,
        body: 'You have a new notification',
    };
}
//# sourceMappingURL=templates.js.map