import { WebSocketServer, WebSocket } from "ws";
import { v4 as uuidv4 } from "uuid";

const PORT = Number(process.env.PORT || 8080);
const CALL_TIMEOUT_MS = 30000;

type CallState = "idle" | "initiating" | "ringing" | "connecting" | "connected" | "reconnecting" | "rejected" | "ended" | "failed" | "timed_out";

interface CallSession {
  callId: string;
  conversationId: string;
  callerId: string;
  recipientId: string;
  type: "voice" | "video";
  state: CallState;
  createdAt: number;
  timeoutHandle?: NodeJS.Timeout;
}

const sessions = new Map<string, CallSession>();
const clients = new Map<string, WebSocket>(); // userId -> socket
const rateLimits = new Map<string, number[]>();

function rateLimit(userId: string, max = 20, windowMs = 10000): boolean {
  const now = Date.now();
  const arr = (rateLimits.get(userId) || []).filter((t) => now - t < windowMs);
  if (arr.length >= max) return false;
  arr.push(now);
  rateLimits.set(userId, arr);
  return true;
}

function send(ws: WebSocket, payload: any) {
  if (ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(payload));
}

function broadcastToUser(userId: string, payload: any) {
  const ws = clients.get(userId);
  if (ws) send(ws, payload);
}

const VALID_EVENTS = new Set([
  "call.initiate", "call.ring", "call.accept", "call.reject", "call.cancel",
  "call.offer", "call.answer", "call.ice_candidate", "call.end", "call.timeout", "call.error",
]);

function validateEvent(evt: any): string | null {
  if (!evt || typeof evt !== "object") return "invalid payload";
  if (!VALID_EVENTS.has(evt.type)) return "unknown event type";
  if (!evt.callId || typeof evt.callId !== "string") return "missing callId";
  return null;
}

const wss = new WebSocketServer({ port: PORT });
console.log(`Qivora signaling server on ${PORT}`);

wss.on("connection", (ws, req) => {
  let userId: string | null = null;
  // Auth via query token (placeholder; replace with real JWT verification)
  const url = new URL(req.url || "", `http://localhost`);
  const token = url.searchParams.get("token");
  const user = url.searchParams.get("user");
  if (!token || !user) {
    ws.close(4001, "unauthorized");
    return;
  }
  // NOTE: token validation is a placeholder; integrate real auth.
  userId = user;
  clients.set(userId, ws);
  console.log(`client connected: ${userId}`);

  ws.on("message", (raw) => {
    let evt: any;
    try { evt = JSON.parse(raw.toString()); } catch { send(ws, { type: "call.error", error: "invalid json" }); return; }
    const err = validateEvent(evt);
    if (err) { send(ws, { type: "call.error", callId: evt?.callId, error: err }); return; }
    if (!userId || !rateLimit(userId)) { send(ws, { type: "call.error", callId: evt.callId, error: "rate limited" }); return; }

    const session = sessions.get(evt.callId);

    switch (evt.type) {
      case "call.initiate": {
        if (sessions.has(evt.callId)) { send(ws, { type: "call.error", callId: evt.callId, error: "duplicate callId" }); return; }
        const s: CallSession = {
          callId: evt.callId,
          conversationId: evt.conversationId,
          callerId: userId,
          recipientId: evt.recipientId,
          type: evt.callType === "video" ? "video" : "voice",
          state: "initiating",
          createdAt: Date.now(),
        };
        s.timeoutHandle = setTimeout(() => {
          s.state = "timed_out";
          broadcastToUser(s.callerId, { type: "call.timeout", callId: s.callId });
          broadcastToUser(s.recipientId, { type: "call.timeout", callId: s.callId });
          sessions.delete(s.callId);
        }, CALL_TIMEOUT_MS);
        sessions.set(s.callId, s);
        // transition to ringing
        s.state = "ringing";
        broadcastToUser(s.recipientId, { type: "call.ring", callId: s.callId, callerId: s.callerId, callType: s.type, conversationId: s.conversationId });
        send(ws, { type: "call.ring", callId: s.callId, status: "sent" });
        break;
      }
      case "call.accept": {
        if (!session || session.recipientId !== userId) { send(ws, { type: "call.error", callId: evt.callId, error: "not authorized" }); return; }
        if (session.state !== "ringing") { send(ws, { type: "call.error", callId: evt.callId, error: "invalid state" }); return; }
        if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
        session.state = "connecting";
        broadcastToUser(session.callerId, { type: "call.accept", callId: evt.callId });
        break;
      }
      case "call.reject": {
        if (!session || session.recipientId !== userId) { send(ws, { type: "call.error", callId: evt.callId, error: "not authorized" }); return; }
        if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
        session.state = "rejected";
        broadcastToUser(session.callerId, { type: "call.reject", callId: evt.callId });
        sessions.delete(session.callId);
        break;
      }
      case "call.cancel": {
        if (!session || session.callerId !== userId) { send(ws, { type: "call.error", callId: evt.callId, error: "not authorized" }); return; }
        if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
        session.state = "ended";
        broadcastToUser(session.recipientId, { type: "call.cancel", callId: evt.callId });
        sessions.delete(session.callId);
        break;
      }
      case "call.offer":
      case "call.answer":
      case "call.ice_candidate": {
        if (!session) { send(ws, { type: "call.error", callId: evt.callId, error: "no session" }); return; }
        if (session.callerId !== userId && session.recipientId !== userId) { send(ws, { type: "call.error", callId: evt.callId, error: "not participant" }); return; }
        const other = userId === session.callerId ? session.recipientId : session.callerId;
        broadcastToUser(other, evt);
        break;
      }
      case "call.end": {
        if (!session) return;
        if (session.callerId !== userId && session.recipientId !== userId) { send(ws, { type: "call.error", callId: evt.callId, error: "not participant" }); return; }
        if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
        session.state = "ended";
        broadcastToUser(session.callerId, { type: "call.end", callId: evt.callId });
        broadcastToUser(session.recipientId, { type: "call.end", callId: evt.callId });
        sessions.delete(session.callId);
        break;
      }
      case "call.timeout": {
        if (session) {
          if (session.timeoutHandle) clearTimeout(session.timeoutHandle);
          session.state = "timed_out";
          sessions.delete(session.callId);
        }
        break;
      }
      case "call.error": break;
    }
  });

  ws.on("close", () => {
    if (userId) {
      clients.delete(userId);
      // cleanup sessions involving this user
      for (const [id, s] of sessions) {
        if (s.callerId === userId || s.recipientId === userId) {
          if (s.timeoutHandle) clearTimeout(s.timeoutHandle);
          const other = s.callerId === userId ? s.recipientId : s.callerId;
          broadcastToUser(other, { type: "call.end", callId: id, reason: "peer_disconnected" });
          sessions.delete(id);
        }
      }
    }
  });
});

process.on("SIGINT", () => { wss.close(); process.exit(0); });