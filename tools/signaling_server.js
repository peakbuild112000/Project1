'use strict';

// Minimal WebSocket signaling relay for Climb Together WebRTC rooms.
// It never sees game traffic: it only forwards SDP offers, answers and ICE
// candidates between the players of the same room.

const http = require('http');
const { WebSocketServer } = require('ws');

const PORT = Number(process.env.PORT || 9080);
const HOST = process.env.HOST || '0.0.0.0';
const MAX_PLAYERS = 4;
const ROOM_CODE = /^[A-Z0-9]{3,12}$/;

const rooms = new Map();

const server = http.createServer((request, response) => {
  if (request.url === '/health') {
    response.writeHead(200, { 'content-type': 'text/plain' });
    response.end('ok\n');
    return;
  }
  response.writeHead(404);
  response.end();
});

const wss = new WebSocketServer({ server, maxPayload: 65536 });

function send(ws, payload) {
  if (ws.readyState === 1) {
    ws.send(JSON.stringify(payload));
  }
}

function fail(ws, message) {
  send(ws, { type: 'error', message });
}

function leaveRoom(ws) {
  const room = rooms.get(ws.room);
  if (!room) {
    ws.room = null;
    ws.peerId = 0;
    return;
  }
  const leftId = ws.peerId;
  room.clients.delete(leftId);
  for (const [peerId, peer] of room.clients) {
    send(peer, { type: 'peer_left', id: leftId });
  }
  if (leftId === 1) {
    for (const peer of room.clients.values()) {
      send(peer, { type: 'error', message: 'The host closed the room.' });
    }
    room.clients.clear();
  }
  if (room.clients.size === 0) {
    rooms.delete(room.code);
  }
  ws.room = null;
  ws.peerId = 0;
  console.log(`[room ${room.code}] player ${leftId} left`);
}

function createRoom(ws, data) {
  if (ws.room) {
    leaveRoom(ws);
  }
  const code = String(data.room || '').toUpperCase();
  if (!ROOM_CODE.test(code)) {
    fail(ws, 'Room code must be 3 to 12 letters or digits.');
    return;
  }
  if (rooms.has(code)) {
    fail(ws, 'That room already exists. Choose another code.');
    return;
  }
  const room = { code, clients: new Map() };
  rooms.set(code, room);
  ws.room = code;
  ws.peerId = 1;
  room.clients.set(1, ws);
  send(ws, { type: 'created', id: 1, room: code });
  console.log(`[room ${code}] opened by host`);
}

function joinRoom(ws, data) {
  if (ws.room) {
    leaveRoom(ws);
  }
  const code = String(data.room || '').toUpperCase();
  const room = rooms.get(code);
  if (!room) {
    fail(ws, 'No room with that code is open.');
    return;
  }
  if (room.clients.size >= MAX_PLAYERS) {
    fail(ws, 'The room is full (4 players maximum).');
    return;
  }
  let nextId = 2;
  while (room.clients.has(nextId) && nextId <= MAX_PLAYERS) {
    nextId += 1;
  }
  if (nextId > MAX_PLAYERS) {
    fail(ws, 'The room is full (4 players maximum).');
    return;
  }
  ws.room = code;
  ws.peerId = nextId;
  room.clients.set(nextId, ws);
  send(ws, {
    type: 'joined',
    id: nextId,
    room: code,
    peers: Array.from(room.clients.keys()),
  });
  for (const [peerId, peer] of room.clients) {
    if (peerId !== nextId) {
      send(peer, { type: 'peer_joined', id: nextId });
    }
  }
  console.log(`[room ${code}] player ${nextId} joined`);
}

function relay(ws, data, kind) {
  const room = rooms.get(ws.room);
  if (!room) {
    return;
  }
  const targetId = Number(data.to || 0);
  const target = room.clients.get(targetId);
  if (!target || target === ws) {
    return;
  }
  const senderId = Number(ws.peerId || 0);
  if (senderId < 1 || !room.clients.has(senderId)) {
    return;
  }
  if (kind === 'offer' || kind === 'answer') {
    const sdp = String(data.sdp || '');
    if (sdp.length === 0 || sdp.length > 40000) {
      return;
    }
    send(target, { type: kind, from: senderId, to: targetId, sdp });
    return;
  }
  send(target, {
    type: 'ice',
    from: senderId,
    to: targetId,
    media: String(data.media || ''),
    index: Number(data.index || 0),
    name: String(data.name || ''),
  });
}

wss.on('connection', (ws) => {
  ws.room = null;
  ws.peerId = 0;

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw.toString());
    } catch (error) {
      return;
    }
    if (!data || typeof data !== 'object') {
      return;
    }
    switch (data.type) {
      case 'create':
        createRoom(ws, data);
        break;
      case 'join':
        joinRoom(ws, data);
        break;
      case 'offer':
      case 'answer':
        relay(ws, data, data.type);
        break;
      case 'ice':
        relay(ws, data, 'ice');
        break;
      case 'leave':
        leaveRoom(ws);
        break;
      default:
        break;
    }
  });

  ws.on('close', () => leaveRoom(ws));
  ws.on('error', () => leaveRoom(ws));
});

server.listen(PORT, HOST, () => {
  console.log(`Climb Together signaling server listening on ${HOST}:${PORT}`);
});
