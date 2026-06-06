import http from 'http';
import fs from 'fs';
import path from 'path';
import net from 'net';

const VSCODE_PORT = parseInt(process.env.VSCODE_PORT || '3000');
const PORT = parseInt(process.env.FILE_SERVER_PORT || '3001');
const TOKEN = process.env.CONNECTION_TOKEN || '';
const FILES_PREFIX = '/files';

const ROOT_DIR = '/';
const CACHE = {};

function formatSize(bytes) {
  if (bytes === 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  const i = Math.floor(Math.log(bytes) / Math.log(1024));
  return (bytes / Math.pow(1024, i)).toFixed(i > 0 ? 1 : 0) + ' ' + units[i];
}

function getEntries(dirPath) {
  try {
    const items = fs.readdirSync(dirPath, { withFileTypes: true });
    return items
      .filter(e => !e.name.startsWith('.'))
      .map(e => {
        const fullPath = path.join(dirPath, e.name);
        let stat;
        try { stat = fs.statSync(fullPath); } catch { return null; }
        return {
          name: e.name,
          isDir: e.isDirectory() || (!e.isFile() && stat.isDirectory()),
          size: stat.size,
          mtime: stat.mtime,
        };
      })
      .filter(Boolean)
      .sort((a, b) => {
        if (a.isDir !== b.isDir) return a.isDir ? -1 : 1;
        return a.name.localeCompare(b.name);
      });
  } catch {
    return null;
  }
}

function getBreadcrumbs(relPath) {
  const parts = relPath.split('/').filter(Boolean);
  const crumbs = [{ name: 'Root', path: FILES_PREFIX + '/' }];
  let accumulated = '';
  for (const p of parts) {
    accumulated += '/' + p;
    crumbs.push({ name: p, path: FILES_PREFIX + accumulated });
  }
  return crumbs;
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function renderDirHTML(relPath, entries) {
  const bc = getBreadcrumbs(relPath);
  const rows = entries.map(e => {
    const fullRel = relPath === '/' ? e.name : relPath + '/' + e.name;
    const url = FILES_PREFIX + (e.isDir ? fullRel : fullRel + '?download=1');
    const icon = e.isDir ? '&#128193;' : '&#128196;';
    return `<tr>
      <td class="name-col"><a href="${url}">${icon} ${escapeHtml(e.name)}</a></td>
      <td class="size-col">${e.isDir ? '-' : formatSize(e.size)}</td>
      <td class="date-col">${e.mtime.toISOString().slice(0, 16).replace('T', ' ')}</td>
    </tr>`;
  }).join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Files - ${escapeHtml(relPath)}</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#1e1e1e;color:#d4d4d4;min-height:100vh}
  .top{position:sticky;top:0;z-index:10;background:#252526;border-bottom:1px solid #3c3c3c;padding:16px 20px}
  .top h1{font-size:20px;font-weight:600;color:#e0e0e0;margin-bottom:8px}
  .nav{display:flex;align-items:center;gap:8px;font-size:14px;flex-wrap:wrap;margin-bottom:10px}
  .nav a{color:#569cd6;text-decoration:none;padding:2px 4px;border-radius:3px}
  .nav a:hover{background:#2a2d2e;text-decoration:underline}
  .nav .sep{color:#6e6e6e;user-select:none}
  .search{width:100%;padding:8px 12px;background:#3c3c3c;border:1px solid #555;border-radius:4px;color:#d4d4d4;font-size:14px;outline:none}
  .search:focus{border-color:#569cd6}
  .search::placeholder{color:#888}
  table{width:100%;border-collapse:collapse;table-layout:fixed}
  th{background:#2d2d2d;padding:10px 16px;font-size:12px;font-weight:600;text-transform:uppercase;color:#aaa;cursor:pointer;user-select:none;border-bottom:2px solid #3c3c3c;position:sticky;top:130px}
  th:hover{color:#d4d4d4}
  th .sort{color:#888;margin-left:4px}
  td{padding:8px 16px;border-bottom:1px solid #2d2d2d;font-size:14px}
  tr:hover td{background:#2a2d2e}
  .name-col a{color:#d4d4d4;text-decoration:none;display:flex;align-items:center;gap:6px}
  .name-col a:hover{color:#569cd6}
  .size-col{text-align:right;width:120px;color:#888}
  .date-col{width:160px;color:#888}
  .empty{padding:40px;text-align:center;color:#888}
  @media(max-width:600px){.date-col{display:none}.top{padding:12px 8px}td,th{padding:6px 8px}}
</style>
</head>
<body>
<div class="top">
  <h1>&#128193; Files</h1>
  <div class="nav">
    ${bc.map((c, i) => i < bc.length - 1
      ? `<a href="${escapeHtml(c.path)}">${escapeHtml(c.name)}</a><span class="sep">/</span>`
      : `<span style="color:#e0e0e0">${escapeHtml(c.name)}</span>`
    ).join('')}
  </div>
  <input class="search" type="text" id="search" placeholder="Filter files..." oninput="filterFiles(this.value)" autofocus>
</div>
<table>
  <thead>
    <tr>
      <th class="name-col" onclick="sortTable(0)">Name<span class="sort" id="s0"></span></th>
      <th class="size-col" onclick="sortTable(1)">Size<span class="sort" id="s1"></span></th>
      <th class="date-col" onclick="sortTable(2)">Modified<span class="sort" id="s2"></span></th>
    </tr>
  </thead>
  <tbody id="tbody">
    ${rows}
  </tbody>
</table>
<div class="empty" id="empty" style="display:none">No files match filter</div>
<script>
  function filterFiles(q) {
    const tbody = document.getElementById('tbody');
    const empty = document.getElementById('empty');
    let visible = 0;
    tbody.querySelectorAll('tr').forEach(tr => {
      const match = tr.children[0].textContent.toLowerCase().includes(q.toLowerCase());
      tr.style.display = match ? '' : 'none';
      if (match) visible++;
    });
    empty.style.display = visible === 0 ? 'block' : 'none';
  }
  let sortState = {};
  function sortTable(col) {
    const tbody = document.getElementById('tbody');
    const rows = Array.from(tbody.querySelectorAll('tr'));
    sortState[col] = !sortState[col];
    const dir = sortState[col] ? 1 : -1;
    document.querySelectorAll('.sort').forEach((el, i) => el.textContent = i === col ? (dir === 1 ? '▲' : '▼') : '');
    rows.sort((a, b) => {
      let va = a.children[col].textContent.trim();
      let vb = b.children[col].textContent.trim();
      if (col === 1) { va = va === '-' ? '-1' : va; vb = vb === '-' ? '-1' : vb; }
      const na = parseFloat(va), nb = parseFloat(vb);
      if (!isNaN(na) && !isNaN(nb)) return (na - nb) * dir;
      return va.localeCompare(vb) * dir;
    });
    rows.forEach(r => tbody.appendChild(r));
  }
</script>
</body>
</html>`;
}

function handleFileRequest(req, res, url) {
  let relPath = decodeURIComponent(url.pathname.slice(FILES_PREFIX.length) || '/');
  if (!relPath.startsWith('/')) relPath = '/' + relPath;
  relPath = path.normalize(relPath).replace(/\/$/, '') || '/';

  const fullPath = path.resolve(ROOT_DIR, '.' + relPath);

  if (!fullPath.startsWith(path.resolve(ROOT_DIR))) {
    res.writeHead(403);
    return res.end('Forbidden');
  }

  try {
    const stat = fs.statSync(fullPath);

    if (stat.isDirectory()) {
      const entries = getEntries(fullPath);
      if (entries === null) {
        res.writeHead(403);
        return res.end('Permission denied');
      }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      return res.end(renderDirHTML(relPath, entries));
    }

    if (stat.isFile()) {
      const ext = path.extname(fullPath).toLowerCase();
      const mimeMap = {
        '.txt': 'text/plain', '.html': 'text/html', '.css': 'text/css',
        '.js': 'application/javascript', '.json': 'application/json',
        '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
        '.gif': 'image/gif', '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
        '.pdf': 'application/pdf', '.zip': 'application/zip',
        '.tar': 'application/x-tar', '.gz': 'application/gzip',
        '.apk': 'application/vnd.android.package-archive',
      };
      const contentType = mimeMap[ext] || 'application/octet-stream';
      const isDownload = url.searchParams.has('download');

      if (isDownload || ext === '.apk' || ext === '.zip' || ext === '.gz' || ext === '.tar') {
        res.writeHead(200, {
          'Content-Type': contentType,
          'Content-Disposition': `attachment; filename="${encodeURIComponent(path.basename(fullPath))}"`,
          'Content-Length': stat.size,
          'Cache-Control': 'no-cache',
        });
        fs.createReadStream(fullPath).pipe(res);
      } else {
        res.writeHead(200, {
          'Content-Type': contentType + '; charset=utf-8',
          'Content-Length': stat.size,
        });
        fs.createReadStream(fullPath).pipe(res);
      }
      return;
    }

    res.writeHead(404);
    res.end('Not found');
  } catch (err) {
    if (err.code === 'ENOENT' || err.code === 'ENOTDIR') {
      res.writeHead(404);
      return res.end('Not found');
    }
    if (err.code === 'EACCES' || err.code === 'EPERM') {
      res.writeHead(403);
      return res.end('Permission denied');
    }
    res.writeHead(500);
    res.end('Internal error');
  }
}

function proxyToVSCode(req, res) {
  const options = {
    hostname: '127.0.0.1',
    port: VSCODE_PORT,
    path: req.url,
    method: req.method,
    headers: { ...req.headers, host: `localhost:${VSCODE_PORT}` },
  };

  const proxyReq = http.request(options, proxyRes => {
    const resh = { ...proxyRes.headers };
    delete resh['transfer-encoding'];
    res.writeHead(proxyRes.statusCode, resh);
    proxyRes.pipe(res);
  });

  proxyReq.on('error', err => {
    if (!res.headersSent) {
      res.writeHead(502, { 'Content-Type': 'text/plain' });
      res.end('Bad Gateway: ' + err.message);
    }
  });

  req.pipe(proxyReq);
}

function checkToken(req, url) {
  if (!TOKEN) return true;
  const queryToken = url.searchParams.get('tkn');
  const headerToken = req.headers['x-auth-token'];
  return queryToken === TOKEN || headerToken === TOKEN;
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (url.pathname === '/health') {
    res.writeHead(200);
    return res.end('ok');
  }

  if (url.pathname.startsWith(FILES_PREFIX)) {
    if (!checkToken(req, url)) {
      res.writeHead(401, { 'Content-Type': 'text/plain' });
      return res.end('Unauthorized — provide ?tkn=TOKEN in URL or X-Auth-Token header');
    }
    return handleFileRequest(req, res, url);
  }

  proxyToVSCode(req, res);
});

server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);

  if (url.pathname.startsWith(FILES_PREFIX)) {
    socket.destroy();
    return;
  }

  const conn = net.connect(VSCODE_PORT, '127.0.0.1', () => {
    conn.write(
      req.method + ' ' + req.url + ' HTTP/1.1\r\n' +
      Object.entries(req.headers).map(([k, v]) => k + ': ' + v + '\r\n').join('') +
      '\r\n'
    );
    if (head && head.length > 0) conn.write(head);
    conn.pipe(socket);
    socket.pipe(conn);
  });

  conn.on('error', () => { try { socket.destroy(); } catch {} });
  socket.on('error', () => { try { conn.destroy(); } catch {} });
});

server.listen(PORT, '0.0.0.0', () => {
  process.stdout.write('file-server listening on port ' + PORT + '\n');
});
