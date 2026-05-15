const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn, exec } = require('child_process');

const PORT = 3456;
const RENDERER_DIR = path.join(__dirname, 'renderer');
const NODE_MODULES_DIR = path.join(__dirname, 'node_modules');
const SERVER_ONLY = process.argv.includes('--server-only');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.json': 'application/json',
};

/* ── HTTP server: serves renderer/ at / and node_modules/ at /node_modules/ ── */
const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://localhost:${PORT}`);
  let pathname = url.pathname;

  let baseDir;
  if (pathname.startsWith('/node_modules/')) {
    baseDir = NODE_MODULES_DIR;
    pathname = pathname.slice('/node_modules'.length);
  } else {
    baseDir = RENDERER_DIR;
  }

  if (pathname === '/') pathname = '/index.html';

  const filePath = path.join(baseDir, pathname);
  const resolved = path.resolve(filePath);

  if (!resolved.startsWith(path.resolve(baseDir))) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.readFile(resolved, (err, data) => {
    if (err) {
      res.writeHead(404);
      res.end('Not Found');
      return;
    }
    const ext = path.extname(resolved).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

server.listen(PORT, () => {
  if (SERVER_ONLY) return; // Native app launches the browser

  console.log('');
  console.log('  ╔══════════════════════════════════════════╗');
  console.log('  ║      PDF 图片反转工具                     ║');
  console.log('  ║      http://localhost:' + String(PORT).padEnd(5) + '                    ║');
  console.log('  ╚══════════════════════════════════════════╝');
  console.log('');

  // Try launching in Safari
  exec(`open -a Safari http://localhost:${PORT}`, (err) => {
    if (err) {
      exec(`open http://localhost:${PORT}`); // fallback to default browser
    }
  });
});

process.on('SIGINT', () => {
  server.close();
  process.exit(0);
});
