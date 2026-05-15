pdfjsLib.GlobalWorkerOptions.workerSrc = '/node_modules/pdfjs-dist/build/pdf.worker.min.js';

/* ── Native Bridge (WKWebView) ── */
const isNative = !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge);

async function nativeCall(method, args = {}) {
  return window.callNative(method, args);
}

/* ── State ── */
const state = {
  items: [],        // { id, name, originalUrl, invertedUrl }
  selected: new Set(),
  idCounter: 0,
};

/* ── DOM refs ── */
const uploadZone = document.getElementById('uploadZone');
const fileInput = document.getElementById('fileInput');
const grid = document.getElementById('grid');
const totalCount = document.getElementById('totalCount');
const selectedCount = document.getElementById('selectedCount');
const statusText = document.getElementById('statusText');
const selectAllBtn = document.getElementById('selectAllBtn');
const deselectAllBtn = document.getElementById('deselectAllBtn');
const saveToFolderBtn = document.getElementById('saveToFolderBtn');
const generatePdfBtn = document.getElementById('generatePdfBtn');
const clearAllBtn = document.getElementById('clearAllBtn');
const toastContainer = document.getElementById('toastContainer');

/* ── Toast ── */
function toast(msg, type = 'success') {
  const el = document.createElement('div');
  el.className = `toast ${type}`;
  el.textContent = msg;
  toastContainer.appendChild(el);
  setTimeout(() => { el.style.opacity = '0'; el.style.transition = 'opacity 0.3s'; }, 2500);
  setTimeout(() => el.remove(), 3000);
}

/* ── Status ── */
function setStatus(text, loading = false) {
  statusText.textContent = text;
  statusText.classList.toggle('loading', loading);
}

/* ── Update UI ── */
function updateCounts() {
  totalCount.textContent = state.items.length;
  selectedCount.textContent = state.selected.size;
}

function updateButtons() {
  const hasItems = state.items.length > 0;
  const hasSelected = state.selected.size > 0;
  selectAllBtn.disabled = !hasItems;
  deselectAllBtn.disabled = !hasItems;
  generatePdfBtn.disabled = !hasItems;
  saveToFolderBtn.disabled = !hasSelected;
  clearAllBtn.disabled = !hasItems;
}

function renderGrid() {
  if (state.items.length === 0) {
    grid.innerHTML = '<div class="empty-state"><span class="icon">🖼</span><div>上传 PDF 或图片文件，自动生成反转预览</div></div>';
    updateCounts();
    updateButtons();
    return;
  }

  let html = '';
  for (const item of state.items) {
    const checked = state.selected.has(item.id) ? 'checked' : '';
    html += `
      <div class="card${checked ? ' selected' : ''}" data-id="${item.id}">
        <div class="card-check">
          <input type="checkbox" ${checked} data-id="${item.id}">
        </div>
        <div class="card-image-wrap">
          <img class="img-inverted" src="${item.invertedUrl}" alt="${item.name}" loading="lazy">
          <img class="img-original" src="${item.originalUrl}" alt="${item.name} 原图" loading="lazy">
        </div>
        <button class="card-download" data-id="${item.id}" title="下载此图片">⬇</button>
        <div class="card-label">${item.name}</div>
      </div>`;
  }
  grid.innerHTML = html;
  updateCounts();
  updateButtons();
}

/* ── Selection ── */
function selectAll() {
  state.selected = new Set(state.items.map(i => i.id));
  renderGrid();
}

function deselectAll() {
  state.selected.clear();
  renderGrid();
}

function toggleSelection(id, checked) {
  if (checked) state.selected.add(id);
  else state.selected.delete(id);
  const card = grid.querySelector(`.card[data-id="${id}"]`);
  if (card) {
    card.classList.toggle('selected', checked);
    const cb = card.querySelector('input[type="checkbox"]');
    if (cb) cb.checked = checked;
  }
  updateCounts();
  updateButtons();
}

/* ── Grid event delegation ── */
grid.addEventListener('click', (e) => {
  const cb = e.target.closest('input[type="checkbox"]');
  if (cb) {
    toggleSelection(+cb.dataset.id, cb.checked);
    return;
  }
  const dlBtn = e.target.closest('.card-download');
  if (dlBtn) {
    const id = +dlBtn.dataset.id;
    const item = state.items.find(i => i.id === id);
    if (item) downloadSingle(item);
    return;
  }
});

/* ── Download single ── */
async function downloadSingle(item) {
  if (isNative) {
    try {
      const result = await nativeCall('downloadSingleImage', {
        name: item.name,
        dataUrl: item.invertedUrl,
      });
      if (result && result.success) toast('图片已保存');
    } catch (err) {
      if (err.code !== 'CANCELLED') toast('下载失败', 'error');
    }
  } else {
    const a = document.createElement('a');
    a.href = item.invertedUrl;
    a.download = item.name + '.png';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    toast('图片已保存');
  }
}

/* ── Generate PDF ── */
async function generatePDF() {
  const items = state.items;
  if (items.length === 0) { toast('没有可导出的图片', 'error'); return; }

  const { jsPDF } = window.jspdf;
  setStatus('正在生成 PDF…', true);

  try {
    const doc = new jsPDF({ orientation: 'portrait', unit: 'pt', format: 'a4', compress: true });
    const pageW = 595.28;
    const pageH = 841.89;

    for (let i = 0; i < items.length; i++) {
      if (i > 0) doc.addPage();

      const img = await new Promise((resolve, reject) => {
        const imgEl = new Image();
        imgEl.onload = () => resolve(imgEl);
        imgEl.onerror = reject;
        imgEl.src = items[i].invertedUrl;
      });

      const scale = Math.min(pageW / img.naturalWidth, pageH / img.naturalHeight);
      const w = img.naturalWidth * scale;
      const h = img.naturalHeight * scale;

      doc.addImage(items[i].invertedUrl, 'PNG', (pageW - w) / 2, (pageH - h) / 2, w, h);
    }

    const pdfDataUrl = doc.output('datauristring');
    const pdfName = items[0].name.replace(/_(p\d+)?$/, '') + '_反转输出.pdf';

    if (isNative) {
      const result = await nativeCall('savePDF', { fileName: pdfName, dataUrl: pdfDataUrl });
      if (result && result.success) {
        setStatus('PDF 已生成');
        toast('PDF 已保存');
      }
    } else {
      const a = document.createElement('a');
      a.href = pdfDataUrl;
      a.download = pdfName;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      setStatus('PDF 已生成');
      toast('PDF 已保存');
    }
  } catch (err) {
    console.error(err);
    setStatus('PDF 生成失败');
    toast('PDF 生成失败', 'error');
  }
}

/* ── Save to folder ── */
async function saveToFolder() {
  const selected = state.items.filter(i => state.selected.has(i.id));
  if (selected.length === 0) { toast('请先选择图片', 'error'); return; }

  if (isNative) {
    let dirPath;
    try {
      dirPath = await nativeCall('selectFolder');
    } catch (err) {
      if (err.code !== 'CANCELLED') toast('选择文件夹失败', 'error');
      return;
    }

    setStatus('正在保存…', true);
    try {
      const items = selected.map(item => ({
        name: item.name,
        dataUrl: item.invertedUrl,
      }));
      const result = await nativeCall('saveImagesToFolder', { dirPath, items });
      setStatus(`${result.count} 张图片已保存`);
      toast(`成功保存 ${result.count} 张图片`);
    } catch (err) {
      console.error(err);
      setStatus('保存失败');
      toast('保存失败', 'error');
    }
  } else {
    // Browser fallback: save each image individually
    for (const item of selected) {
      downloadSingle(item);
    }
    if (selected.length > 1) toast(`已下载 ${selected.length} 张图片`);
  }
}

/* ── Clear all ── */
function clearAll() {
  if (state.items.length === 0) return;
  for (const item of state.items) {
    URL.revokeObjectURL(item.originalUrl);
    URL.revokeObjectURL(item.invertedUrl);
  }
  state.items = [];
  state.selected.clear();
  renderGrid();
  setStatus('已清空全部');
  toast('已清空所有图片');
}

/* ── Shared Canvas for reuse ── */
let sharedCanvas = null;
function getSharedCanvas(w, h) {
  if (!sharedCanvas) sharedCanvas = document.createElement('canvas');
  if (sharedCanvas.width !== w || sharedCanvas.height !== h) {
    sharedCanvas.width = w;
    sharedCanvas.height = h;
  }
  return sharedCanvas;
}

/* ── Chunked grayscale + invert (yields to UI via rAF) ── */
async function invertPixels(ctx, w, h) {
  const imageData = ctx.getImageData(0, 0, w, h);
  const d = imageData.data;
  const CHUNK = 500000; // pixels per chunk (~2M bytes)
  const totalPixels = w * h;

  for (let offset = 0; offset < totalPixels; offset += CHUNK) {
    const end = Math.min(offset + CHUNK, totalPixels);
    const startIdx = offset * 4;
    const endIdx = end * 4;

    for (let j = startIdx; j < endIdx; j += 4) {
      const gray = 0.299 * d[j] + 0.587 * d[j + 1] + 0.114 * d[j + 2];
      const val = 255 - Math.round(gray);
      d[j] = val;
      d[j + 1] = val;
      d[j + 2] = val;
    }

    if (end < totalPixels) {
      await new Promise(r => requestAnimationFrame(r));
    }
  }
  ctx.putImageData(imageData, 0, 0);
}

/* ── Image Processing ── */
async function processImage(file) {
  const url = URL.createObjectURL(file);
  const img = await new Promise((resolve, reject) => {
    const el = new Image();
    el.onload = () => resolve(el);
    el.onerror = reject;
    el.src = url;
  });

  const canvas = getSharedCanvas(img.naturalWidth, img.naturalHeight);
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0);
  URL.revokeObjectURL(url);

  const originalUrl = canvas.toDataURL('image/png');

  await invertPixels(ctx, canvas.width, canvas.height);
  const invertedUrl = canvas.toDataURL('image/png');

  return [{
    id: ++state.idCounter,
    name: file.name.replace(/\.[^.]+$/, ''),
    originalUrl,
    invertedUrl,
  }];
}

/* ── PDF Processing (progressive: yields each page) ── */
async function* processPDFPages(file) {
  const arrayBuffer = await file.arrayBuffer();
  const pdf = await pdfjsLib.getDocument({ data: arrayBuffer }).promise;
  const baseName = file.name.replace(/\.pdf$/i, '');

  for (let i = 1; i <= pdf.numPages; i++) {
    const page = await pdf.getPage(i);
    const scale = Math.min(2, 1800 / Math.max(page.view[2], page.view[3]));
    const viewport = page.getViewport({ scale });

    const canvas = getSharedCanvas(viewport.width, viewport.height);
    const ctx = canvas.getContext('2d');

    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    await page.render({ canvasContext: ctx, viewport }).promise;

    const originalUrl = canvas.toDataURL('image/png');

    await invertPixels(ctx, canvas.width, canvas.height);
    const invertedUrl = canvas.toDataURL('image/png');

    yield {
      id: ++state.idCounter,
      name: `${baseName}_p${i}`,
      originalUrl,
      invertedUrl,
    };
  }
}

async function handleFiles(files) {
  const pdfs = [];
  const imgs = [];
  for (const f of files) {
    if (f.type === 'application/pdf' || f.name.toLowerCase().endsWith('.pdf')) {
      pdfs.push(f);
    } else if (f.type.startsWith('image/')) {
      imgs.push(f);
    }
  }

  if (pdfs.length === 0 && imgs.length === 0) {
    toast('请上传 PDF 或图片文件', 'error');
    return;
  }

  if (state.items.length === 0) grid.innerHTML = '';

  let total = 0;

  // Process PDFs page-by-page, rendering each page immediately
  for (const file of pdfs) {
    try {
      let pageCount = 0;
      for await (const item of processPDFPages(file)) {
        state.items.push(item);
        total++;
        pageCount++;
        setStatus(`正在处理 PDF: ${file.name} (第 ${pageCount} 页)`, true);
        renderGrid();
        // Yield to keep UI responsive between pages
        await new Promise(r => requestAnimationFrame(r));
      }
    } catch (err) {
      console.error(err);
      toast(`处理 "${file.name}" 失败`, 'error');
    }
  }

  // Process images with chunked pixel ops (non-blocking)
  for (const file of imgs) {
    try {
      setStatus(`正在处理图片: ${file.name}`, true);
      const items = await processImage(file);
      state.items.push(...items);
      total += items.length;
      renderGrid();
    } catch (err) {
      console.error(err);
      toast(`处理 "${file.name}" 失败`, 'error');
    }
  }

  setStatus(`就绪 — 共 ${state.items.length} 张图片`);
  if (total > 0) toast(`成功处理 ${pdfs.length + imgs.length} 个文件，共 ${total} 张图片`);
}

/* ── Upload: click ── */
uploadZone.addEventListener('click', () => fileInput.click());
fileInput.addEventListener('change', () => {
  if (fileInput.files.length) {
    handleFiles(fileInput.files);
    fileInput.value = '';
  }
});

/* ── Upload: drag & drop ── */
uploadZone.addEventListener('dragover', (e) => {
  e.preventDefault();
  uploadZone.classList.add('drag-over');
});
uploadZone.addEventListener('dragleave', () => {
  uploadZone.classList.remove('drag-over');
});
uploadZone.addEventListener('drop', (e) => {
  e.preventDefault();
  uploadZone.classList.remove('drag-over');
  if (e.dataTransfer.files.length) {
    handleFiles(e.dataTransfer.files);
  }
});

/* ── Action buttons ── */
selectAllBtn.addEventListener('click', selectAll);
deselectAllBtn.addEventListener('click', deselectAll);
saveToFolderBtn.addEventListener('click', saveToFolder);
generatePdfBtn.addEventListener('click', generatePDF);
clearAllBtn.addEventListener('click', clearAll);

/* ── Keyboard shortcuts ── */
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') deselectAll();
});

/* ── Init ── */
updateCounts();
updateButtons();
